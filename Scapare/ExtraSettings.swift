import AppKit

final class ExtraSettings: NSObject, NSWindowDelegate {
    private static var current: ExtraSettings?
    private let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 540), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    private let elements = NSButton(checkboxWithTitle: "识别界面控件（需要辅助功能权限）", target: nil, action: nil)
    private let corner = NSButton(checkboxWithTitle: "启用屏幕触发角（高级功能中配置）", target: nil, action: nil)
    private let cursor = NSButton(checkboxWithTitle: "截图包含鼠标指针", target: nil, action: nil)
    private let restore = NSButton(checkboxWithTitle: "自动保存贴图并在下次启动时恢复", target: nil, action: nil)
    private let autoSave = NSButton(checkboxWithTitle: "复制、贴图时自动另存 PNG", target: nil, action: nil)
    static func show() {
        if let current { current.window.makeKeyAndOrderFront(nil); return }
        let instance = ExtraSettings(); current = instance; instance.window.center(); instance.window.makeKeyAndOrderFront(nil)
    }
    private override init() {
        super.init(); window.title = "更多设置 · Scapare"; window.isReleasedWhenClosed = false; window.delegate = self
        cursor.state = SettingsManager.captureCursor ? .on : .off; restore.state = SettingsManager.restorePins ? .on : .off; autoSave.state = SettingsManager.autoSave ? .on : .off
        elements.state = ElementPicker.enabled ? .on : .off
        corner.state = UserDefaults.standard.bool(forKey: "hot_corner") ? .on : .off
        for button in [cursor, restore, autoSave, elements, corner] { button.target = self; button.action = #selector(changed(_:)) }
        let folder = NSButton(title: "选择快速保存文件夹…", target: self, action: #selector(chooseFolder))
        let hint = NSTextField(wrappingLabelWithString: "贴图备份保存在本机应用数据目录。关闭自动恢复不会删除旧备份。截图历史只保留在本次运行中。")
        hint.font = .systemFont(ofSize: 12); hint.textColor = .secondaryLabelColor
        let done = NSButton(title: "完成", target: self, action: #selector(close)); done.keyEquivalent = "\r"
        let shortcuts = NSButton(title: "更多全局快捷键…", target: self, action: #selector(showShortcuts))
        let stack = NSStackView(views: [cursor, elements, corner, restore, autoSave, folder, shortcuts, NSButton(title: "外观与调色板…", target: self, action: #selector(appearance)), NSButton(title: "高级功能…", target: self, action: #selector(advanced)), hint, done]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false; window.contentView?.addSubview(stack)
        if let content = window.contentView { NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24), stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24), hint.widthAnchor.constraint(equalTo: stack.widthAnchor)]) }
    }
    @objc private func changed(_ sender: NSButton) {
        if sender === elements {
            ElementPicker.enabled = sender.state == .on
            if sender.state == .on && !ElementPicker.requestPermission() { AppDialogs.error("请在系统设置的「隐私与安全性 → 辅助功能」中允许 Scapare，允许后控件识别才会生效。窗口识别仍可使用。") }
        }
        if sender === corner { UserDefaults.standard.set(sender.state == .on, forKey: "hot_corner") }
        if sender === cursor { SettingsManager.captureCursor = sender.state == .on }
        if sender === restore { SettingsManager.restorePins = sender.state == .on; if sender.state == .on { PinManager.shared.saveNow() } }
        if sender === autoSave {
            if sender.state == .on && !ImageFileSaver.chooseQuickSaveFolder() { sender.state = .off }
            SettingsManager.autoSave = sender.state == .on
        }
    }
    @objc private func appearance() { AppearanceWindow.show() }
    @objc private func advanced() { AdvancedSettings.show() }
    @objc private func showShortcuts() { AdditionalShortcutWindow.show() }
    @objc private func chooseFolder() { _ = ImageFileSaver.chooseQuickSaveFolder() }
    @objc private func close() { window.close() }
    func windowWillClose(_ notification: Notification) { Self.current = nil }
}
