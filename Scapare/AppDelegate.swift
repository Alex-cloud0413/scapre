//
//  AppDelegate.swift
//  Scapare
//
//  App 启动后：
//  1. 设为菜单栏小工具（不在程序坞显示）。
//  2. 从 UserDefaults 读取用户快捷键（首次弹引导窗）。
//  3. 注册全局快捷键，随时可改。
//

import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotKey = ShortcutBinding<GlobalHotKey>()
    private var statusItem: NSStatusItem?
    private var shotMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        SettingsManager.initializeDefaults()

        setupStatusItem()
        registerHotKey()

        // 首次启动：弹引导窗让用户选择快捷键
        if !SettingsManager.setupCompleted {
            DispatchQueue.main.async { [weak self] in
                SetupWindowController.showSetup {
                    self?.refreshMenuShortcut()
                }
            }
        }
    }

    // MARK: - 全局热键

    private func registerHotKey() {
        do {
            try updateShortcut(keyCode: SettingsManager.keyCode, modifiers: SettingsManager.modifiers)
        } catch {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "截图快捷键不可用"
                alert.informativeText = "可以通过菜单栏截图，或在设置中选择其他快捷键。\n\(error.localizedDescription)"
                alert.addButton(withTitle: "打开设置")
                alert.addButton(withTitle: "稍后")
                if alert.runModal() == .alertFirstButtonReturn { SetupWindowController.showSettings() }
            }
        }
    }

    func updateShortcut(keyCode: UInt32, modifiers: UInt32) throws {
        let candidate = CaptureShortcut(keyCode: keyCode, modifiers: modifiers)
        try hotKey.replace(with: candidate, register: { shortcut in
            try GlobalHotKey(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers) {
                // A configured global shortcut must not interrupt in-app text entry/recording.
                if NSApp.isActive && (NSApp.keyWindow?.firstResponder is NSTextView
                    || NSApp.keyWindow?.firstResponder is ShortcutRecorder) { return }
                CaptureController.shared.startCapture()
            }
        }, persist: { shortcut in
            SettingsManager.save(keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)
        })
        refreshMenuShortcut()
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Scapare")
            image?.isTemplate = true
            button.image = image
        }

        let menu = NSMenu()

        let shot = NSMenuItem(title: "截图",
                              action: #selector(startCaptureAction),
                              keyEquivalent: "")
        shot.target = self
        menu.addItem(shot)
        shotMenuItem = shot

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "设置…",
                                  action: #selector(openSettingsAction),
                                  keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        menu.addItem(settings)

        let about = NSMenuItem(title: "关于 Scapare",
                               action: #selector(showAboutAction),
                               keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "退出 Scapare",
                              action: #selector(quitAction),
                              keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
        statusItem = item

        refreshMenuShortcut()
    }

    /// 让「截图」菜单项显示当前快捷键（如 "截图    ⌘S"）
    private func refreshMenuShortcut() {
        let shortcut = SettingsManager.currentShortcutString
        let display = "截图    \(shortcut)"
        // 菜单栏的 keyEquivalent 和 modifierMask 设空——我们不通过
        // NSMenu 来拦截全局按键，而只用于显示文字。
        shotMenuItem?.keyEquivalent = ""
        shotMenuItem?.keyEquivalentModifierMask = []
        shotMenuItem?.title = display
    }

    // MARK: - 动作

    @objc private func startCaptureAction() {
        CaptureController.shared.startCapture()
    }

    @objc private func openSettingsAction() {
        SetupWindowController.showSettings()
    }

    @objc private func showAboutAction() {
        showAbout()
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - 关于窗口

    func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        let shortcut = SettingsManager.currentShortcutString
        let alert = NSAlert()
        alert.messageText = "Scapare"
        alert.informativeText = """
        一款 Mac 截图小工具。

        • 按 \(shortcut) 开始截图
        • 拖动鼠标框选区域
        • 可标注、贴图、文字识别(OCR)、复制、保存

        版本 \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
        """
        alert.addButton(withTitle: "好的")
        alert.runModal()
    }
}
