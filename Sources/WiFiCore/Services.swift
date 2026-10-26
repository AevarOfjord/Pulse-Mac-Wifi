import Foundation
import CoreWLAN
import SystemConfiguration
import Darwin

public struct CommandResult: Sendable {
    public let output: Data
    public let status: Int32
}

// Only fixed, read-only system commands are used. No shell, sudo, settings
// mutations, credential reads, or caller-supplied executable paths.
public final class CommandHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var timedOut = false
    public init() {}
    public func cancel(timeout: Bool = false) {
        lock.lock()
        cancelled = true; timedOut = timedOut || timeout
        if let process, process.isRunning { process.terminate() }
        lock.unlock()
    }
    private func launch(_ p: Process) throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw MeasurementError.cancelled }
        process = p
        do { try p.run() } catch { process = nil; throw MeasurementError.commandFailed }
    }
    private func finish() throws {
        lock.lock(); defer { lock.unlock() }
        process = nil
        if timedOut { throw MeasurementError.timeout }
        if cancelled { throw MeasurementError.cancelled }
    }
    public func run(executable: String, arguments: [String], timeout: Double) async throws -> CommandResult {
        try await withTaskCancellationHandler(operation: {
            try await Task.detached(priority: .utility) { [self] in
                let p = Process()
                p.executableURL = URL(fileURLWithPath: executable)
                p.arguments = arguments
                p.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C", "LANG": "C"]) { _, new in new }
                let output = Pipe()
                p.standardOutput = output
                // Discard stderr: diagnostics can contain private network names.
                p.standardError = FileHandle.nullDevice
                try launch(p)
                let deadline = DispatchWorkItem { [weak self] in self?.cancel(timeout: true) }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: deadline)
                var data = Data()
                while true {
                    let next = output.fileHandleForReading.availableData
                    if next.isEmpty { break }
                    if data.count + next.count <= 1_048_576 { data.append(next) }
                    else { cancel() }
                }
                p.waitUntilExit()
                deadline.cancel()
                try finish()
                return CommandResult(output: data, status: p.terminationStatus)
            }.value
        }, onCancel: { [self] in cancel() })
    }
}

public actor WiFiSampler {
    private var firewall: Bool?
    private var stealth: Bool?
    private var firewallDate: Date?
    public init() {}

    public func capture(forceProtection: Bool = false) async -> WiFiSnapshot {
        if forceProtection || firewallDate == nil || Date().timeIntervalSince(firewallDate!) >= 60 {
            async let global = CommandHandle().run(executable: "/usr/libexec/ApplicationFirewall/socketfilterfw", arguments: ["--getglobalstate"], timeout: 4)
            async let hidden = CommandHandle().run(executable: "/usr/libexec/ApplicationFirewall/socketfilterfw", arguments: ["--getstealthmode"], timeout: 4)
            let g = try? await global; let h = try? await hidden
            firewall = g.flatMap { FirewallParser.state(String(decoding: $0.output, as: UTF8.self), exitCode: $0.status) }
            stealth = h.flatMap { FirewallParser.stealth(String(decoding: $0.output, as: UTF8.self), exitCode: $0.status) }
            firewallDate = Date()
        }
        var result = WiFiSnapshot()
        result.firewall = firewall; result.stealth = stealth; result.firewallDate = firewallDate
        guard let wifi = CWWiFiClient.shared().interface() else {
            result.error = "No Wi-Fi interface is available on this Mac."
            return result
        }
        result.poweredOn = wifi.powerOn()
        result.interface = wifi.interfaceName
        result.associated = result.poweredOn && wifi.interfaceMode() == .station
        guard result.associated else { return result }
        result.ssid = wifi.ssid()
        result.bssid = wifi.bssid()
        // Recent macOS releases can redact Wi-Fi identifiers and return an
        // apparent zero security value before Location authorization. Do not
        // turn that missing access into an "open network" warning.
        result.security = result.ssid == nil ? .unknown : WiFiSecurity(systemValue: wifi.security().rawValue)
        let signal = wifi.rssiValue(); let noise = wifi.noiseMeasurement()
        result.signal = (-120 ... -1).contains(signal) ? signal : nil
        result.noise = (-130 ... -1).contains(noise) ? noise : nil
        let rate = wifi.transmitRate()
        result.linkMbps = rate > 0 && rate.isFinite ? rate : nil
        if let channel = wifi.wlanChannel() {
            result.channel = channel.channelNumber
            switch channel.channelBand.rawValue {
            case 1: result.band = "2.4 GHz"
            case 2: result.band = "5 GHz"
            case 3: result.band = "6 GHz"
            default: break
            }
        }
        if let interface = result.interface, let store = SCDynamicStoreCreate(nil, "PulseWiFi" as CFString, nil, nil) {
            let key = "State:/Network/Interface/\(interface)/IPv4" as CFString
            if let ipv4 = SCDynamicStoreCopyValue(store, key) as? [String: Any] {
                result.localIP = (ipv4["Addresses"] as? [String])?.first
            }
            if let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] {
                result.router = global["Router"] as? String
            }
        }
        return result
    }
}

private final class ProbeDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public enum ConnectionTester {
    public static func run() async -> ConnectionReport {
        var result = ConnectionReport()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: config, delegate: ProbeDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        // Full DNS/TLS/HTTP response time, deliberately labelled HTTPS latency.
        for _ in 0..<3 {
            if Task.isCancelled { result.cancelled = true; return result }
            result.attempts += 1
            let began = ProcessInfo.processInfo.systemUptime
            do {
                let request = URLRequest(url: URL(string: "https://www.apple.com/library/test/success.html")!)
                let (bytes, response) = try await session.bytes(for: request)
                var body = Data()
                for try await byte in bytes {
                    body.append(byte)
                    if body.count >= 16_384 { break }
                }
                if let http = response as? HTTPURLResponse, http.statusCode == 200,
                   String(decoding: body, as: UTF8.self).contains("<TITLE>Success</TITLE>") {
                    result.durations.append((ProcessInfo.processInfo.systemUptime - began) * 1000)
                }
            } catch { if Task.isCancelled { result.cancelled = true; return result } }
        }
        if !Task.isCancelled {
            do {
                let request = URLRequest(url: URL(string: "http://captive.apple.com/hotspot-detect.html")!)
                let (bytes, response) = try await session.bytes(for: request)
                var body = Data()
                for try await byte in bytes { body.append(byte); if body.count >= 16_384 { break } }
                if let http = response as? HTTPURLResponse {
                    result.portalSuspected = http.statusCode != 200 || !String(decoding: body, as: UTF8.self).contains("<TITLE>Success</TITLE>")
                }
            } catch { /* A blocked HTTP probe alone is not evidence of a captive portal. */ }
        }
        result.cancelled = Task.isCancelled
        result.date = Date()
        return result
    }
}

public enum SpeedTester {
    public static func run(handle: CommandHandle) async throws -> SpeedResult {
        // Follow the normal system route, including VPNs. Never bind to the
        // physical Wi-Fi interface, which could bypass the user's protection.
        let command = try await handle.run(executable: "/usr/bin/networkQuality", arguments: ["-c", "-M", "20"], timeout: 65)
        guard command.status == 0 else { throw MeasurementError.commandFailed }
        return try SpeedResult(data: command.output)
    }
}
