// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PulseWiFi",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PulseWiFi", targets: ["PulseWiFi"]),
        .executable(name: "WiFiDiagnostics", targets: ["WiFiDiagnostics"])
    ],
    targets: [
        .target(name: "WiFiCore", linkerSettings: [.linkedFramework("CoreWLAN"), .linkedFramework("SystemConfiguration")]),
        .executableTarget(name: "PulseWiFi", dependencies: ["WiFiCore"]),
        .executableTarget(name: "WiFiDiagnostics", dependencies: ["WiFiCore"]),
        .testTarget(name: "WiFiCoreTests", dependencies: ["WiFiCore"])
    ],
    swiftLanguageModes: [.v5]
)
