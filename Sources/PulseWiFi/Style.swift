import SwiftUI
import AppKit
import WiFiCore

typealias ViewState<Value> = SwiftUI.State<Value>

// Pulse's palette and panel treatment, with matching system-aware colors.
enum Palette {
    static let background = adaptive(light: 0xF4F6F8, dark: 0x0D1117)
    static let sidebar = adaptive(light: 0xECEFF3, dark: 0x10161E)
    static let panel = adaptive(light: 0xFFFFFF, dark: 0x141B24)
    static let border = adaptive(light: 0xD4DCE5, dark: 0x26313E)
    static let muted = adaptive(light: 0x536174, dark: 0x8290A4)
    static let mint = adaptive(light: 0x006B50, dark: 0x74E2BE)
    static let blue = adaptive(light: 0x245CCD, dark: 0x79A9FF)
    static let purple = adaptive(light: 0x6E4ABD, dark: 0xB49AFF)
    static let amber = adaptive(light: 0x915410, dark: 0xE9B978)
    static let cyan = adaptive(light: 0x00697B, dark: 0x6BD2E3)

    // Resolve against the drawing view's appearance, rather than caching the
    // system appearance at launch. Windows and menu extras update live.
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255,
                           blue: Double(value & 255) / 255, alpha: 1)
        })
    }
    static func color(_ level: FindingLevel) -> Color {
        switch level { case .good: return mint; case .attention: return amber; case .unknown: return muted }
    }
}
extension Color {
    init(hex: UInt32) { self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1) }
}
struct WiFiPanel<Content: View>: View {
    let title: String
    var symbol = "wifi"
    var color = Palette.mint
    var subtitle: String? = nil
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 9) {
                Image(systemName: symbol).foregroundStyle(color).font(.system(size: 14))
                Text(title).font(.system(size: 14, weight: .semibold))
                Spacer()
                if let subtitle { Text(subtitle).font(.system(size: 9, weight: .medium)).foregroundStyle(Palette.muted) }
            }
            content
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.border.opacity(0.7)))
    }
}
struct StatusPill: View {
    let text: String
    var level = FindingLevel.unknown
    var body: some View {
        HStack(spacing: 5) { Circle().fill(Palette.color(level)).frame(width: 5, height: 5); Text(text).font(.system(size: 10, weight: .medium)) }
            .foregroundStyle(Palette.color(level)).padding(.horizontal, 9).padding(.vertical, 6)
            .background(Palette.color(level).opacity(0.08), in: Capsule())
    }
}
struct DetailRow: View {
    let title: String
    let value: String
    var color = Color.primary
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(Palette.muted)
            Spacer(minLength: 20)
            Text(value).foregroundStyle(color).monospacedDigit().multilineTextAlignment(.trailing).textSelection(.enabled)
        }.font(.system(size: 12))
    }
}
struct ActionButton: View {
    let title: String
    var symbol = "arrow.clockwise"
    var prominent = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .foregroundStyle(prominent ? Palette.background : Palette.mint)
                .background(prominent ? Palette.mint : Palette.mint.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }
}
struct SmallMetric: View {
    let title: String
    let value: String
    let unit: String
    let caption: String
    let symbol: String
    var color = Palette.mint
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.muted)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value).font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(color)
                Text(unit).font(.system(size: 11)).foregroundStyle(Palette.muted)
            }
            Text(caption).font(.system(size: 10)).foregroundStyle(Palette.muted).lineLimit(2).frame(minHeight: 25, alignment: .top)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.border.opacity(0.7)))
    }
}
