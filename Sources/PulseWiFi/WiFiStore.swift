import AppKit
import SwiftUI
import Network
import CoreLocation
import UserNotifications
import WiFiCore

enum WiFiPage: String, CaseIterable, Identifiable {
    case overview = "Overview", connection = "Connection", protections = "Protections", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .overview: return "square.grid.2x2"; case .connection: return "wifi"; case .protections: return "checkmark.shield"; case .settings: return "gearshape" }
    }
    var subtitle: String {
        switch self {
        case .overview: return "A clearer view of the Wi-Fi you're on."
        case .connection: return "Signal, responsiveness, and measured internet speed."
        case .protections: return "What macOS reports, and what still needs your review."
        case .settings: return "Lightweight monitoring, on your terms."
        }
    }
}

struct SignalPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Int
}

@MainActor final class WiFiStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var wifi = WiFiSnapshot()
    @Published var selected = WiFiPage.overview
    @Published var report: ConnectionReport?
    @Published var speed: SpeedResult?
    @Published var history: [SignalPoint] = []
    @Published var refreshing = false
    @Published var checking = false
    @Published var testingSpeed = false
    @Published var speedMessage: String?
    @Published var notice: String?
    @Published var hasPath = false
    @Published var usesWiFi = false
    @Published var expensive = false
    @Published var constrained = false
    @Published var paused = false
    @Published var locationStatus = CLAuthorizationStatus.notDetermined
    @Published var notificationStatus = "Not requested"
    @Published var automaticChecks: Bool { didSet { UserDefaults.standard.set(automaticChecks, forKey: "automaticChecks") } }
    @Published var showMenuText: Bool { didSet { UserDefaults.standard.set(showMenuText, forKey: "showMenuText") } }
    @Published var alertsEnabled: Bool = false

    private let sampler = WiFiSampler()
    private let pathMonitor = NWPathMonitor()
    private let location = CLLocationManager()
    private var loop: Task<Void, Never>?
    private var checkTask: Task<Void, Never>?
    private var speedTask: Task<Void, Never>?
    private var speedHandle: CommandHandle?
    private var context = UUID()
    private var pathSignature: String?
    private var lastAutomatic = Date.distantPast
    private var lastAlert = Date.distantPast
    private var wakeObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?

    override init() {
        let defaults = UserDefaults.standard
        automaticChecks = defaults.object(forKey: "automaticChecks") as? Bool ?? true
        showMenuText = defaults.object(forKey: "showMenuText") as? Bool ?? true
        super.init()
        location.delegate = self
        locationStatus = location.authorizationStatus
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let ready = path.status == .satisfied
            let wifi = path.usesInterfaceType(.wifi)
            let expensive = path.isExpensive; let constrained = path.isConstrained
            let signature = "\(ready)|\(wifi)|\(expensive)|\(constrained)|\(path.availableInterfaces.map(\.name).sorted().joined(separator: ","))"
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.pathSignature != nil && self.pathSignature != signature { self.invalidateContext() }
                self.pathSignature = signature
                self.hasPath = ready; self.usesWiFi = wifi
                self.expensive = expensive; self.constrained = constrained
                await self.refresh()
                self.maybeCheckAutomatically()
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "local.pulse.wifi.path", qos: .utility))
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.invalidateContext()
                await self?.refresh(force: true)
            }
        }
        terminateObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.loop?.cancel()
                self?.checkTask?.cancel()
                self?.speedHandle?.cancel()
                self?.speedTask?.cancel()
            }
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if !self.paused { await self.refresh(); self.maybeCheckAutomatically() }
                let visible = NSApp.windows.contains { $0.isVisible && !$0.isMiniaturized }
                try? await Task.sleep(for: .seconds(visible ? 10 : 30))
            }
        }
        Task { await refreshNotificationStatus() }
    }
    deinit {
        loop?.cancel(); checkTask?.cancel(); speedTask?.cancel(); speedHandle?.cancel()
        pathMonitor.cancel()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let terminateObserver { NotificationCenter.default.removeObserver(terminateObserver) }
    }

    var checks: [ProtectionCheck] { ProtectionRules.checks(for: wifi) }
    var protectionSummary: String { ProtectionRules.summary(checks) }
    var needsAttention: Bool { checks.contains { $0.level == .attention } }
    var attentionCount: Int { checks.filter { $0.level == .attention }.count }
    var incompleteCount: Int { checks.filter { $0.level == .unknown }.count }
    var networkName: String { wifi.associated ? wifi.ssid ?? "Wi-Fi name needs permission" : wifi.poweredOn ? "Not connected to Wi-Fi" : "Wi-Fi is off" }
    var qualityTitle: String {
        if !wifi.associated { return "Not connected" }
        if !hasPath { return "No network path" }
        if let report { return report.title }
        return checking ? "Checking connection" : "Ready to check"
    }
    var qualityLevel: FindingLevel {
        guard wifi.associated, hasPath else { return .attention }
        guard let report else { return .unknown }
        return report.title == "Checks passed" && wifi.signalLevel != .attention ? .good : .attention
    }
    var menuLabel: String { paused ? "Paused" : needsAttention ? "Review" : wifi.associated ? "Wi-Fi" : "Offline" }

    func refresh(force: Bool = false) async {
        guard !refreshing, !paused || force else { return }
        refreshing = true
        let fresh = await sampler.capture(forceProtection: force)
        if fresh.contextID != wifi.contextID { invalidateContext() }
        wifi = fresh
        if let signal = fresh.signal { history.append(SignalPoint(date: fresh.date, value: signal)) }
        history.removeAll { Date().timeIntervalSince($0.date) > 600 }
        if history.count > 100 { history.removeFirst(history.count - 100) }
        refreshing = false
    }

    private func invalidateContext() {
        context = UUID()
        checkTask?.cancel(); checkTask = nil
        speedHandle?.cancel(); speedTask?.cancel(); speedTask = nil; speedHandle = nil
        checking = false; testingSpeed = false
        report = nil; speed = nil; speedMessage = nil; history = []
        lastAutomatic = .distantPast
    }

    func togglePause() {
        paused.toggle()
        if paused {
            checkTask?.cancel(); checking = false
            cancelSpeed()
        } else { Task { await refresh(force: true) } }
    }

    func requestWiFiDetails() {
        if location.authorizationStatus == .notDetermined { location.requestWhenInUseAuthorization() }
        else if location.authorizationStatus == .authorizedAlways {
            Task { await refresh(force: true) }
        } else { openSettings("location") }
    }
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            self?.locationStatus = status
            await self?.refresh(force: true)
        }
    }

    private func maybeCheckAutomatically() {
        guard automaticChecks, !paused, hasPath, wifi.associated, !expensive, !constrained,
              !checking, !testingSpeed, Date().timeIntervalSince(lastAutomatic) > 300 else { return }
        runCheck()
    }

    func runCheck() {
        guard !checking, !testingSpeed, !paused else { return }
        checking = true; notice = nil; lastAutomatic = Date()
        checkTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh(force: true)
            // Refresh may have detected a new association and cancelled this task.
            guard !Task.isCancelled else { return }
            let ticket = self.context
            self.checking = true
            let result = await ConnectionTester.run()
            guard !Task.isCancelled, ticket == self.context else { return }
            self.report = result; self.checking = false
            await self.notifyIfNeeded()
        }
    }

    func cancelCheck() { checkTask?.cancel(); checkTask = nil; checking = false }

    func startSpeed() {
        guard !testingSpeed, !checking, !paused, hasPath else { return }
        testingSpeed = true; speedMessage = nil; notice = nil
        speedTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            guard !Task.isCancelled else { return }
            let ticket = self.context
            self.testingSpeed = true
            let handle = CommandHandle(); self.speedHandle = handle
            do {
                let measured = try await SpeedTester.run(handle: handle)
                guard ticket == self.context, !Task.isCancelled else { return }
                self.speed = measured
            } catch {
                guard ticket == self.context, !Task.isCancelled else { return }
                self.speedMessage = error.localizedDescription
            }
            self.testingSpeed = false; self.speedHandle = nil
        }
    }
    func cancelSpeed() {
        guard testingSpeed else { return }
        speedHandle?.cancel(); speedTask?.cancel()
        speedTask = nil; speedHandle = nil; testingSpeed = false
        speedMessage = "Test cancelled. Previous completed measurements, if any, are unchanged."
    }

    func setAlerts(_ enabled: Bool) {
        if !enabled { alertsEnabled = false; UserDefaults.standard.set(false, forKey: "alertsEnabled"); return }
        Task {
            do {
                let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                alertsEnabled = allowed
                UserDefaults.standard.set(allowed, forKey: "alertsEnabled")
                await refreshNotificationStatus()
            } catch { notice = "Notification permission couldn't be requested. You can review it in System Settings." }
        }
    }
    func refreshNotificationStatus() async {
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationStatus = status == .authorized ? "Allowed" : status == .denied ? "Denied" : "Not requested"
        alertsEnabled = status == .authorized && UserDefaults.standard.bool(forKey: "alertsEnabled")
    }
    private func notifyIfNeeded() async {
        guard alertsEnabled, Date().timeIntervalSince(lastAlert) >= 1800,
              needsAttention || report?.title != "Checks passed" else { return }
        let content = UNMutableNotificationContent()
        content.title = "Pulse WiFi · review your connection"
        content.body = "A connection or protection check needs attention. Open Pulse WiFi to review the findings."
        do {
            try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
            lastAlert = Date()
        } catch { notice = "The notification couldn't be delivered." }
    }

    func openSettings(_ destination: String) {
        let target: String
        switch destination {
        case "firewall": target = "com.apple.Network-Settings.extension?Firewall"
        case "relay": target = "com.apple.systempreferences.AppleIDSettings?iCloud"
        case "location": target = "com.apple.preference.security?Privacy_LocationServices"
        case "notifications": target = "com.apple.Notifications-Settings.extension"
        default: target = "com.apple.wifi-settings-extension"
        }
        if let url = URL(string: "x-apple.systempreferences:\(target)"), NSWorkspace.shared.open(url) { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}
