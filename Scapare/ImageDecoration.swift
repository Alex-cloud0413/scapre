import AppKit

struct ImageDecoration {
    var cornerRadius: CGFloat = 0
    var borderWidth: CGFloat = 0
    var shadow = false
    func apply(_ image: CGImage) -> CGImage? {
        guard cornerRadius > 0 || borderWidth > 0 || shadow else { return image }
        let padding = Int(ceil(borderWidth + (shadow ? 18 : 0)))
        let width = image.width + padding * 2, height = image.height + padding * 2
        guard width * height <= 60_000_000,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let rect = CGRect(x: padding, y: padding, width: image.width, height: image.height)
        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if shadow { context.setShadow(offset: CGSize(width: 0, height: -3), blur: 8, color: NSColor.black.withAlphaComponent(0.35).cgColor) }
        context.addPath(path); context.setFillColor(NSColor.white.cgColor); context.fillPath()
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.saveGState(); context.addPath(path); context.clip(); context.draw(image, in: rect); context.restoreGState()
        if borderWidth > 0 { context.addPath(path); context.setStrokeColor(NSColor.gray.cgColor); context.setLineWidth(borderWidth); context.strokePath() }
        return context.makeImage()
    }
}
