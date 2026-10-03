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
    private var localKeys: Any?
    private var gestureMonitor: GestureMonitor?
    private var statusMenu: NSMenu?
    private var workspaceObserver: NSObjectProtocol?
    private var appearanceObserver: NSObjectProtocol?
    private var hotCornerMonitor: HotCornerMonitor?
    private let hotKey = ShortcutBinding<GlobalHotKey>()
    private var statusItem: NSStatusItem?
    private var shotMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        SettingsManager.initializeDefaults()
        AppearanceSettings.migrateBrandIcon()

        AppearanceSettings.applyTheme()
        setupStatusItem()
        registerHotKey()
        PinManager.shared.restore()
        AdditionalShortcuts.shared.restore()
        hotCornerMonitor = HotCornerMonitor(); gestureMonitor = GestureMonitor()
        AutomationController.shared.restore()
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { _ in MainActor.assumeIsolated { ShortcutPolicy.refresh() } }
        appearanceObserver = NotificationCenter.default.addObserver(forName: AppearanceSettings.changed, object: nil, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.refreshAppearance() } }
        ShortcutPolicy.refresh()
        localKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            var consumed = false
            MainActor.assumeIsolated { if let self { consumed = self.handleLocalShortcut(event) == nil } }
            return consumed ? nil : event
        }

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
            button.image = BrandIcon.menuBarImage()
            button.toolTip = "Scapare"
            button.setAccessibilityLabel("Scapare 菜单")
        }

        let menu = NSMenu()

        let shot = NSMenuItem(title: "截图",
                              action: #selector(startCaptureAction),
                              keyEquivalent: "")
        shot.target = self
        menu.addItem(shot)
        shotMenuItem = shot

        func add(_ title: String, _ action: Selector, to destination: NSMenu? = nil) {
            let item = (destination ?? menu).addItem(withTitle: title, action: action, keyEquivalent: ""); item.target = self
        }
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: ""), sub = NSMenu(); item.submenu = sub; menu.addItem(item); return sub
        }
        add("滚动长截图…", #selector(longCaptureAction))
        let capture = submenu("更多截图")
        add("当前屏幕", #selector(fullScreenAction), to: capture)
        add("所有屏幕合成…", #selector(allScreensAction), to: capture)
        add("活动窗口", #selector(windowCaptureAction), to: capture)
        add("重复上次选区", #selector(repeatCaptureAction), to: capture)
        add("延时 5 秒", #selector(delayedCaptureAction), to: capture)
        add("取消延时", #selector(cancelDelayedCapture), to: capture)
        menu.addItem(.separator())
        add("贴出剪贴板", #selector(pasteAction))
        add("贴图库与分组…", #selector(pinLibraryAction))
        let pins = submenu("贴图操作")
        add("从文件贴图…", #selector(importImageAction), to: pins)
        add("从剪贴板网址导入图片…", #selector(importURLAction), to: pins)
        add("显示所有贴图", #selector(showPinsAction), to: pins)
        add("隐藏所有贴图", #selector(hidePinsAction), to: pins)
        add("恢复贴图鼠标交互", #selector(restoreMouseAction), to: pins)
        add("打开图片编辑…", #selector(editImageAction))
        let board = submenu("白板")
        add("白色背景", #selector(whiteboardAction), to: board)
        add("透明背景", #selector(transparentWhiteboardAction), to: board)
        menu.addItem(.separator())
        add("更多设置…", #selector(extraSettingsAction))

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

        statusMenu = menu; statusItem = item
        item.button?.target = self; item.button?.action = #selector(statusClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        refreshAppearance()

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

    func applicationDidBecomeActive(_ notification: Notification) { ShortcutPolicy.refresh() }
    func applicationDidResignActive(_ notification: Notification) {
        ShortcutPolicy.refresh()
        statusItem?.button?.toolTip = GlobalHotKey.lastResumeError.map { "Scapare：" + $0 } ?? "Scapare"
    }
    func applicationWillTerminate(_ notification: Notification) { if let localKeys { NSEvent.removeMonitor(localKeys) }; PinManager.shared.saveNow(); AutomationController.shared.stop(); gestureMonitor?.stop(); hotCornerMonitor?.stop() }
    private func handleLocalShortcut(_ event: NSEvent) -> NSEvent? {
        let responder = NSApp.keyWindow?.firstResponder
        guard !(responder is NSTextView), !(responder is ShortcutRecorder), !(responder is EditorView), NSApp.modalWindow == nil else { return event }
        // Standard in-app edit and document commands keep their native meaning.
        if event.modifierFlags.contains(.command), [0, 1, 6, 7, 8, 9, 12, 13].contains(Int(event.keyCode)) { return event }
        var modifiers: UInt32 = 0
        if event.modifierFlags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if event.modifierFlags.contains(.option) { modifiers |= UInt32(optionKey) }
        if event.modifierFlags.contains(.control) { modifiers |= UInt32(controlKey) }
        if event.modifierFlags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let key = CaptureShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers)
        if key == CaptureShortcut(keyCode: SettingsManager.keyCode, modifiers: SettingsManager.modifiers) { CaptureController.shared.startCapture(); return nil }
        if let action = ShortcutAction.allCases.first(where: { AdditionalShortcuts.shared.saved($0) == key }) { action.run(); return nil }
        return event
    }
    private func refreshAppearance() {
        let symbol = AppearanceSettings.options.statusSymbol
        let image = symbol == "longjuan" ? BrandIcon.menuBarImage()
            : NSImage(systemSymbolName: symbol, accessibilityDescription: "Scapare")
        image?.isTemplate = true
        statusItem?.button?.image = image ?? BrandIcon.menuBarImage()
        statusItem?.button?.toolTip = "Scapare · 右键打开菜单"
    }
    @objc private func statusClicked() {
        guard let item = statusItem else { return }
        let click = AppearanceSettings.options.statusClick
        if NSApp.currentEvent?.type == .rightMouseUp || click == 0 {
            item.menu = statusMenu; item.button?.performClick(nil); item.menu = nil
        } else if click == 1 { CaptureController.shared.startCapture() }
        else { PinManager.shared.pasteClipboard() }
    }
    @objc private func allScreensAction() {
        Task { do { ImageWorkspace.open(try await ScreenshotEngine.captureDesktop(), title: "所有屏幕 · Scapare") }
        catch { PermissionHelper.showCaptureError(error) {} } }
    }
    @objc private func longCaptureAction() { CaptureController.shared.startCapture(mode: .long) }
    @objc private func fullScreenAction() { CaptureController.shared.startCapture(mode: .fullScreen) }
    @objc private func windowCaptureAction() { CaptureController.shared.startCapture(mode: .activeWindow) }
    @objc private func repeatCaptureAction() { CaptureController.shared.startCapture(mode: .repeatRegion) }
    @objc private func delayedCaptureAction() { CaptureController.shared.delayedCapture(seconds: 5) }
    @objc private func cancelDelayedCapture() { CaptureController.shared.cancelDelay() }
    @objc private func pasteAction() { PinManager.shared.pasteClipboard() }
    @objc private func importURLAction() { WebImageImporter.pasteURL() }
    @objc private func importImageAction() { ImageInputs.openFiles(asPins: true) }
    @objc private func editImageAction() { ImageInputs.openFiles(asPins: false) }
    @objc private func pinLibraryAction() { PinLibrary.show() }
    @objc private func showPinsAction() { PinManager.shared.showAll() }
    @objc private func hidePinsAction() { PinManager.shared.hideAll() }
    @objc private func restoreMouseAction() { PinManager.shared.restoreMouseInteraction() }
    @objc private func whiteboardAction() { ImageInputs.whiteboard(transparent: false) }
    @objc private func transparentWhiteboardAction() { ImageInputs.whiteboard(transparent: true) }
    @objc private func extraSettingsAction() { ExtraSettings.show() }
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
