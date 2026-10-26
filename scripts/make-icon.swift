import AppKit
let destination = CommandLine.arguments[1]
func bigEndian(_ number: UInt32) -> Data { var value = number.bigEndian; return withUnsafeBytes(of: &value) { Data($0) } }
var chunks = Data()
for (size, type) in [(128, "ic07"), (256, "ic08"), (512, "ic09"), (1024, "ic10")] {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    NSColor(calibratedRed: 0.06, green: 0.10, blue: 0.14, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.05, y: s * 0.05, width: s * 0.9, height: s * 0.9), xRadius: s * 0.2, yRadius: s * 0.2).fill()
    if let symbol = NSImage(systemSymbolName: "wifi", accessibilityDescription: nil) {
        let colored = NSImage(size: symbol.size)
        colored.lockFocus()
        symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        NSColor(calibratedRed: 0.45, green: 0.89, blue: 0.74, alpha: 1).setFill()
        NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
        colored.unlockFocus()
        colored.draw(in: NSRect(x: s * 0.23, y: s * 0.29, width: s * 0.54, height: s * 0.43))
    }
    image.unlockFocus()
    let png = NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    chunks.append(Data(type.utf8)); chunks.append(bigEndian(UInt32(png.count + 8))); chunks.append(png)
}
var data = Data("icns".utf8); data.append(bigEndian(UInt32(chunks.count + 8))); data.append(chunks)
try data.write(to: URL(fileURLWithPath: destination))
