//
//  Helpers.swift
//  Scapare
//
//  一些零碎的小帮助函数，被其它文件复用。
//

import AppKit

extension NSScreen {
    // 取得这块屏幕对应的系统「显示器编号」，用来和 ScreenCaptureKit 的屏幕做匹配。
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID
    }
}

extension NSImage {
    // 把图片转成 PNG 格式的数据，用于保存成文件或写入剪贴板。
    var pngData: Data? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

// MARK: - 颜色扩展

extension NSColor {
    /// 从十六进制字符串创建颜色，支持 "CC0000" 或 "#CC0000"
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6, let int = UInt32(hex, radix: 16) else { return nil }
        let r = CGFloat((int >> 16) & 0xFF) / 255.0
        let g = CGFloat((int >> 8) & 0xFF) / 255.0
        let b = CGFloat(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }

    /// 导出为六位大写十六进制字符串，用于持久化
    var hexString: String {
        guard let rgb = usingColorSpace(.sRGB) ?? usingColorSpace(.deviceRGB) else { return "CC0000" }
        let r = Int(round(rgb.redComponent * 255))
        let g = Int(round(rgb.greenComponent * 255))
        let b = Int(round(rgb.blueComponent * 255))
        return String(format: "%02X%02X%02X", r, g, b)
    }
}

enum Clipboard {
    // 把一张图片放进系统剪贴板（之后可在别处 ⌘V 粘贴）。
    @discardableResult
    static func copy(image: NSImage, to pb: NSPasteboard = .general) -> Bool {
        // Prepare the image before replacing the user's clipboard.
        guard let data = image.pngData else { return false }
        let item = NSPasteboardItem()
        item.setData(data, forType: .png)
        if let tiff = image.tiffRepresentation { item.setData(tiff, forType: .tiff) }
        pb.clearContents()
        return pb.writeObjects([item])
    }

    // 把一段文字放进系统剪贴板。
    @discardableResult
    static func copy(text: String, to pb: NSPasteboard = .general) -> Bool {
        pb.clearContents()
        return pb.setString(text, forType: .string)
    }
}
