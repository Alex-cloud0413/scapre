import AppKit
import UniformTypeIdentifiers

@MainActor
enum ImageFileSaver {
    static func save(_ image: NSImage) -> SaveOutcome {
        guard let data = image.pngData else {
            let alert = NSAlert()
            alert.messageText = "无法生成图片"
            alert.informativeText = "截图仍然保留，请返回后重试。"
            alert.runModal()
            return .cancelled
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        panel.nameFieldStringValue = "截图 \(formatter.string(from: Date())).png"
        NSApp.activate(ignoringOtherApps: true)
        return SaveFlow.run(data: data, chooseURL: {
            panel.runModal() == .OK ? panel.url : nil
        }, write: { data, url in
            try data.write(to: url, options: .atomic)
        }, retry: { error in
            let alert = NSAlert()
            alert.messageText = "图片未保存"
            alert.informativeText = "\(error.localizedDescription)\n\n截图仍然保留，可以选择其他位置重试。"
            alert.addButton(withTitle: "重新选择位置")
            alert.addButton(withTitle: "返回")
            return alert.runModal() == .alertFirstButtonReturn
        })
    }
}
