import AppKit

/// A deliberately local renderer for clipboard text. Only inline text formatting is
/// interpreted; no browser, scripts, external resources, or document imports run.
enum ClipboardText {
    static func html(_ input: String) -> NSAttributedString {
        let clean = String(input.prefix(300_000)).replacingOccurrences(of: "(?is)<(script|style|head)[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        let expression = try! NSRegularExpression(pattern: "<[^>]*>|[^<]+")
        let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.black]
        let result = NSMutableAttributedString(string: "")
        var styles: [(tag: String, attributes: [NSAttributedString.Key: Any])] = [("", base)]
        func newline() { if result.length > 0 && !result.string.hasSuffix("\n") { result.append(NSAttributedString(string: "\n", attributes: styles.last!.attributes)) } }
        for match in expression.matches(in: clean, range: NSRange(clean.startIndex..., in: clean)) {
            guard let range = Range(match.range, in: clean) else { continue }
            let token = String(clean[range])
            if !token.hasPrefix("<") { result.append(NSAttributedString(string: entities(token), attributes: styles.last!.attributes)); continue }
            let lower = token.lowercased()
            let tag = lower.dropFirst(lower.hasPrefix("</") ? 2 : 1).prefix { $0.isLetter || $0.isNumber }
            let name = String(tag)
            let blocks = ["p", "div", "li", "pre", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6"]
            if name == "br" { result.append(NSAttributedString(string: "\n", attributes: styles.last!.attributes)); continue }
            if lower.hasPrefix("</") {
                if let index = styles.lastIndex(where: { $0.tag == name }), index > 0 { styles.removeSubrange(index...) }
                if blocks.contains(name) { newline() }; continue
            }
            guard ["b", "strong", "i", "em", "u", "s", "code", "span", "font", "a"].contains(name) || blocks.contains(name), styles.count < 50 else { continue }
            if blocks.contains(name) { newline() }
            var attrs = styles.last!.attributes
            let font = attrs[.font] as? NSFont ?? NSFont.systemFont(ofSize: 18)
            if ["b", "strong", "h1", "h2", "h3", "h4", "h5", "h6"].contains(name) || lower.contains("font-weight: bold") || lower.contains("font-weight:700") { attrs[.font] = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
            if ["i", "em"].contains(name) { attrs[.font] = NSFontManager.shared.convert(attrs[.font] as! NSFont, toHaveTrait: .italicFontMask) }
            if name == "u" { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            if name == "s" { attrs[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            if ["code", "pre"].contains(name) { attrs[.font] = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular); attrs[.backgroundColor] = NSColor(white: 0.94, alpha: 1) }
            if name.hasPrefix("h"), let level = Int(name.dropFirst()) { attrs[.font] = NSFont.boldSystemFont(ofSize: CGFloat(30 - level * 2)) }
            if name == "li" { result.append(NSAttributedString(string: "• ", attributes: attrs)) }
            if let regex = try? NSRegularExpression(pattern: "(?i)(?:^|[;\"'\\s])color\\s*[:=]\\s*[\"']?#([0-9a-f]{6})(?:[^0-9a-f]|$)"), let match = regex.firstMatch(in: token, range: NSRange(token.startIndex..., in: token)), let range = Range(match.range(at: 1), in: token), let color = NSColor(hex: String(token[range])) { attrs[.foregroundColor] = color }
            styles.append((name, attrs))
        }
        return result
    }
    static func entities(_ text: String) -> String {
        var result = text
        let pattern = try! NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);")
        for match in pattern.matches(in: result, range: NSRange(result.startIndex..., in: result)).reversed() {
            guard let valueRange = Range(match.range(at: 1), in: result), let full = Range(match.range, in: result) else { continue }
            let value = String(result[valueRange]); let n = value.hasPrefix("x") ? UInt32(value.dropFirst(), radix: 16) : UInt32(value)
            if let n, let scalar = UnicodeScalar(n) { result.replaceSubrange(full, with: String(scalar)) }
        }
        for (entity, character) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&amp;", "&")] { result = result.replacingOccurrences(of: entity, with: character) }
        return result
    }
    static func image(_ text: NSAttributedString) -> NSImage {
        let maxHeight: CGFloat = 20_000
        let measured = text.boundingRect(with: CGSize(width: 760, height: maxHeight), options: [.usesLineFragmentOrigin, .usesFontLeading])
        let width = Int(max(160, min(800, ceil(measured.width) + 40))), height = Int(max(70, min(maxHeight + 40, ceil(measured.height) + 40)))
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        text.draw(with: CGRect(x: 20, y: 20, width: width - 40, height: height - 40), options: [.usesLineFragmentOrigin, .usesFontLeading]); NSGraphicsContext.restoreGraphicsState()
        return NSImage(cgImage: context.makeImage()!, size: CGSize(width: width, height: height))
    }
}
