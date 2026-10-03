import AppKit

@main
struct StoreAssets {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        NSApp.appearance = NSAppearance(named: .aqua)
        let size = CGSize(width: 1280, height: 800)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        func text(_ value: String, _ point: CGPoint, _ font: NSFont, _ color: NSColor = .labelColor) {
            (value as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
        }
        text("SCAPARE · 截图示例", CGPoint(x: 110, y: 684), .systemFont(ofSize: 14, weight: .medium), .secondaryLabelColor)
        text("让信息留在手边", CGPoint(x: 110, y: 614), .systemFont(ofSize: 42, weight: .bold))
        text("框选重点、添加标注，把需要的信息整理成一张图片。", CGPoint(x: 110, y: 570), .systemFont(ofSize: 18), .secondaryLabelColor)
        let cards: [(String, String, String)] = [
            ("01 / 收集", "截取关键信息", "区域与滚动长截图，保留需要阅读的内容。"),
            ("02 / 表达", "标出重点", "使用箭头、文字与高亮，说明图片中的细节。"),
            ("03 / 提取", "将图片转为文字", "使用离线 OCR 识别中文和英文，再复制结果。"),
            ("04 / 参考", "贴在桌面上", "拖动、缩放和调整透明度，随时查看参考图片。")
        ]
        for (i, card) in cards.enumerated() {
            let x: CGFloat = i % 2 == 0 ? 110 : 654
            let y: CGFloat = i < 2 ? 336 : 124
            let rect = CGRect(x: x, y: y, width: 516, height: 182)
            NSColor.white.setFill(); NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16).fill()
            text(card.0, CGPoint(x: x+26, y: y+138), .systemFont(ofSize: 14, weight: .semibold), .systemBlue)
            text(card.1, CGPoint(x: x+26, y: y+96), .systemFont(ofSize: 25, weight: .bold))
            text(card.2, CGPoint(x: x+26, y: y+56), .systemFont(ofSize: 17), .secondaryLabelColor)
        }
        image.unlockFocus()
        let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let session = EditingSession()
        var rect = Annotation(tool: .rectangle, color: .systemRed, lineWidth: 3)
        rect.start = CGPoint(x: 668, y: 418); rect.end = CGPoint(x: 896, y: 475); rect.cornerRadius = 6
        var arrow = Annotation(tool: .arrow, color: .systemRed, lineWidth: 3)
        arrow.start = CGPoint(x: 948, y: 546); arrow.end = CGPoint(x: 866, y: 482)
        session.snapshot.annotations = [rect, arrow]
        let editor = EditorView(shot: DisplayShot(screen: NSScreen.main!, image: cg), controller: .shared, session: session, canvasSize: size)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = editor
        editor.setSelection(CGRect(x: 90, y: 96, width: 1100, height: 630))
        editor.layoutSubtreeIfNeeded()
        editor.displayIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
        editor.layoutSubtreeIfNeeded()
        let cached = editor.bitmapImageRepForCachingDisplay(in: editor.bounds)!
        editor.cacheDisplay(in: editor.bounds, to: cached)
        cached.size = size
        let cacheImage = NSImage(size: size); cacheImage.addRepresentation(cached)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1280, pixelsHigh: 800, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        cacheImage.draw(in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/private/tmp/scapare-store-assets/Scapare-1.1.2-capture-1280x800.png"))
        print("Rendered production EditorView and EditorToolbar at 1280x800")
    }
}
