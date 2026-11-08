import AppKit
import ServiceManagement

@MainActor
final class SetupWindowController: NSObject, NSWindowDelegate {
    private static var current: SetupWindowController?
    let window: NSWindow
    private let recorder: ShortcutRecorder
    private let shortcutStatus = NSTextField(wrappingLabelWithString: "")
    private let loginStatus = NSTextField(wrappingLabelWithString: "")
    private let loginCheckbox = NSButton(checkboxWithTitle: "登录时启动 Scapare", target: nil, action: nil)
    private let loginSettingsButton = NSButton(title: "打开登录项设置…", target: nil, action: nil)
    private let updateShortcut: (UInt32, UInt32) throws -> Void

    static func showSettings(updateShortcut: @escaping (UInt32, UInt32) throws -> Void) {
        if let existing = current {
            NSApp.activate(ignoringOtherApps: true)
            existing.window.makeKeyAndOrderFront(nil)
            return
        }
        let controller = SetupWindowController(updateShortcut: updateShortcut)
        current = controller
        NSApp.activate(ignoringOtherApps: true)
        controller.window.center()
        controller.window.makeKeyAndOrderFront(nil)
    }
    init(updateShortcut: @escaping (UInt32, UInt32) throws -> Void) {
        self.updateShortcut = updateShortcut
        recorder = ShortcutRecorder(keyCode: SettingsManager.keyCode, modifiers: SettingsManager.modifiers)
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 390),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Scapare 设置"
        window.isReleasedWhenClosed = false
        super.init()
        window.delegate = self
        let title = NSTextField(labelWithString: "截图快捷键")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let hint = NSTextField(wrappingLabelWithString: "点击后按下组合键或 F1–F12，Esc 取消。部分键盘需要同时按 Fn。")
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 12)
        shortcutStatus.textColor = .systemRed
        shortcutStatus.font = .systemFont(ofSize: 12)
        loginStatus.textColor = .secondaryLabelColor
        loginStatus.font = .systemFont(ofSize: 12)
        // SwiftUI owns NSApp.delegate; the live AppDelegate supplies its update action.
        recorder.onShortcutChanged = updateShortcut
        recorder.onError = { [weak self] message in self?.shortcutStatus.stringValue = message }
        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLogin)
        loginSettingsButton.target = self
        loginSettingsButton.action = #selector(openLoginSettings)
        let done = NSButton(title: "完成", target: self, action: #selector(dismissTapped))
        done.bezelStyle = .rounded
        done.keyEquivalent = "\r"
        let guide = NSButton(title: "功能引导", target: self, action: #selector(showFeatureGuide))
        guide.bezelStyle = .rounded
        let stack = NSStackView(views: [title, hint, recorder, shortcutStatus, loginCheckbox, loginStatus, loginSettingsButton, guide, done])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(stack)
        window.contentView = content
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -20),
            recorder.widthAnchor.constraint(equalToConstant: 200),
            recorder.heightAnchor.constraint(equalToConstant: 44),
            hint.widthAnchor.constraint(equalTo: stack.widthAnchor),
            shortcutStatus.widthAnchor.constraint(equalTo: stack.widthAnchor),
            loginStatus.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        refreshLoginStatus()
    }
    private func refreshLoginStatus() {
        let status = SMAppService.mainApp.status
        loginCheckbox.state = status == .enabled ? .on : .off
        loginSettingsButton.isHidden = status != .requiresApproval
        switch status {
        case .enabled: loginStatus.stringValue = "已启用登录启动。"
        case .requiresApproval: loginStatus.stringValue = "需要在系统设置的「登录项」中允许 Scapare。"
        case .notFound: loginStatus.stringValue = "请先将 Scapare 安装到「应用程序」后再启用。"
        default: loginStatus.stringValue = "未启用登录启动。"
        }
    }
    func windowDidBecomeKey(_ notification: Notification) { refreshLoginStatus() }
    @objc private func toggleLogin() {
        do {
            if loginCheckbox.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLoginStatus()
        } catch {
            refreshLoginStatus()
            loginStatus.stringValue = "设置未生效：\(error.localizedDescription)"
        }
    }
    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    @objc private func showFeatureGuide() {
        FeatureGuideController.show { [updateShortcut] in Self.showSettings(updateShortcut: updateShortcut) }
    }
    @objc private func dismissTapped() { window.close() }
    func windowWillClose(_ notification: Notification) {
        if Self.current === self { Self.current = nil }
    }
}
