import SwiftUI
import WiFiCore

@main struct PulseWiFiApp: App {
    @StateObject private var store = WiFiStore()
    var body: some Scene {
        WindowGroup("Pulse WiFi", id: "dashboard") {
            WiFiDashboard().environmentObject(store)
                .frame(minWidth: 950, minHeight: 710)
        }
        .defaultSize(width: 1160, height: 860)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Connection") {
                Button("Check Connection", action: store.runCheck).keyboardShortcut("r", modifiers: .command)
                Button(store.paused ? "Resume Monitoring" : "Pause Monitoring", action: store.togglePause)
                Divider()
                ForEach(WiFiPage.allCases) { page in Button(page.rawValue) { store.selected = page } }
            }
        }
        MenuBarExtra {
            WiFiMenuView().environmentObject(store)
        } label: {
            Image(systemName: "wifi")
            if store.showMenuText { Text(store.menuLabel).font(.system(size: 11)).monospacedDigit() }
        }.menuBarExtraStyle(.window)
        Settings {
            WiFiSettingsView().environmentObject(store).padding(24).frame(width: 600).background(Palette.background)
        }
    }
}

struct WiFiMenuView: View {
    @EnvironmentObject var store: WiFiStore
    @Environment(\.openWindow) private var openWindow
    private var speedDisabled: Bool { store.checking || store.paused || !store.hasPath || !store.wifi.associated }
    private var checkDisabled: Bool { store.testingSpeed || store.paused || !store.wifi.associated }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Pulse WiFi", systemImage: "wifi").font(.headline)
                Spacer()
                Text(store.paused ? "Paused" : "Live")
                    .font(.system(size: 11)).foregroundStyle(store.paused ? Palette.muted : Palette.mint)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(store.networkName).font(.system(size: 13, weight: .semibold))
                    .lineLimit(2).textSelection(.enabled)
                HStack {
                    Text("\(store.wifi.band ?? "Band unavailable") · \(store.wifi.channel.map { "Channel \($0)" } ?? "Channel unavailable")")
                    Spacer(minLength: 5)
                    Text(store.wifi.signal.map { "\($0) dBm" } ?? "— dBm").monospacedDigit()
                }.font(.system(size: 10)).foregroundStyle(.secondary)
                if store.wifi.associated && store.wifi.ssid == nil {
                    Button("Enable Wi-Fi details", action: store.requestWiFiDetails)
                        .font(.system(size: 11)).buttonStyle(.borderless)
                }
            }
            Divider()
            HStack {
                Text("Latest speed test").font(.system(size: 11, weight: .medium))
                Spacer()
                Text(store.speed.map { WiFiFormat.time($0.date) } ?? "Not tested")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .help(store.speed?.date.formatted(date: .abbreviated, time: .standard) ?? "No completed speed test for this network")
            }
            HStack(spacing: 18) {
                speedReading("Download", symbol: "arrow.down", value: store.speed?.downloadMbps, color: Palette.cyan)
                speedReading("Upload", symbol: "arrow.up", value: store.speed?.uploadMbps, color: Palette.blue)
            }
            if let latency = store.speed?.idleLatency {
                menuRow("Test idle latency", value: "\(WiFiFormat.number(latency)) ms")
            }
            if let rpm = store.speed?.responsiveness {
                menuRow("Loaded responsiveness", value: "\(WiFiFormat.number(rpm, digits: 0)) RPM")
                    .help("Round trips per minute while the connection is busy. Higher means more responsive in this test.")
            }
            HStack(spacing: 8) {
                Button(store.testingSpeed ? "Cancel test" : "Run speed test") {
                    store.testingSpeed ? store.cancelSpeed() : store.startSpeed()
                }.disabled(!store.testingSpeed && speedDisabled)
                    .accessibilityLabel(store.testingSpeed ? "Cancel speed test" : "Run speed test")
                Button(store.checking ? "Cancel check" : "Check connection") {
                    store.checking ? store.cancelCheck() : store.runCheck()
                }.disabled(!store.checking && checkDisabled)
            }.controlSize(.small)
            if store.testingSpeed {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini)
                    Text(store.speed == nil ? "Testing… usually 20–60 seconds" : "Testing… showing the previous completed result")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            if let message = store.speedMessage {
                Text(message).font(.system(size: 10)).foregroundStyle(Palette.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(store.expensive || store.constrained ? "Speed tests use mobile / metered data." : "Speed tests use internet data.")
                .font(.system(size: 9)).foregroundStyle(store.expensive || store.constrained ? Palette.amber : Palette.muted)
            Divider()
            menuRow("Connection", value: store.checking ? "Checking…" : store.qualityTitle,
                    color: store.checking ? .secondary : Palette.color(store.qualityLevel))
            menuRow("HTTPS latency", value: store.report?.latency.map { "\(WiFiFormat.number($0, digits: 0)) ms" } ?? "Not checked")
                .help(store.report.map { "Apple HTTPS endpoint · checked \(WiFiFormat.time($0.date))" } ?? "Run a connection check")
            menuRow("Wi-Fi security", value: store.wifi.associated ? store.wifi.security.title : "Not connected",
                    color: Palette.color(store.wifi.associated ? store.wifi.security.level : .unknown))
            Button {
                store.selected = .protections; showDashboard()
            } label: {
                menuRow("Protections", value: store.protectionSummary, color: store.needsAttention ? Palette.amber : .secondary)
            }.buttonStyle(.plain).help("Review firewall, stealth mode, and privacy checks")
            Text("\(store.incompleteCount) checks need review · updated \(WiFiFormat.time(store.wifi.date))")
                .font(.system(size: 9)).foregroundStyle(.secondary)
            Divider()
            footer
        }
        .padding(18).frame(width: 320)
        // Keep the native menu-bar material and inherited system appearance.
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: showDashboard) {
                Label("Dashboard", systemImage: "arrow.up.right").font(.system(size: 11, weight: .medium))
            }.accessibilityLabel("Open dashboard").help("Open dashboard")
            Spacer(minLength: 0)
            Button(action: store.togglePause) {
                Image(systemName: store.paused ? "play.fill" : "pause.fill").frame(width: 24, height: 24)
            }.accessibilityLabel(store.paused ? "Resume monitoring" : "Pause monitoring")
                .help(store.paused ? "Resume monitoring" : "Pause monitoring")
            Button { store.selected = .settings; showDashboard() } label: {
                Image(systemName: "gearshape").frame(width: 24, height: 24)
            }.accessibilityLabel("Settings").help("Settings")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power").frame(width: 24, height: 24) }
                .accessibilityLabel("Quit Pulse WiFi").help("Quit Pulse WiFi")
        }.buttonStyle(.borderless).font(.system(size: 12)).foregroundStyle(.secondary)
    }

    private func menuRow(_ title: String, value: String, color: Color = .secondary) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 10)
            Text(value).monospacedDigit().foregroundStyle(color).multilineTextAlignment(.trailing)
        }.font(.system(size: 11))
    }

    private func speedReading(_ title: String, symbol: String, value: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(.system(size: 10, weight: .medium)).foregroundStyle(color)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(WiFiFormat.number(value)).font(.system(size: 20, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("Mbps").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func showDashboard() {
        openWindow(id: "dashboard")
        NSApp.activate(ignoringOtherApps: true)
    }
}
