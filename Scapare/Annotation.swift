import AppKit

enum AnnotationTool: String, Equatable, Codable, CaseIterable {
    case rectangle, ellipse, arrow, pen, text, line, polyline, highlighter, mosaic, blur, eraser, number, magnify
    var title: String {
        switch self {
        case .rectangle: return "矩形"; case .ellipse: return "椭圆"; case .arrow: return "箭头"
        case .pen: return "画笔"; case .text: return "文字"; case .line: return "直线"
        case .polyline: return "折线"; case .highlighter: return "高亮"; case .mosaic: return "马赛克"
        case .blur: return "模糊"; case .eraser: return "橡皮擦"; case .number: return "序号"; case .magnify: return "局部放大"
        }
    }
}

struct Annotation: Equatable, Codable {
    var tool: AnnotationTool
    var color: NSColor
    var lineWidth: CGFloat
    var start: CGPoint = .zero
    var end: CGPoint = .zero
    var points: [CGPoint] = []
    var text = ""
    var fontSize: CGFloat = 14
    var fontWeight: CGFloat = 0
    var textMaxWidth: CGFloat?
    var opacity: CGFloat = 1
    var dashed = false
    var filled = false
    var cornerRadius: CGFloat = 0
    var doubleArrow = false
    var ellipticalMask = false
    var number = 1
    var rotation: CGFloat = 0
    var textBackground: String?
    var textOutline: CGFloat = 0
    var fontName: String?
    var textOutlineColor: String?
    var arrowStyle: Int?

