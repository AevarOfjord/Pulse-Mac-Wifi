import Foundation
import CoreFoundation

public enum FindingLevel: String, Sendable { case good, attention, unknown }

public enum WiFiSecurity: Int, Sendable {
    case open = 0, wep = 1, wpa = 2, wpaMixed = 3, wpa2 = 4, personal = 5
    case dynamicWEP = 6, wpaEnterprise = 7, enterpriseMixed = 8, wpa2Enterprise = 9, enterprise = 10
    case wpa3 = 11, wpa3Enterprise = 12, transition = 13, owe = 14, oweTransition = 15
    case unknown = -1

    public init(systemValue: Int) { self = Self(rawValue: systemValue) ?? .unknown }
    public var title: String {
        switch self {
        case .open: return "Open network"
        case .wep, .dynamicWEP: return "WEP"
        case .wpa, .wpaEnterprise: return "WPA"
        case .wpaMixed, .enterpriseMixed: return "WPA / WPA2"
        case .wpa2, .wpa2Enterprise: return "WPA2"
        case .wpa3, .wpa3Enterprise: return "WPA3"
        case .transition: return "WPA2 / WPA3"
        case .owe: return "Enhanced Open"
        case .oweTransition: return "Enhanced Open transition"
        case .personal, .enterprise, .unknown: return "Unavailable"
        }
    }
    public var level: FindingLevel {
        switch self {
        case .wpa2, .wpa2Enterprise, .wpa3, .wpa3Enterprise, .transition: return .good
        case .personal, .enterprise, .unknown: return .unknown
        default: return .attention
        }
    }
    public var explanation: String {
        switch self {
        case .open: return "This Wi-Fi link has no wireless encryption. HTTPS can still protect individual connections; the network itself is not authenticated."
        case .wep, .dynamicWEP, .wpa, .wpaEnterprise, .wpaMixed, .enterpriseMixed:
            return "macOS reports a legacy security mode. Prefer a network using WPA2 or WPA3, and keep using HTTPS."
        case .wpa2, .wpa2Enterprise: return "macOS reports WPA2. This is a wireless security check, not proof that the hotspot or every connection is trustworthy."
        case .wpa3, .wpa3Enterprise: return "macOS reports WPA3, a modern wireless security mode. It does not establish that the hotspot operator is trustworthy."
        case .transition: return "macOS reports WPA2/WPA3 transition mode. This does not confirm a WPA3-only connection."
        case .owe, .oweTransition: return "Enhanced Open provides wireless encryption on supported connections, but does not authenticate the hotspot. Transition mode may also offer an unencrypted connection."
        default: return "macOS has not exposed a specific security mode. Grant Wi-Fi details access or review this connection in System Settings."
        }
    }
}

public struct WiFiSnapshot: Sendable {
    public var date = Date()
    public var poweredOn = false
    public var associated = false
    public var interface: String?
    public var ssid: String?
    public var bssid: String?
    public var router: String?
    public var localIP: String?
    public var signal: Int?
    public var noise: Int?
    public var linkMbps: Double?
    public var channel: Int?
    public var band: String?
    public var security: WiFiSecurity = .unknown
    public var firewall: Bool?
    public var stealth: Bool?
    public var firewallDate: Date?
    public var error: String?
    public init() {}

    // SSID alone is not a unique network identity. Invalidate observations when
    // any available association, gateway, or interface identity changes.
    public var contextID: String {
        [associated ? "joined" : "not-joined", interface ?? "", ssid ?? "", bssid ?? "", router ?? "", localIP ?? ""].joined(separator: "|")
    }
    public var signalLabel: String {
        guard let signal else { return "Unavailable" }
        if signal >= -60 { return "Strong" }
        if signal >= -70 { return "Good" }
        return "Weak"
    }
    public var signalLevel: FindingLevel {
        guard let signal else { return .unknown }
        return signal >= -70 ? .good : .attention
    }
    public var snr: Int? {
        guard let signal, let noise, signal >= noise else { return nil }
        return signal - noise
    }
}

public struct ProtectionCheck: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let value: String
    public let detail: String
    public let level: FindingLevel
    public let source: String
    public let settings: String
    public init(id: String, title: String, value: String, detail: String, level: FindingLevel, source: String, settings: String) {
        self.id = id; self.title = title; self.value = value; self.detail = detail; self.level = level; self.source = source; self.settings = settings
    }
}

