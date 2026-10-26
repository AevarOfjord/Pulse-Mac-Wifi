import Foundation
import Testing
@testable import WiFiCore

struct ChecksTests {
    @Test func unknownSecurityNeverPasses() {
        for value in [-8, 5, 10, 100, Int.max] {
            #expect(WiFiSecurity(systemValue: value).level == .unknown)
        }
    }
    @Test func legacyAndOpenNetworksNeedAttention() {
        for value in [0, 1, 2, 3, 6, 7, 8] { #expect(WiFiSecurity(systemValue: value).level == .attention) }
    }
    @Test func modernModesAreReportedWithoutInventingWPA3() {
        for value in [4, 9, 11, 12, 13] { #expect(WiFiSecurity(systemValue: value).level == .good) }
        #expect(WiFiSecurity(systemValue: 13).title == "WPA2 / WPA3")
        #expect(WiFiSecurity(systemValue: 14).level == .attention)
        #expect(WiFiSecurity(systemValue: 15).level == .attention)
    }
    @Test func aMissingFirewallReadingIsNotDisabledOrEnabled() {
        #expect(FirewallParser.state("Operation not permitted", exitCode: 1) == nil)
        #expect(FirewallParser.state("Firewall state unknown", exitCode: 0) == nil)
        #expect(FirewallParser.state("Future state (State = 10)", exitCode: 0) == nil)
        #expect(FirewallParser.state("Firewall is disabled. (State = 0)", exitCode: 0) == false)
        #expect(FirewallParser.state("Firewall enabled. (State = 1)", exitCode: 0) == true)
        #expect(FirewallParser.state("Block all (State = 2)", exitCode: 0) == true)
    }
    @Test func stealthParsingHonorsCommandFailure() {
        #expect(FirewallParser.stealth("Firewall stealth mode is on\n", exitCode: 0) == true)
        #expect(FirewallParser.stealth("Firewall stealth mode is off\n", exitCode: 0) == false)
        #expect(FirewallParser.stealth("Firewall stealth mode is on", exitCode: 1) == nil)
        #expect(FirewallParser.stealth("Unexpected", exitCode: 0) == nil)
    }
    @Test func configuredProtectionsCannotCertifyOverallSafety() {
        var wifi = WiFiSnapshot()
        wifi.associated = true; wifi.security = .wpa3; wifi.firewall = true; wifi.stealth = true
        let checks = ProtectionRules.checks(for: wifi)
        #expect(ProtectionRules.summary(checks) == "Checks incomplete")
        #expect(checks.first { $0.id == "private-address" }?.level == .unknown)
        #expect(checks.first { $0.id == "private-relay" }?.level == .unknown)
    }
    @Test func disabledFirewallIsActionableAndMakesStealthInapplicable() {
        var wifi = WiFiSnapshot(); wifi.firewall = false; wifi.stealth = true
        let checks = ProtectionRules.checks(for: wifi)
        #expect(ProtectionRules.summary(checks) == "Needs attention")
        #expect(checks.first { $0.id == "stealth" }?.level == .unknown)
    }
    @Test func disconnectedNetworkDoesNotReuseItsEncryptionVerdict() {
        var wifi = WiFiSnapshot(); wifi.associated = false; wifi.security = .wpa3
        #expect(ProtectionRules.checks(for: wifi).first?.level == .unknown)
    }
    @Test func networkContextsSeparateSameNameOnDifferentAccessPoints() {
        var first = WiFiSnapshot(); first.associated = true; first.ssid = "Example"; first.bssid = "first"
        var second = first; second.bssid = "second"
        #expect(first.contextID != second.contextID)
        second = first; second.router = "different-gateway"
        #expect(first.contextID != second.contextID)
        second = first; second.associated = false
        #expect(first.contextID != second.contextID)
    }
    @Test func speedTestConvertsBitsToDecimalMegabits() throws {
        let result = try SpeedResult(data: Data(#"{"dl_throughput":125000000,"ul_throughput":25000000,"base_rtt":12.5,"responsiveness":1200,"interface_name":"en0"}"#.utf8))
        #expect(result.downloadMbps == 125)
        #expect(result.uploadMbps == 25)
        #expect(result.idleLatency == 12.5)
    }
    @Test func missingPartialErroredAndBooleanSpeedsAreRejected() {
        for fixture in [#"{}"#, #"{"dl_throughput":100}"#, #"{"dl_throughput":-1,"ul_throughput":10}"#, #"{"dl_throughput":true,"ul_throughput":1}"#, #"{"dl_throughput":10,"ul_throughput":10,"error_code":1}"#, "not json"] {
            #expect(throws: MeasurementError.self) { try SpeedResult(data: Data(fixture.utf8)) }
        }
    }
    @Test func zeroThroughputIsAValidMeasurementButNoDataIsNotZero() throws {
        let zero = try SpeedResult(data: Data(#"{"dl_throughput":0,"ul_throughput":0}"#.utf8))
        #expect(zero.downloadMbps == 0)
        #expect(WiFiFormat.number(nil) == "—")
    }
    @Test func connectionFailureDoesNotBecomeALowLatencyPass() {
        var report = ConnectionReport(); report.attempts = 3
        #expect(report.latency == nil)
        #expect(report.failedPercent == 100)
        #expect(report.title == "Couldn't reach test service")
        report.durations = [100, 150, 125]
        #expect(report.latency == 125)
        #expect(report.jitter == 37.5)
        #expect(report.title == "Checks passed")
        report.portalSuspected = true
        #expect(report.title == "Sign-in may be needed")
    }
    @Test func commandCancellationBeforeLaunchStopsExecution() async {
        let handle = CommandHandle(); handle.cancel()
        do {
            _ = try await handle.run(executable: "/usr/bin/true", arguments: [], timeout: 2)
            Issue.record("Cancelled command unexpectedly ran")
        } catch { #expect(error as? MeasurementError == .cancelled) }
    }
    @Test func commandTimeoutTerminatesItsOwnChild() async {
        do {
            _ = try await CommandHandle().run(executable: "/bin/sleep", arguments: ["5"], timeout: 0.1)
            Issue.record("Timed-out command unexpectedly succeeded")
        } catch { #expect(error as? MeasurementError == .timeout) }
    }
}
