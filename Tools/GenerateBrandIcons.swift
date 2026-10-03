import AppKit
import Foundation

// Compile with Scapare/BrandIcon.swift and this file copied to main.swift.
guard CommandLine.arguments.count == 2 else { fatalError("Supply the app icon set directory") }
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
var entries: [[String: String]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)!
        rep.size = NSSize(width: pixels, height: pixels)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: pixels, height: pixels)).fill()
        let factor = CGFloat(pixels) / 1024
        BrandIcon.draw(in: NSRect(x: 313 * factor, y: 242 * factor,
            width: 398 * factor, height: 524 * factor), lineWidth: 26 * factor)
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)@\(scale)x.png"
        try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
        entries.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": entries, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: directory.appendingPathComponent("Contents.json"))
