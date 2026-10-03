import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageInputs {
    static func decode(_ data: Data) throws -> NSImage {
        guard data.count <= 100_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 30_000, height <= 30_000, width * height <= 60_000_000,
              let image = NSImage(data: data) else { throw ImageError.decode }
        return image
    }
    static func clipboard() throws -> NSImage {
        let pb = NSPasteboard.general
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], let first = urls.first {
            return try decode(Data(contentsOf: first, options: .mappedIfSafe))
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            if let data = pb.data(forType: type) { return try decode(data) }
        }
        if let html = pb.string(forType: .html), !html.isEmpty { return ClipboardText.image(ClipboardText.html(html)) }
        if let text = pb.string(forType: .string), !text.isEmpty { return textImage(text) }
        throw NSError(domain: "Scapare.Clipboard", code: 1, userInfo: [NSLocalizedDescriptionKey: "剪贴板中没有可贴出的图片、文字、色值或图片文件。"])
    }
    static func textImage(_ text: String) -> NSImage {
        let trimmed = String(text.prefix(100_000)).trimmingCharacters(in: .whitespacesAndNewlines)
        let color = NSColor(hex: trimmed)
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.black]
        if color == nil { return ClipboardText.image(NSAttributedString(string: trimmed, attributes: attrs)) }
        let label = ("#" + color!.hexString) as NSString
        let measured = label.boundingRect(with: CGSize(width: 760, height: 4000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
        let size = color == nil ? CGSize(width: max(160, min(800, ceil(measured.width) + 40)), height: max(70, min(4040, ceil(measured.height) + 40))) : CGSize(width: 260, height: 200)
        let image = NSImage(size: size)
        image.lockFocus(); NSColor.white.setFill(); NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        if let color { color.setFill(); NSBezierPath(rect: CGRect(x: 0, y: 50, width: size.width, height: size.height - 50)).fill() }
        label.draw(with: CGRect(x: 20, y: 20, width: size.width - 40, height: color == nil ? size.height - 40 : 26), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
        image.unlockFocus(); return image
    }
    static func openFiles(asPins: Bool) {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]; panel.allowsMultipleSelection = asPins
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            do {
                let data = try Data(contentsOf: url, options: .mappedIfSafe); let image = try decode(data)
                if asPins { PinManager.shared.add(image, originalData: data) } else { ImageWorkspace.open(image, title: url.lastPathComponent + " · Scapare") }
            } catch { AppDialogs.error(error.localizedDescription) }
        }
    }
    static func whiteboard(transparent: Bool) {
        let size = CGSize(width: 1200, height: 800)
        let ctx = CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        if !transparent { ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(origin: .zero, size: size)) }
        ImageWorkspace.open(NSImage(cgImage: ctx.makeImage()!, size: size), title: transparent ? "透明白板 · Scapare" : "白板 · Scapare")
    }
}
