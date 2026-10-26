import SwiftUI
import Charts
import WiFiCore

struct WiFiDashboard: View {
    @EnvironmentObject var store: WiFiStore
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(Palette.border).frame(width: 1)
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(spacing: 18) {
                        if let notice = store.notice {
                            Text(notice).font(.system(size: 12)).foregroundStyle(Palette.amber).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        switch store.selected {
                        case .overview: overview
                        case .connection: connection
                        case .protections: protections
                        case .settings: WiFiSettingsView()
                        }
                    }.padding(.horizontal, 28).padding(.bottom, 24)
                }.id(store.selected)
                footer
            }
        }.background(Palette.background).tint(Palette.mint)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "wifi").font(.system(size: 21, weight: .medium)).foregroundStyle(Palette.mint)
                    .frame(width: 36, height: 36).background(Palette.mint.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 1) {
                    Text("pulse").font(.system(size: 25, weight: .semibold, design: .rounded)).tracking(-0.7)
                    Text("W I F I").font(.system(size: 8, weight: .semibold)).foregroundStyle(Palette.mint)
                }
            }.padding(.horizontal, 22).padding(.top, 43).padding(.bottom, 36)
            Text("YOUR CONNECTION").font(.system(size: 9, weight: .semibold)).tracking(1.3).foregroundStyle(Palette.muted)
                .padding(.horizontal, 24).padding(.bottom, 13)
            ForEach(WiFiPage.allCases) { page in
                Button { store.selected = page } label: {
                    HStack(spacing: 12) {
                        Image(systemName: page.symbol).font(.system(size: 14)).frame(width: 19)
                        Text(page.rawValue).font(.system(size: 12, weight: store.selected == page ? .semibold : .regular))
                        Spacer()
                        if store.selected == page { Capsule().fill(Palette.mint).frame(width: 3, height: 15) }
                    }.foregroundStyle(store.selected == page ? Palette.mint : Palette.muted)
                        .padding(.horizontal, 13).frame(height: 40)
                        .background(store.selected == page ? Palette.mint.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.horizontal, 12).padding(.bottom, 5)
            }
            Spacer(minLength: 25)
            VStack(alignment: .leading, spacing: 11) {
                Image(systemName: "laptopcomputer").font(.system(size: 25, weight: .light)).foregroundStyle(Palette.muted)
                Text("Made to move with you").font(.system(size: 12, weight: .semibold))
                Text("Fresh checks for the network you're on. Your observations stay on this Mac.")
                    .font(.system(size: 10)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    Circle().fill(Palette.mint).frame(width: 5, height: 5)
                    Text("Lightweight monitoring").font(.system(size: 9)).foregroundStyle(Palette.muted)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 11)).padding(14)
            Text("PULSE WIFI FOR MAC  /  1.0").font(.system(size: 8, weight: .medium)).tracking(0.8)
                .foregroundStyle(Palette.muted.opacity(0.6)).padding(.horizontal, 24).padding(.bottom, 21)
        }.frame(width: 198).background(Palette.sidebar)
    }

    private var header: some View {
        HStack(spacing: 15) {
            VStack(alignment: .leading, spacing: 8) {
                Text("WIFI HEALTH & PROTECTION").font(.system(size: 9, weight: .semibold)).tracking(2).foregroundStyle(Palette.mint)
                Text(store.selected == .overview ? "Wi-Fi overview" : store.selected.rawValue)
                    .font(.system(size: 28, weight: .semibold)).tracking(-0.8)
                Text(store.selected.subtitle).font(.system(size: 12)).foregroundStyle(Palette.muted)
            }
            Spacer()
            StatusPill(text: store.paused ? "PAUSED" : "LIVE", level: store.paused ? .unknown : .good)
            Button(action: store.togglePause) {
                Image(systemName: store.paused ? "play.fill" : "pause.fill").font(.system(size: 11)).frame(width: 28, height: 28)
            }.buttonStyle(.plain).background(Palette.panel, in: RoundedRectangle(cornerRadius: 7))
                .help(store.paused ? "Resume monitoring" : "Pause monitoring")
                .accessibilityLabel(store.paused ? "Resume monitoring" : "Pause monitoring")
        }.padding(.horizontal, 28).padding(.top, 36).padding(.bottom, 27)
    }

    private var overview: some View {
        Group {
            currentNetwork
            HStack(alignment: .top, spacing: 18) {
                qualityPanel
                protectionSummary
            }
            metrics
            HStack(alignment: .top, spacing: 18) {
                speedPanel
                signalPanel
            }
            if store.wifi.ssid == nil && store.wifi.associated { permissionPanel }
        }
    }

    private var currentNetwork: some View {
        WiFiPanel(title: "Your current network", subtitle: store.wifi.interface?.uppercased()) {
            HStack(spacing: 18) {
                Image(systemName: store.wifi.associated ? "wifi" : "wifi.slash")
                    .font(.system(size: 32, weight: .light)).foregroundStyle(store.wifi.associated ? Palette.mint : Palette.muted)
                    .frame(width: 62, height: 62).background(Palette.mint.opacity(0.06), in: RoundedRectangle(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 9) {
                    Text(store.networkName).font(.system(size: 23, weight: .semibold, design: .rounded)).lineLimit(2).textSelection(.enabled)
                    HStack(spacing: 10) {
                        Text(store.wifi.band ?? "Band unavailable")
                        Text("·")
                        Text(store.wifi.channel.map { "Channel \($0)" } ?? "Channel unavailable")
                        Text("·")
                        Text(store.wifi.security.title).foregroundStyle(Palette.color(store.wifi.associated ? store.wifi.security.level : .unknown))
                    }.font(.system(size: 11)).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                if store.checking { ProgressView().controlSize(.small) }
                ActionButton(title: store.checking ? "Cancel check" : "Check connection", symbol: store.checking ? "stop.fill" : "arrow.clockwise", prominent: true) {
                    store.checking ? store.cancelCheck() : store.runCheck()
                }.disabled(store.testingSpeed || store.paused || !store.wifi.associated)
            }
        }
    }

    private var qualityPanel: some View {
        WiFiPanel(title: "Connection quality", symbol: "waveform.path", color: Palette.cyan, subtitle: "OBSERVED BEHAVIOR") {
            HStack { Text(store.qualityTitle).font(.system(size: 19, weight: .semibold, design: .rounded)); Spacer(); Image(systemName: store.qualityLevel == .good ? "checkmark.circle" : "waveform.path").foregroundStyle(Palette.color(store.qualityLevel)) }
            Text(qualityExplanation).font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true).frame(minHeight: 43, alignment: .top)
            HStack {
                Text(store.report.map { "Last check \(WiFiFormat.time($0.date))" } ?? "No connection test yet").font(.system(size: 10)).foregroundStyle(Palette.muted)
                Spacer()
                Button("Details ↗") { store.selected = .connection }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.mint)
            }
        }
    }
    private var qualityExplanation: String {
        guard store.wifi.associated else { return "Join a Wi-Fi network to begin. Local protection settings can still be reviewed." }
        guard let report = store.report else { return "Run a small connection check to test an Apple HTTPS endpoint and look for a possible browser sign-in page." }
        if report.portalSuspected { return "The sign-in probe received an unexpected response. The network may require browser sign-in; this is not proof of interception." }
        if report.durations.isEmpty { return "The Apple test endpoint did not return the expected HTTPS response. The endpoint, VPN, or network policy may be responsible." }
        return "\(report.durations.count) of \(report.attempts) HTTPS checks passed. These observations describe this test endpoint, not every internet service."
    }

    private var protectionSummary: some View {
        WiFiPanel(title: "Your protections", symbol: "checkmark.shield", color: Palette.purple, subtitle: "CONFIGURATION CHECKS") {
            HStack { Text(store.protectionSummary).font(.system(size: 19, weight: .semibold, design: .rounded)); Spacer(); Image(systemName: store.needsAttention ? "exclamationmark.shield" : "shield.lefthalf.filled").foregroundStyle(store.needsAttention ? Palette.amber : Palette.muted) }
            Text("\(store.attentionCount) \(store.attentionCount == 1 ? "finding needs" : "findings need") attention · \(store.incompleteCount) checks need review. Settings checks do not certify that a network is safe.")
                .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true).frame(minHeight: 43, alignment: .top)
            HStack {
                Text("Checked \(WiFiFormat.time(store.wifi.firewallDate))").font(.system(size: 10)).foregroundStyle(Palette.muted)
                Spacer()
                Button("Review protections ↗") { store.selected = .protections }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.mint)
            }
        }
    }

    private var metrics: some View {
        HStack(alignment: .top, spacing: 14) {
            SmallMetric(title: "Wi-Fi signal", value: store.wifi.signal.map(String.init) ?? "—", unit: "dBm", caption: store.wifi.signalLabel, symbol: "wifi", color: Palette.mint)
            SmallMetric(title: "Download", value: WiFiFormat.number(store.speed?.downloadMbps), unit: "Mbps", caption: store.speed.map { "Tested \(WiFiFormat.time($0.date))" } ?? "Run a speed test", symbol: "arrow.down", color: Palette.cyan)
            SmallMetric(title: "Upload", value: WiFiFormat.number(store.speed?.uploadMbps), unit: "Mbps", caption: store.speed.map { "Tested \(WiFiFormat.time($0.date))" } ?? "Run a speed test", symbol: "arrow.up", color: Palette.blue)
            SmallMetric(title: "HTTPS latency", value: WiFiFormat.number(store.report?.latency, digits: 0), unit: "ms", caption: "Apple test endpoint", symbol: "timer", color: Palette.purple)
        }
    }

    private var speedPanel: some View {
        WiFiPanel(title: "Internet speed test", symbol: "speedometer", color: Palette.cyan, subtitle: "ON DEMAND") {
            if store.testingSpeed {
                HStack(spacing: 12) { ProgressView().controlSize(.small); Text("Measuring download and upload…").font(.system(size: 12)) }
                Text("Usually 20–60 seconds. Keep this network connected.").font(.system(size: 11)).foregroundStyle(Palette.muted)
            } else if let speed = store.speed {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(WiFiFormat.number(speed.downloadMbps)).font(.system(size: 29, weight: .medium, design: .rounded)).monospacedDigit()
                    Text("Mbps down").font(.system(size: 11)).foregroundStyle(Palette.muted)
                    Spacer()
                }
                DetailRow(title: "Upload", value: "\(WiFiFormat.number(speed.uploadMbps)) Mbps", color: Palette.blue)
                if let rpm = speed.responsiveness { DetailRow(title: "Loaded responsiveness", value: "\(WiFiFormat.number(rpm, digits: 0)) RPM") }
                Text("Completed \(WiFiFormat.time(speed.date)) · \(speed.interface ?? "System route")").font(.system(size: 10)).foregroundStyle(Palette.muted)
            } else {
                Text("How fast is this connection?").font(.system(size: 18, weight: .medium, design: .rounded))
                Text("Uses Apple's built-in network quality test. Results follow your current route, including a VPN if active.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            if let message = store.speedMessage { Text(message).font(.system(size: 11)).foregroundStyle(Palette.amber).fixedSize(horizontal: false, vertical: true) }
            Text(store.expensive || store.constrained ? "Metered or Low Data Mode connection. This test may transfer substantial data." : "Transfers substantial data. Speed tests run only when you start one.")
                .font(.system(size: 10)).foregroundStyle(store.expensive || store.constrained ? Palette.amber : Palette.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                ActionButton(title: store.testingSpeed ? "Cancel speed test" : "Run speed test", symbol: store.testingSpeed ? "stop.fill" : "play.fill", prominent: !store.testingSpeed) {
                    store.testingSpeed ? store.cancelSpeed() : store.startSpeed()
                }.disabled(store.checking || store.paused || !store.hasPath || !store.wifi.associated)
                Spacer()
            }
        }
    }

    private var signalPanel: some View {
        WiFiPanel(title: "Signal history", symbol: "chart.xyaxis.line", subtitle: "THIS NETWORK · 10 MIN") {
            if store.history.count >= 2 {
                SignalChart(points: store.history).frame(height: 120)
            } else {
                VStack(spacing: 11) {
                    Image(systemName: "waveform.path").font(.system(size: 27, weight: .light)).foregroundStyle(Palette.mint)
                    Text(store.wifi.signal == nil ? "Waiting for a signal reading" : "Collecting signal history")
                        .font(.system(size: 11)).foregroundStyle(Palette.muted)
                }.frame(maxWidth: .infinity).frame(height: 120)
            }
            DetailRow(title: "Signal / noise", value: "\(store.wifi.signal.map { "\($0)" } ?? "—") / \(store.wifi.noise.map { "\($0)" } ?? "—") dBm")
            Text("History resets when the observed network changes. Weaker signal does not by itself mean an unsafe network.")
                .font(.system(size: 10)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var permissionPanel: some View {
        WiFiPanel(title: "Show your Wi-Fi name", symbol: "location", color: Palette.blue) {
            Text("macOS requires Location permission to reveal Wi-Fi names. Pulse WiFi asks only for that access; it doesn't request location updates or store coordinates.")
                .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            ActionButton(title: "Enable Wi-Fi details", symbol: "location") { store.requestWiFiDetails() }
        }
    }

    private var connection: some View {
        Group {
            currentNetwork
            metrics
            HStack(alignment: .top, spacing: 18) { speedPanel; signalPanel }
            WiFiPanel(title: "Connection checks", symbol: "waveform.path", color: Palette.cyan, subtitle: store.report.map { WiFiFormat.time($0.date) }) {
                DetailRow(title: "Result", value: store.qualityTitle, color: Palette.color(store.qualityLevel))
                DetailRow(title: "HTTPS response time · average", value: store.report?.latency.map { "\(WiFiFormat.number($0)) ms" } ?? "Not measured")
                DetailRow(title: "Response-time variation", value: store.report?.jitter.map { "\(WiFiFormat.number($0)) ms" } ?? "Not measured")
                DetailRow(title: "Failed HTTPS probes", value: store.report?.failedPercent.map { "\(WiFiFormat.number($0, digits: 0))%" } ?? "Not measured")
                Text("Three HTTPS requests to Apple's test endpoint, followed by one HTTP sign-in probe. Response time includes HTTP processing and may include DNS/TLS setup; failed probes are not a measurement of IP packet loss. No redirects are followed, credentials submitted, or certificate checks bypassed.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            WiFiPanel(title: "Wi-Fi details", symbol: "info.circle") {
                DetailRow(title: "Network", value: store.networkName)
                DetailRow(title: "Interface", value: store.wifi.interface ?? "Unavailable")
                DetailRow(title: "Band / channel", value: "\(store.wifi.band ?? "—") / \(store.wifi.channel.map(String.init) ?? "—")")
                DetailRow(title: "Reported security", value: store.wifi.security.title)
                DetailRow(title: "Negotiated transmit link rate", value: store.wifi.linkMbps.map { "\(WiFiFormat.number($0, digits: 0)) Mbps" } ?? "Unavailable")
                DetailRow(title: "Signal-to-noise ratio", value: store.wifi.snr.map { "\($0) dB" } ?? "Unavailable")
                DetailRow(title: "Local IPv4 address", value: store.wifi.localIP ?? "Unavailable")
                Text("The negotiated link rate describes your Mac's Wi-Fi radio link. It is not your internet download speed.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
                ActionButton(title: "Wi-Fi settings", symbol: "arrow.up.right") { store.openSettings("wifi") }
            }
            if store.wifi.ssid == nil { permissionPanel }
        }
    }

    private var protections: some View {
        Group {
            WiFiPanel(title: "Protection overview", symbol: "checkmark.shield", color: Palette.purple) {
                HStack { Text(store.protectionSummary).font(.system(size: 25, weight: .medium, design: .rounded)); Spacer(); StatusPill(text: "\(store.attentionCount) to review", level: store.needsAttention ? .attention : .unknown) }
                Text("A setting being enabled is different from proving its protection works end to end. Each check shows its source and limitations. Unknown checks stay unknown; a strong signal or a fast speed test is not a security assessment.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                ActionButton(title: "Refresh protection checks") { Task { await store.refresh(force: true) } }.disabled(store.refreshing)
            }
            ForEach(store.checks) { check in
                WiFiPanel(title: check.title, symbol: check.level == .good ? "checkmark.shield" : check.level == .attention ? "exclamationmark.shield" : "questionmark.shield", color: Palette.color(check.level), subtitle: check.source.uppercased()) {
                    HStack {
                        StatusPill(text: check.value, level: check.level)
                        Spacer()
                        ActionButton(title: "Open settings", symbol: "arrow.up.right") { store.openSettings(check.settings) }
                    }
                    Text(check.detail).font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                    if check.id == "firewall" || check.id == "stealth" {
                        Text("Configuration checked \(WiFiFormat.time(store.wifi.firewallDate)) · blocking behavior not tested")
                            .font(.system(size: 10)).foregroundStyle(Palette.muted)
                    }
                    if check.id == "private-address" {
                        Text("In Wi-Fi settings: Details → Private Wi-Fi Address → Fixed or Rotating.").font(.system(size: 11)).foregroundStyle(Palette.blue)
                    }
                    if check.id == "private-relay" {
                        Text("Review Private Relay in iCloud, then Limit IP Address Tracking in this network's Wi-Fi Details.").font(.system(size: 11)).foregroundStyle(Palette.blue)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 15) {
            Label("Observations stay local", systemImage: "lock").foregroundStyle(Palette.muted)
            if store.expensive { Text("Metered connection").foregroundStyle(Palette.amber) }
            Spacer()
            Text(store.paused ? "Monitoring paused" : "Updated \(store.wifi.date.formatted(date: .omitted, time: .standard))").foregroundStyle(Palette.muted)
        }.font(.system(size: 9)).padding(.horizontal, 28).frame(height: 35)
            .overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: 1) }
    }
}

struct SignalChart: View {
    let points: [SignalPoint]
    @ViewState private var selection: Date?
    private var nearest: SignalPoint? {
        guard let selection else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selection)) < abs($1.date.timeIntervalSince(selection)) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let point = nearest {
                Text("Selected · \(point.date.formatted(date: .omitted, time: .standard)) · \(point.value) dBm")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.mint)
            }
            Chart {
                ForEach(points) { point in
                    LineMark(x: .value("Time", point.date), y: .value("Signal", point.value))
                        .foregroundStyle(Palette.mint).lineStyle(StrokeStyle(lineWidth: 2))
                }
                if let selected = nearest { RuleMark(x: .value("Selected", selected.date)).foregroundStyle(Palette.muted.opacity(0.6)) }
            }
            .chartYScale(domain: min(-100, (points.map(\.value).min() ?? -90) - 5)...max(-30, (points.map(\.value).max() ?? -40) + 5))
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.6, dash: [3, 4])).foregroundStyle(Palette.border)
                    AxisValueLabel().font(.system(size: 9)).foregroundStyle(Palette.muted)
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { AxisValueLabel(format: .dateTime.hour().minute()).font(.system(size: 9)).foregroundStyle(Palette.muted) } }
            .chartXSelection(value: $selection)
            .chartGesture { proxy in DragGesture(minimumDistance: 0).onChanged { proxy.selectXValue(at: $0.location.x) } }
            .accessibilityLabel("Wi-Fi signal history in dBm")
            .help("Click or drag to inspect a signal reading.")
        }
    }
}

