//
//  SetupWindow.swift
//  SnapTool
//
//  首次启动的引导窗 + 后续从菜单打开的设置窗口。
//  两者复用同一个视图内容。
//

import AppKit
import ServiceManagement

@MainActor
final class SetupWindowController: NSObject, NSWindowDelegate {
    nonisolated(unsafe) private static var alive: [SetupWindowController] = []

    private let window: NSWindow
    private let recorder: ShortcutRecorder
    private let isFirstRun: Bool
    private var launchAtLoginCheckbox: NSButton?
    var onDismiss: (() -> Void)?

    // 首次运行引导窗
    static func showSetup(completion: @escaping () -> Void) {
        let controller = SetupWindowController(isFirstRun: true)
        controller.onDismiss = completion
        alive.append(controller)
        NSApp.activate(ignoringOtherApps: true)
        controller.window.center()
        controller.window.makeKeyAndOrderFront(nil)
    }

    // 菜单 → 设置
    static func showSettings() {
        let controller = SetupWindowController(isFirstRun: false)
        alive.append(controller)
        NSApp.activate(ignoringOtherApps: true)
        controller.window.center()
        controller.window.makeKeyAndOrderFront(nil)
    }

    private init(isFirstRun: Bool) {
        self.isFirstRun = isFirstRun

        let kc = SettingsManager.keyCode
        let md = SettingsManager.modifiers
        recorder = ShortcutRecorder(keyCode: kc, modifiers: md)

        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 380, height: isFirstRun ? 290 : 240),
                          styleMask: [.titled, .closable],
                          backing: .buffered,
                          defer: false)
        window.title = isFirstRun ? "欢迎使用 Scapre" : "Scapre 设置"
        window.isReleasedWhenClosed = false

        super.init()
        window.delegate = self

        let content = NSView()

        let titleLabel = NSTextField(labelWithString: isFirstRun
            ? "请设置你的截图快捷键"
            : "更改截图快捷键")
        titleLabel.font = NSFont.systemFont(ofSize: 15, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let hint = NSTextField(labelWithString: isFirstRun
            ? "点击下方区域，然后按下组合键（如 ⌘E、⌘⇧A、F1）"
            : "点击后按新组合键即生效（如 ⌘E、⌘⇧A、F1）")
        hint.font = NSFont.systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        hint.translatesAutoresizingMaskIntoConstraints = false

        recorder.translatesAutoresizingMaskIntoConstraints = false
        recorder.onShortcutChanged = { [weak self] kc, mods in
            self?.saveShortcut(keyCode: kc, modifiers: mods)
        }

        // 开机自启动复选框（仅首次引导时显示）
        var bottomView: NSView
        if isFirstRun {
            let cb = NSButton(checkboxWithTitle: "开机时自动启动 Scapre", target: self, action: #selector(launchAtLoginToggled(_:)))
            cb.state = .on  // 默认勾选
            cb.font = NSFont.systemFont(ofSize: 13)
            cb.translatesAutoresizingMaskIntoConstraints = false
            launchAtLoginCheckbox = cb
            content.addSubview(cb)
            bottomView = cb
        } else {
            // 占位：用一个不可见的视图保持约束一致
            let spacer = NSView()
            spacer.translatesAutoresizingMaskIntoConstraints = false
            bottomView = spacer
        }

        let button = NSButton(title: isFirstRun ? "开始使用" : "完成",
                              target: nil, action: nil)
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.target = self
        button.action = #selector(dismissTapped)

        let buttonStack = NSStackView(views: [button])
        buttonStack.alignment = .centerX
        buttonStack.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(titleLabel)
        content.addSubview(hint)
        content.addSubview(recorder)
        if !isFirstRun { content.addSubview(bottomView) }
        content.addSubview(buttonStack)
        window.contentView = content

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: content.topAnchor, constant: 30),
            titleLabel.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            hint.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            hint.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            recorder.topAnchor.constraint(equalTo: hint.bottomAnchor, constant: 20),
            recorder.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            recorder.widthAnchor.constraint(equalToConstant: 180),
            recorder.heightAnchor.constraint(equalToConstant: 44),

            bottomView.topAnchor.constraint(equalTo: recorder.bottomAnchor, constant: 16),
            bottomView.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            buttonStack.topAnchor.constraint(equalTo: bottomView.bottomAnchor, constant: 16),
            buttonStack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
        ])
    }

    private func saveShortcut(keyCode: UInt32, modifiers: UInt32) {
        SettingsManager.save(keyCode: keyCode, modifiers: modifiers)
        // 通知 AppDelegate 重新注册全局热键
        (NSApp.delegate as? AppDelegate)?.reloadHotKey()
    }

    @objc private func launchAtLoginToggled(_ sender: NSButton) {
        do {
            if sender.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // 权限不足时静默失败
            print("SnapTool: SMAppService failed: \(error)")
        }
    }

    @objc private func dismissTapped() {
        // 首次运行没设置过时，存默认值
        if isFirstRun && !SettingsManager.hasSetShortcut {
            SettingsManager.hasSetShortcut = true

            // 应用开机自启动设置
            do {
                if launchAtLoginCheckbox?.state == .on {
                    try SMAppService.mainApp.register()
                }
            } catch {
                print("SnapTool: SMAppService register failed: \(error)")
            }
        }
        window.close()
        onDismiss?()
    }

    func windowWillClose(_ notification: Notification) {
        dismissTapped()
        Self.alive.removeAll { $0 === self }
    }
}
