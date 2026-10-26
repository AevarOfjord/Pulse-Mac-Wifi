import Foundation
import WiFiCore

@main struct Diagnostics {
    static func main() async {
        let snapshot = await WiFiSampler().capture(forceProtection: true)
        // Intentionally omit SSIDs, addresses, gateways, and raw command output.
        let checks = ProtectionRules.checks(for: snapshot)
        print("Wi-Fi interface available: \(snapshot.interface != nil)")
        print("Wi-Fi associated: \(snapshot.associated)")
        print("Network name readable: \(snapshot.ssid != nil)")
        print("Security mode readable: \(snapshot.security != .unknown)")
        print("Firewall setting readable: \(snapshot.firewall != nil)")
        print("Stealth setting readable: \(snapshot.stealth != nil)")
        print("Assessment: \(ProtectionRules.summary(checks))")
        if CommandLine.arguments.contains("--connection") {
            let report = await ConnectionTester.run()
            print("HTTPS probes succeeded: \(report.durations.count)/\(report.attempts)")
            print("Connection assessment: \(report.title)")
        }
        if CommandLine.arguments.contains("--speed") {
            do {
                let speed = try await SpeedTester.run(handle: CommandHandle())
                print("Valid speed result: download=\(WiFiFormat.number(speed.downloadMbps)) Mbps, upload=\(WiFiFormat.number(speed.uploadMbps)) Mbps")
            } catch { print("Speed result: \(error.localizedDescription)") }
        }
    }
}
