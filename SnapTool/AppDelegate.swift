//
//  AppDelegate.swift
//  SnapTool
//
//  App 启动后：
//  1. 设为菜单栏小工具（不在程序坞显示）。
//  2. 从 UserDefaults 读取用户快捷键（首次弹引导窗）。
//  3. 注册全局快捷键，随时可改。
//

import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: GlobalHotKey?
    private var statusItem: NSStatusItem?
    private var shotMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        SettingsManager.initializeDefaults()

        setupStatusItem()
        registerHotKey()

        // 首次启动：弹引导窗让用户选择快捷键
        if !SettingsManager.hasSetShortcut {
            DispatchQueue.main.async { [weak self] in
                SetupWindowController.showSetup {
                    self?.refreshMenuShortcut()
                }
            }
        }
    }

    // MARK: - 全局热键

    private func registerHotKey() {
        // 销毁旧的
        hotKey = nil
        hotKey = GlobalHotKey(keyCode: SettingsManager.keyCode,
                              modifiers: SettingsManager.modifiers) {
            CaptureController.shared.startCapture()
        }
    }

    /// 当用户在设置面板里改了快捷键后调用
    func reloadHotKey() {
        registerHotKey()
        refreshMenuShortcut()
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Scapre")
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

        let about = NSMenuItem(title: "关于 Scapre",
                               action: #selector(showAboutAction),
                               keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        let quit = NSMenuItem(title: "退出 Scapre",
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
        alert.messageText = "Scapre"
        alert.informativeText = """
        一款 Mac 截图小工具。

        • 按 \(shortcut) 开始截图
        • 拖动鼠标框选区域
        • 可标注、贴图、文字识别(OCR)、复制、保存

        版本 1.0
        """
        alert.addButton(withTitle: "好的")
        alert.runModal()
    }
}