    func draw(source: CGImage? = nil, viewSize: CGSize = .zero) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        let b = unrotatedBounds
        transform.translateX(by: b.midX, yBy: b.midY)
        transform.rotate(byDegrees: rotation)
        transform.translateX(by: -b.midX, yBy: -b.midY)
        transform.concat()
        color.withAlphaComponent(opacity).set()
        func stroke(_ path: NSBezierPath) {
            path.lineWidth = lineWidth; path.lineCapStyle = .round; path.lineJoinStyle = .round
            if dashed { path.setLineDash([lineWidth * 3, lineWidth * 2], count: 2, phase: 0) }
            if filled { path.fill() } else { path.stroke() }
        }
        switch tool {
        case .rectangle:
            stroke(NSBezierPath(roundedRect: normalizedRect, xRadius: cornerRadius, yRadius: cornerRadius))
        case .ellipse: stroke(NSBezierPath(ovalIn: normalizedRect))
        case .arrow:
            drawArrow(from: start, to: end)
            if doubleArrow { drawArrow(from: end, to: start) }
        case .line:
            let path = NSBezierPath(); path.move(to: start); path.line(to: end); stroke(path)
        case .pen, .polyline, .highlighter:
            if tool == .highlighter && ellipticalMask {
                color.withAlphaComponent(opacity * 0.32).setFill(); NSBezierPath(ovalIn: normalizedRect).fill(); return
            }
            let vertices = tool == .polyline ? points + [end] : points
            guard vertices.count > 1 else { return }
            let path = NSBezierPath(); path.move(to: vertices[0])
            for p in vertices.dropFirst() { path.line(to: p) }
            if tool == .highlighter {
                color.withAlphaComponent(opacity * 0.32).setStroke()
                path.lineWidth = max(12, lineWidth * 5); path.lineCapStyle = .butt; path.lineJoinStyle = .round
                path.stroke()
            } else { stroke(path) }
        case .text:
            let rect = textBoundingRect()
            if let hex = textBackground, let bg = NSColor(hex: hex) { bg.setFill(); NSBezierPath(rect: rect.insetBy(dx: -3, dy: -2)).fill() }
            var attrs = textAttributes
            if textOutline > 0 { attrs[.strokeWidth] = -textOutline; attrs[.strokeColor] = textOutlineColor.flatMap { NSColor(hex: $0) } ?? NSColor.white }
            (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
        case .number:
            let rect = unrotatedBounds
            color.withAlphaComponent(opacity).setFill(); NSBezierPath(ovalIn: rect).fill()
            let label = String(number) as NSString
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: rect.height * 0.57, weight: .bold), .foregroundColor: NSColor.white]
            let size = label.size(withAttributes: attrs)
            label.draw(at: CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2), withAttributes: attrs)
        case .mosaic, .blur, .eraser, .magnify:
            guard let source, normalizedRect.width > 0, normalizedRect.height > 0 else { return }
            let region = tool == .magnify ? normalizedRect.insetBy(dx: normalizedRect.width / 4, dy: normalizedRect.height / 4) : normalizedRect
            let pixels = PixelGeometry.cropRect(selection: region, viewSize: viewSize, imageSize: CGSize(width: source.width, height: source.height))
            guard !pixels.isNull else { return }
            guard let image = ImageEffects.region(source, pixels: pixels, tool: tool, amount: max(8, lineWidth * 5)) else {
                // A failed redaction must never reveal the unredacted source.
                NSColor.black.setFill(); NSBezierPath(rect: normalizedRect).fill(); return
            }
            if ellipticalMask { NSBezierPath(ovalIn: normalizedRect).addClip() }
            NSImage(cgImage: image, size: normalizedRect.size).draw(in: normalizedRect)
            if tool == .magnify { color.setStroke(); let outline = NSBezierPath(rect: normalizedRect); outline.lineWidth = 2; outline.stroke() }
        }
    }
    private var textAttributes: [NSAttributedString.Key: Any] {
        [.font: AppearanceSettings.font(size: fontSize, weight: fontWeight, name: fontName ?? ""), .foregroundColor: color.withAlphaComponent(opacity)]
    }
    var normalizedRect: CGRect { CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)) }
    func textBoundingRect() -> CGRect {
        let size = (text as NSString).boundingRect(with: NSSize(width: textMaxWidth ?? .greatestFiniteMagnitude, height: .greatestFiniteMagnitude),
                                                   options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: textAttributes).size
        return CGRect(origin: start, size: CGSize(width: max(1, size.width), height: max(1, size.height)))
    }
    private var unrotatedBounds: CGRect {
        if tool == .text { return textBoundingRect() }
        if tool == .number { let s = max(24, fontSize * 1.7); return CGRect(x: start.x - s / 2, y: start.y - s / 2, width: s, height: s) }
        if !points.isEmpty {
            return points.reduce(CGRect(origin: points[0], size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }.union(CGRect(origin: end, size: .zero))
        }
        return normalizedRect
    }
    var boundingRect: CGRect {
        let b = unrotatedBounds, radians = rotation * .pi / 180
        let size = CGSize(width: abs(cos(radians)) * b.width + abs(sin(radians)) * b.height,
                          height: abs(sin(radians)) * b.width + abs(cos(radians)) * b.height)
        return CGRect(x: b.midX - size.width / 2, y: b.midY - size.height / 2, width: size.width, height: size.height).insetBy(dx: -max(4, lineWidth), dy: -max(4, lineWidth))
    }
    mutating func translate(x: CGFloat, y: CGFloat) {
        start.x += x; start.y += y; end.x += x; end.y += y
        points = points.map { CGPoint(x: $0.x + x, y: $0.y + y) }
    }
    private func drawArrow(from: CGPoint, to: CGPoint) {
        let length = max(1, hypot(to.x - from.x, to.y - from.y)), angle = atan2(to.y - from.y, to.x - from.x)
        let headLength = min(length, 12 + lineWidth * 3), headAngle = CGFloat.pi / 7
        let path = NSBezierPath(); path.move(to: from); path.line(to: to)
        path.lineWidth = lineWidth; path.lineCapStyle = .round
        if dashed { path.setLineDash([lineWidth * 3, lineWidth * 2], count: 2, phase: 0) }
        path.stroke()
        let head = NSBezierPath(); head.move(to: CGPoint(x: to.x - headLength * cos(angle - headAngle), y: to.y - headLength * sin(angle - headAngle)))
        head.line(to: to); head.line(to: CGPoint(x: to.x - headLength * cos(angle + headAngle), y: to.y - headLength * sin(angle + headAngle)))
        if arrowStyle == 1 { head.close(); head.fill() }
        else if arrowStyle == 2 { NSBezierPath(ovalIn: CGRect(x: to.x - lineWidth * 2, y: to.y - lineWidth * 2, width: lineWidth * 4, height: lineWidth * 4)).fill() }
        else { head.lineWidth = lineWidth; head.lineCapStyle = .round; head.stroke() }
    }
    private enum CodingKeys: String, CodingKey { case tool, color, lineWidth, start, end, points, text, fontSize, fontWeight, textMaxWidth, opacity, dashed, filled, cornerRadius, doubleArrow, ellipticalMask, number, rotation, textBackground, textOutline, fontName, textOutlineColor, arrowStyle }
    init(tool: AnnotationTool, color: NSColor, lineWidth: CGFloat) { self.tool = tool; self.color = color; self.lineWidth = lineWidth }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tool = try c.decode(AnnotationTool.self, forKey: .tool); color = NSColor(hex: try c.decode(String.self, forKey: .color)) ?? .red
        lineWidth = try c.decode(CGFloat.self, forKey: .lineWidth); start = try c.decode(CGPoint.self, forKey: .start); end = try c.decode(CGPoint.self, forKey: .end)
        points = try c.decode([CGPoint].self, forKey: .points); text = try c.decode(String.self, forKey: .text)
        fontSize = try c.decode(CGFloat.self, forKey: .fontSize); fontWeight = try c.decode(CGFloat.self, forKey: .fontWeight); textMaxWidth = try c.decodeIfPresent(CGFloat.self, forKey: .textMaxWidth)
        opacity = try c.decode(CGFloat.self, forKey: .opacity); dashed = try c.decode(Bool.self, forKey: .dashed); filled = try c.decode(Bool.self, forKey: .filled)
        cornerRadius = try c.decode(CGFloat.self, forKey: .cornerRadius); doubleArrow = try c.decode(Bool.self, forKey: .doubleArrow)
        ellipticalMask = try c.decode(Bool.self, forKey: .ellipticalMask); number = try c.decode(Int.self, forKey: .number); rotation = try c.decode(CGFloat.self, forKey: .rotation)
        arrowStyle = try c.decodeIfPresent(Int.self, forKey: .arrowStyle)
        fontName = try c.decodeIfPresent(String.self, forKey: .fontName); textOutlineColor = try c.decodeIfPresent(String.self, forKey: .textOutlineColor)
        textBackground = try c.decodeIfPresent(String.self, forKey: .textBackground); textOutline = try c.decode(CGFloat.self, forKey: .textOutline)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(tool, forKey: .tool); try c.encode(color.hexString, forKey: .color); try c.encode(lineWidth, forKey: .lineWidth)
        try c.encode(start, forKey: .start); try c.encode(end, forKey: .end); try c.encode(points, forKey: .points); try c.encode(text, forKey: .text)
        try c.encode(fontSize, forKey: .fontSize); try c.encode(fontWeight, forKey: .fontWeight); try c.encodeIfPresent(textMaxWidth, forKey: .textMaxWidth)
        try c.encode(opacity, forKey: .opacity); try c.encode(dashed, forKey: .dashed); try c.encode(filled, forKey: .filled); try c.encode(cornerRadius, forKey: .cornerRadius)
        try c.encode(doubleArrow, forKey: .doubleArrow); try c.encode(ellipticalMask, forKey: .ellipticalMask); try c.encode(number, forKey: .number)
        try c.encodeIfPresent(arrowStyle, forKey: .arrowStyle)
        try c.encodeIfPresent(fontName, forKey: .fontName); try c.encodeIfPresent(textOutlineColor, forKey: .textOutlineColor)
        try c.encode(rotation, forKey: .rotation); try c.encodeIfPresent(textBackground, forKey: .textBackground); try c.encode(textOutline, forKey: .textOutline)
    }
}

