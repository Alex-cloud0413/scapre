import AppKit
import UniformTypeIdentifiers

@MainActor
enum ImageFileSaver {
    static func encoded(_ image: NSImage, extension ext: String) throws -> Data {
        guard let tiff = image.tiffRepresentation, var rep = NSBitmapImageRep(data: tiff) else { throw ImageError.decode }
        let format: NSBitmapImageRep.FileType
        switch ext.lowercased() {
        case "jpg", "jpeg": format = .jpeg
        case "tif", "tiff": format = .tiff
        case "bmp": format = .bmp
        case "gif": format = .gif
        case "png": format = .png
        default: throw NSError(domain: "Scapare.Export", code: 1, userInfo: [NSLocalizedDescriptionKey: "请选择 PNG、JPEG、TIFF、BMP 或 GIF 格式。"])
        }
        if format == .jpeg, let source = rep.cgImage,
           let context = CGContext(data: nil, width: source.width, height: source.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
            let rect = CGRect(x: 0, y: 0, width: source.width, height: source.height)
            context.setFillColor(NSColor.white.cgColor); context.fill(rect); context.draw(source, in: rect)
            if let flattened = context.makeImage() { rep = NSBitmapImageRep(cgImage: flattened) }
        }
        guard let data = rep.representation(using: format, properties: [.compressionFactor: 0.95]) else { throw ImageError.decode }
        return data
    }
    static func save(_ image: NSImage) -> SaveOutcome {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.png, .jpeg, .tiff, .bmp, .gif]; panel.canCreateDirectories = true
        panel.nameFieldStringValue = filename()
        let format = NSPopUpButton(); format.addItems(withTitles: ["PNG", "JPEG", "TIFF", "BMP", "GIF"])
        let choice = ExportFormatChoice(panel: panel, popup: format); format.target = choice; format.action = #selector(ExportFormatChoice.changed)
        panel.accessoryView = format
        NSApp.activate(ignoringOtherApps: true)
        return withExtendedLifetime(choice) {
            SaveFlow.run(data: Data(), chooseURL: { panel.runModal() == .OK ? panel.url : nil }, write: { _, url in
                try encoded(image, extension: url.pathExtension).write(to: url, options: .atomic)
            }, retry: { error in
                let alert = NSAlert(); alert.messageText = "图片未保存"; alert.informativeText = "\(error.localizedDescription)\n截图仍然保留。"
                alert.addButton(withTitle: "重新选择位置"); alert.addButton(withTitle: "返回")
                return alert.runModal() == .alertFirstButtonReturn
            })
        }
    }
    static func filename() -> String {
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss.SSS"
        return "Scapare \(formatter.string(from: Date()))-\(UUID().uuidString.prefix(4)).png"
    }
    static func chooseQuickSaveFolder() -> Bool {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.canCreateDirectories = true; panel.prompt = "选择保存位置"
        panel.level = NSApp.keyWindow?.level ?? .normal
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(data, forKey: "quick_save_folder"); return true
        } catch { AppDialogs.error(error.localizedDescription); return false }
    }
    static func quickSave(_ image: NSImage, allowChoose: Bool = true) -> Bool {
        if UserDefaults.standard.data(forKey: "quick_save_folder") == nil {
            guard allowChoose && chooseQuickSaveFolder() else { return false }
        }
        do {
            guard let bookmark = UserDefaults.standard.data(forKey: "quick_save_folder") else { return false }
            var stale = false
            let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
            guard !stale else { throw NSError(domain: "Scapare", code: 2, userInfo: [NSLocalizedDescriptionKey: "保存位置已失效，请在更多设置中重新选择文件夹。"] ) }
            let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            try encoded(image, extension: "png").write(to: url.appendingPathComponent(filename()), options: .atomic)
            return true
        } catch { AppDialogs.error(error.localizedDescription); return false }
    }
    static func copyAsFile(_ image: NSImage) {
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ScapareClipboard", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(filename()); try encoded(image, extension: "png").write(to: url, options: .atomic)
            NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([url as NSURL])
        } catch { AppDialogs.error(error.localizedDescription) }
    }
}
private final class ExportFormatChoice: NSObject {
    weak var panel: NSSavePanel?
    let popup: NSPopUpButton
    init(panel: NSSavePanel, popup: NSPopUpButton) { self.panel = panel; self.popup = popup }
    @objc func changed() {
        let types: [UTType] = [.png, .jpeg, .tiff, .bmp, .gif]
        let ext = ["png", "jpg", "tiff", "bmp", "gif"][popup.indexOfSelectedItem]
        panel?.allowedContentTypes = [types[popup.indexOfSelectedItem]]
        if let value = panel?.nameFieldStringValue { panel?.nameFieldStringValue = (value as NSString).deletingPathExtension + "." + ext }
    }
}