public enum ProtectionRules {
    public static func checks(for wifi: WiFiSnapshot) -> [ProtectionCheck] {
        let encryption = ProtectionCheck(id: "encryption", title: "Wi-Fi encryption", value: wifi.associated ? wifi.security.title : "Not connected",
            detail: wifi.associated ? wifi.security.explanation : "Join a Wi-Fi network to inspect its reported wireless security mode.",
            level: wifi.associated ? wifi.security.level : .unknown, source: "macOS · CoreWLAN", settings: "wifi")
        let firewall = ProtectionCheck(id: "firewall", title: "Mac firewall", value: wifi.firewall.map { $0 ? "Enabled" : "Disabled" } ?? "Couldn't verify",
            detail: wifi.firewall == true ? "Apple's application firewall is configured to restrict incoming connections. Individual app exceptions still apply; blocking behavior has not been tested from another device." : "The application firewall setting is \(wifi.firewall == false ? "off" : "unavailable"). Review incoming-connection protection in System Settings.",
            level: wifi.firewall.map { $0 ? .good : .attention } ?? .unknown, source: "macOS · setting checked", settings: "firewall")
        let stealth = ProtectionCheck(id: "stealth", title: "Stealth mode", value: wifi.firewall == false ? "Firewall is off" : wifi.stealth.map { $0 ? "Enabled" : "Disabled" } ?? "Couldn't verify",
            detail: "Stealth mode limits responses to some unsolicited probes. It depends on the firewall and does not make your Mac invisible. This checks configuration, not external reachability.",
            level: wifi.firewall == true && wifi.stealth == true ? .good : .unknown, source: "macOS · setting checked", settings: "firewall")
        let address = ProtectionCheck(id: "private-address", title: "Private Wi-Fi Address", value: "Review in Settings",
            detail: "Check that Private Wi-Fi Address is Fixed or Rotating for this network. A randomized-looking MAC address alone cannot verify this setting or its behavior.",
            level: .unknown, source: "Manual check · not verified", settings: "wifi")
        let relay = ProtectionCheck(id: "private-relay", title: "iCloud Private Relay", value: "Review in Settings",
            detail: "If you use iCloud+, review Private Relay and this network's Limit IP Address Tracking setting. It covers supported traffic, including Safari, rather than every app. Pulse WiFi cannot verify that the service is active.",
            level: .unknown, source: "Manual check · not verified", settings: "relay")
        return [encryption, firewall, stealth, address, relay]
    }
    public static func summary(_ checks: [ProtectionCheck]) -> String {
        if checks.contains(where: { $0.level == .attention }) { return "Needs attention" }
        if checks.contains(where: { $0.level == .unknown }) { return "Checks incomplete" }
        return "No issues found"
    }
}

public struct ConnectionReport: Sendable {
    public var date = Date()
    public var attempts = 0
    public var durations: [Double] = []
    public var portalSuspected = false
    public var cancelled = false
    public init() {}
    public var latency: Double? { durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count) }
    public var jitter: Double? {
        guard durations.count > 1 else { return nil }
        return zip(durations.dropFirst(), durations).map { abs($0 - $1) }.reduce(0, +) / Double(durations.count - 1)
    }
    public var failedPercent: Double? { attempts > 0 ? 100 * Double(max(0, attempts - durations.count)) / Double(attempts) : nil }
    public var title: String {
        if cancelled { return "Cancelled" }
        if portalSuspected { return "Sign-in may be needed" }
        guard let latency else { return "Couldn't reach test service" }
        if durations.count < attempts || latency > 500 || (jitter ?? 0) > 100 { return "Variable response" }
        return "Checks passed"
    }
}

public enum MeasurementError: Error, LocalizedError, Equatable {
    case invalidResult, commandFailed, timeout, cancelled
    public var errorDescription: String? {
        switch self {
        case .invalidResult: return "The test did not return complete, valid measurements. Try again after checking your connection."
        case .commandFailed: return "macOS couldn't complete this test. The test service, VPN, or network policy may affect availability."
        case .timeout: return "The test timed out. No speed result was saved."
        case .cancelled: return "Test cancelled."
        }
    }
}

public struct SpeedResult: Sendable {
    public let date: Date
    public let downloadMbps: Double
    public let uploadMbps: Double
    public let idleLatency: Double?
    public let responsiveness: Double?
    public let interface: String?
    public init(data: Data, date: Date = Date()) throws {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["error_code"] == nil, json["error_domain"] == nil,
              let down = json["dl_throughput"] as? NSNumber, let up = json["ul_throughput"] as? NSNumber,
              CFGetTypeID(down) != CFBooleanGetTypeID(), CFGetTypeID(up) != CFBooleanGetTypeID(),
              down.doubleValue.isFinite, up.doubleValue.isFinite, down.doubleValue >= 0, up.doubleValue >= 0 else {
            throw MeasurementError.invalidResult
        }
        downloadMbps = down.doubleValue / 1_000_000
        uploadMbps = up.doubleValue / 1_000_000
        self.date = date
        func positive(_ key: String) -> Double? {
            guard let n = (json[key] as? NSNumber)?.doubleValue, n.isFinite, n > 0 else { return nil }
            return n
        }
        idleLatency = positive("base_rtt")
        responsiveness = positive("responsiveness")
        interface = json["interface_name"] as? String
    }
}

public enum FirewallParser {
    public static func state(_ text: String, exitCode: Int32) -> Bool? {
        guard exitCode == 0 else { return nil }
        if text.contains("(State = 0)") { return false }
        if text.contains("(State = 1)") || text.contains("(State = 2)") { return true }
        return nil
    }
    public static func stealth(_ text: String, exitCode: Int32) -> Bool? {
        guard exitCode == 0 else { return nil }
        let value = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if value == "firewall stealth mode is on" { return true }
        if value == "firewall stealth mode is off" { return false }
        return nil
    }
}

public enum WiFiFormat {
    public static func number(_ value: Double?, digits: Int = 1) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.*f", digits, value)
    }
    public static func time(_ date: Date?) -> String { date?.formatted(date: .omitted, time: .shortened) ?? "Not checked" }
}