enum ImageEffects {
    private static var cachedSource: CGImage?
    private static var regions: [String: CGImage] = [:]
    static func region(_ source: CGImage, pixels: CGRect, tool: AnnotationTool, amount: CGFloat) -> CGImage? {
        if cachedSource.map({ ObjectIdentifier($0) }) != ObjectIdentifier(source) { regions.removeAll(); cachedSource = source }
        let key = "\(pixels)-\(tool.rawValue)-\(amount)"
        if let cached = regions[key] { return cached }
        guard let crop = source.cropping(to: pixels), let result = redact(crop, tool: tool, amount: amount) else { return nil }
        if [.mosaic, .blur].contains(tool), result.width * result.height <= 8_000_000 {
            if regions.values.reduce(0, { $0 + $1.width * $1.height }) + result.width * result.height > 12_000_000 { regions.removeAll() }
            regions[key] = result
        }
        return result
    }
    static func redact(_ image: CGImage, tool: AnnotationTool, amount: CGFloat) -> CGImage? {
        guard tool == .mosaic || tool == .blur else { return image }
        guard let raster = try? PixelRaster(image) else { return nil }
        return (tool == .mosaic ? PixelFilters.mosaic(raster, block: Int(amount)) : PixelFilters.blur(raster, radius: Int(amount / 2))).image()
    }
    static func colorTransform(_ image: CGImage, grayscale: Bool, inverted: Bool) -> CGImage? {
        guard grayscale || inverted else { return image }
        guard var raster = try? PixelRaster(image) else { return nil }
        for i in stride(from: 0, to: raster.bytes.count, by: 4) {
            if grayscale {
                let l = UInt8((Int(raster.bytes[i]) * 77 + Int(raster.bytes[i+1]) * 150 + Int(raster.bytes[i+2]) * 29) >> 8)
                raster.bytes[i] = l; raster.bytes[i+1] = l; raster.bytes[i+2] = l
            }
            if inverted { for c in 0..<3 { raster.bytes[i+c] = raster.bytes[i+3] &- min(raster.bytes[i+3], raster.bytes[i+c]) } }
        }
        return raster.image()
    }
}

extension Annotation {
    var isValid: Bool {
        let numbers = [start.x, start.y, end.x, end.y, lineWidth, fontSize, fontWeight, opacity, cornerRadius, rotation, textOutline]
        return numbers.allSatisfy { $0.isFinite && abs($0) <= 100_000 }
            && (0.5...100).contains(lineWidth) && (6...300).contains(fontSize) && (0...1).contains(opacity)
            && (-1...1).contains(fontWeight) && (arrowStyle.map { (0...2).contains($0) } ?? true)
            && (0...2000).contains(cornerRadius) && (0...20).contains(textOutline)
            && (fontName?.count ?? 0) < 200 && (textOutlineColor.map { NSColor(hex: $0) != nil } ?? true)
            && points.count <= 100_000 && points.allSatisfy { $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 100_000 && abs($0.y) <= 100_000 }
            && text.count <= 100_000 && (textMaxWidth.map { $0.isFinite && $0 > 0 && $0 <= 100_000 } ?? true)
    }
}