struct WiFiSettingsView: View {
    @EnvironmentObject var store: WiFiStore
    var body: some View {
        VStack(spacing: 18) {
            WiFiPanel(title: "Monitoring", symbol: "slider.horizontal.3") {
                Toggle("Show status beside the menu-bar icon", isOn: $store.showMenuText)
                Toggle("Automatic lightweight connection checks", isOn: $store.automaticChecks)
                Text("When enabled, connection checks contact Apple's test endpoints at most once every five minutes. Automatic checks skip metered and Low Data Mode connections. Local Wi-Fi readings refresh every 10 seconds while visible and every 30 seconds in the background. Speed tests are always manual.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                ActionButton(title: store.paused ? "Resume monitoring" : "Pause monitoring", symbol: store.paused ? "play.fill" : "pause.fill", action: store.togglePause)
            }
            WiFiPanel(title: "Notifications", symbol: "bell", color: Palette.amber) {
                Toggle("Notify me when a check needs attention", isOn: Binding(get: { store.alertsEnabled }, set: { store.setAlerts($0) }))
                DetailRow(title: "macOS notification permission", value: store.notificationStatus)
                Text("Notifications are off by default and omit network names and addresses. Findings have a 30-minute cooldown; incomplete manual privacy checks alone do not trigger alerts.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                if store.notificationStatus == "Denied" { ActionButton(title: "Notification settings", symbol: "arrow.up.right") { store.openSettings("notifications") } }
            }
            WiFiPanel(title: "Wi-Fi details permission", symbol: "location", color: Palette.blue) {
                Text("Location access lets macOS reveal your current Wi-Fi name. Pulse WiFi does not request location updates, store coordinates, or scan other devices.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                ActionButton(title: "Enable Wi-Fi details", symbol: "location") { store.requestWiFiDetails() }
            }
            WiFiPanel(title: "Privacy & storage", symbol: "lock", color: Palette.purple) {
                Text("Network observations stay in memory for this session. Signal history is limited to ten minutes and resets when the network changes. Quitting clears observations; only your app preferences are saved. No account, analytics, or browsing history collection.")
                    .font(.system(size: 12)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
                Text("Connection and speed tests contact external services. The sign-in probe uses HTTP with no credentials and follows no redirects. HTTPS tests keep certificate validation enabled.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted).fixedSize(horizontal: false, vertical: true)
            }
            WiFiPanel(title: "Pulse WiFi 1.0", symbol: "wifi") {
                Text("Apple silicon · macOS 14+ · Locally signed preview").font(.system(size: 12))
                Text("A lightweight companion to Pulse. Shares its native styling and leaves your macOS protection settings under your control.")
                    .font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
        }.font(.system(size: 12)).toggleStyle(.switch)
    }
}
