# Pulse WiFi

A lightweight, native Mac app and companion to [Pulse](https://github.com/AevarOfjord/Pulse-Mac-Monitoring) for Apple-silicon Macs running macOS 14 or later. Dashboards, settings, charts, and compact native menu panels follow macOS Light/Dark appearance, with matching Pulse accents and typography.

## Install

Download the [Pulse WiFi 1.0 preview ZIP](https://github.com/AevarOfjord/Pulse-Mac-Wifi/releases/download/v1.0.0-preview.2/Pulse-WiFi-1.0-AppleSilicon-Preview.zip), or visit [Releases](https://github.com/AevarOfjord/Pulse-Mac-Wifi/releases/tag/v1.0.0-preview.2) for its checksum and notes. Extract the ZIP, move **Pulse WiFi.app** to Applications, and open it. Source-code archives are for building the project, not installing the app.

The preview is locally signed and **not notarized**. If macOS blocks a download you trust, review **System Settings → Privacy & Security → Open Anyway**, following [Apple's instructions](https://support.apple.com/102445). Do not disable Gatekeeper globally.

## Features

- Current Wi-Fi, signal, channel, band, and reported security mode using CoreWLAN.
- Read-only checks for the macOS application firewall and stealth-mode configuration.
- Honest manual guidance for Private Wi-Fi Address and iCloud Private Relay; neither is falsely marked verified.
- Small HTTPS connectivity checks and a separate possible-sign-in probe.
- On-demand download/upload tests using Apple's `networkQuality`, with cancellation and validation of results.
- Menu-bar panel, dashboard, signal history, settings, optional notifications, and network-change handling.
- Live Wi-Fi signal strength in the menu bar, such as `−54 dBm`, with a separate protection warning indicator. Paused, disconnected, and unavailable readings are labeled explicitly; the text can be hidden in Settings.
- The compact native menu-bar panel shows your Wi-Fi name, frequency band, channel, signal, security, and protection summary. Run or cancel speed/connection tests directly from it; completed speed tests show download, upload, idle latency, loaded responsiveness, and their timestamp. Dashboard, pause/resume, Settings, and Quit share one compact action row.
- Metered/Low Data Mode connections skip automatic external tests. Wi-Fi and security readings slow down in the background.

## Build and run

Requires Xcode or Apple Command Line Tools with **Swift 6+**. Running the packaged app does not require developer tools.

```sh
git clone https://github.com/AevarOfjord/Pulse-Mac-Wifi.git
cd Pulse-Mac-Wifi
bash scripts/test.sh
bash scripts/build-app.sh --open
bash scripts/package-release.sh
```

The locally signed app is placed in `build/Pulse WiFi.app`; the preview ZIP and SHA-256 checksum are alongside it. Pulse WiFi appears in the Dock and Command-Tab like a regular Mac app, with a menu-bar panel for quick access. It stays running when its dashboard is closed. Click its Dock icon to reopen the dashboard. Choose Quit in its panel or press Command-Q to stop it. This is an independent package; building it does not rebuild or modify Pulse. Quit a running local build before replacing it.

To show the network name, click **Enable Wi-Fi details** and grant Location permission. macOS requires this authorization for Wi-Fi identifiers. The app does not request location updates or collect coordinates. Missing permissions and unsupported readings remain unavailable.

## Privacy and measurements

Observations stay in memory; only app preferences are persisted. Signal history is bounded to ten minutes and resets when the observed network changes. Notifications omit network names and addresses. No analytics, account, stored browsing history, router credentials, or remote device scans.

Automatic connection checks are optional (enabled initially), no more than once every five minutes, and skipped on metered/Low Data Mode connections. Each makes three HTTPS requests to `www.apple.com/library/test/success.html` and one credential-free HTTP request to `captive.apple.com/hotspot-detect.html`. Redirects are not followed. TLS validation stays enabled. A failed endpoint probe does not prove that all internet access is down. HTTPS response timing is not ICMP ping, and failed HTTPS probes are not IP packet loss.

Speed tests run only on demand and transfer substantial data to Apple's test infrastructure. Tests follow the current system route, including a VPN, rather than bypassing it by binding to the physical Wi-Fi interface. Switching networks or pausing cancels in-flight tests. Completed results belong to the current observed network context and are discarded when it changes.

Protection findings distinguish configuration from demonstrated behavior. A firewall enabled setting is not an external blocking test; a fast or encrypted connection does not certify hotspot trustworthiness. Private Relay coverage includes Safari and certain other traffic, not every app. Private address and relay activation are deliberately manual checks until a reliable verification mechanism is available.

## Validation

```sh
bash scripts/test.sh
swift run --disable-sandbox WiFiDiagnostics
swift run --disable-sandbox WiFiDiagnostics --connection
```

Diagnostics omit SSIDs, addresses, gateways, and raw command output. The optional `--speed` diagnostic runs a real, data-intensive speed test. Tests exercise security classifications, unknown states, read-only firewall parsing, network identity changes, partial/error speed results, decimal Mbps conversion, probe failure semantics, and command cancellation/timeouts.

The CI workflow checks Apple-silicon runners on macOS 15 and 26; see [Actions](https://github.com/AevarOfjord/Pulse-Mac-Wifi/actions) for actual results. The deployment target is macOS 14. Physical testing has been on an M5 Pro running macOS 27.0.1; other hardware and OS versions may expose different Wi-Fi details.

The preview is ad-hoc signed, not notarized. Developer ID signing/notarization can be added when a signing identity is available.
