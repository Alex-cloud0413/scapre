import AppKit

/// Polls modifier state only. No key logging, event suppression or accessibility entitlement.
/// Holding the chord opens Scapare's capture surface; dragging then stays inside the App.
final class GestureMonitor {
    private var timer: Timer?
    private var began: Date?
    private var triggered = false
    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.poll() } }
    }
    private func poll() {
        let flags = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift])
        let wanted: NSEvent.ModifierFlags = UserDefaults.standard.integer(forKey: "gesture_chord") == 1 ? [.option, .shift] : [.control, .option]
        let held = UserDefaults.standard.bool(forKey: "gesture_enabled") && flags == wanted
        if !held { began = nil; triggered = false; return }
        guard !triggered, !NSApp.isActive, !ShortcutPolicy.isIgnored, NSEvent.pressedMouseButtons == 0 else { return }
        if began == nil { began = Date() }
        if Date().timeIntervalSince(began!) >= 0.3 { triggered = true; CaptureController.shared.startCapture() }
    }
    func stop() { timer?.invalidate(); timer = nil }
}

enum ShortcutPolicy {
    static var ignoredApps: [String] {
        get { UserDefaults.standard.stringArray(forKey: "shortcut_ignored_apps") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "shortcut_ignored_apps"); refresh() }
    }
    static var isIgnored: Bool { NSWorkspace.shared.frontmostApplication?.bundleIdentifier.map { ignoredApps.contains($0) } ?? false }
    static func refresh() {
        if NSApp.isActive || isIgnored { GlobalHotKey.pauseAll() } else { GlobalHotKey.resumeAll() }
    }
}

final class AdvancedSettings: NSObject, NSWindowDelegate {
    private static var current: AdvancedSettings?
    private let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 520, height: 470), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    private let automation = NSButton(checkboxWithTitle: "启用本机命令行与批处理", target: nil, action: nil)
    private let gestures = NSButton(checkboxWithTitle: "按住修饰键 0.3 秒，进入拖拽截图", target: nil, action: nil)
    private let chord = NSPopUpButton()
    private let status = NSTextField(wrappingLabelWithString: "")
    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let current { current.window.makeKeyAndOrderFront(nil); return }
        let instance = AdvancedSettings(); current = instance; instance.window.center(); instance.window.makeKeyAndOrderFront(nil)
    }
    private override init() {
        super.init(); window.title = "高级功能 · Scapare"; window.delegate = self; window.isReleasedWhenClosed = false
        automation.state = AutomationController.shared.enabled ? .on : .off; automation.target = self; automation.action = #selector(toggleAutomation)
        gestures.state = UserDefaults.standard.bool(forKey: "gesture_enabled") ? .on : .off; gestures.target = self; gestures.action = #selector(toggleGestures)
        chord.addItems(withTitles: ["Control + Option", "Option + Shift"]); chord.selectItem(at: min(1, UserDefaults.standard.integer(forKey: "gesture_chord"))); chord.target = self; chord.action = #selector(changeChord)
        let explanation = NSTextField(wrappingLabelWithString: "按住所选修饰键，等画面冻结后拖动框选，Esc 取消。此方式不需要辅助功能权限。命令行仅接受当前用户的本机连接；可读取截图和剪贴板、处理图片及管理贴图。")
        explanation.font = .systemFont(ofSize: 12); explanation.textColor = .secondaryLabelColor; explanation.widthAnchor.constraint(equalToConstant: 470).isActive = true
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor; status.widthAnchor.constraint(equalToConstant: 470).isActive = true
        let stack = NSStackView(views: [gestures, chord, automation, explanation, NSButton(title: "复制命令行连接路径", target: self, action: #selector(copyPath)), NSButton(title: "配置四个屏幕触发角…", target: self, action: #selector(configureCorners)), NSButton(title: "快捷键和手势忽略的 App…", target: self, action: #selector(ignoreApps)), status]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack); NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)])
        refreshStatus()
    }
    private func refreshStatus() { status.stringValue = AutomationController.shared.error ?? (AutomationController.shared.enabled ? "命令行已启用。可使用源码附带的 scapare 工具运行 --help 查看用法。" : "命令行已关闭。") }
    @objc private func toggleAutomation() {
        do { try AutomationController.shared.setEnabled(automation.state == .on); refreshStatus() }
        catch { automation.state = .off; status.stringValue = error.localizedDescription }
    }
    @objc private func toggleGestures() { UserDefaults.standard.set(gestures.state == .on, forKey: "gesture_enabled") }
    @objc private func changeChord() { UserDefaults.standard.set(chord.indexOfSelectedItem, forKey: "gesture_chord") }
    @objc private func copyPath() { Clipboard.copy(text: AutomationController.shared.socketPath); status.stringValue = "连接路径已复制；用于 scapare --socket 参数。" }
    @objc private func configureCorners() {
        let alert = NSAlert(); alert.messageText = "屏幕触发角（停留 0.8 秒）"
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        let values = UserDefaults.standard.array(forKey: "hot_corner_actions") as? [Int] ?? [0, 1, 0, 0]
        var menus: [NSPopUpButton] = []
        for (index, title) in ["左上角", "右上角", "左下角", "右下角"].enumerated() {
            let menu = NSPopUpButton(); menu.addItems(withTitles: ["不执行操作", "截图", "贴出剪贴板", "切换贴图显示", "显示所有贴图", "隐藏所有贴图"])
            menu.selectItem(at: values.indices.contains(index) ? max(0, min(5, values[index])) : 0); menu.setAccessibilityLabel(title)
            stack.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: title), menu])); menus.append(menu)
        }
        stack.layoutSubtreeIfNeeded(); stack.setFrameSize(stack.fittingSize); alert.accessoryView = stack; alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn { UserDefaults.standard.set(menus.map(\.indexOfSelectedItem), forKey: "hot_corner_actions") }
    }
    @objc private func ignoreApps() {
        let names = ShortcutPolicy.ignoredApps.joined(separator: ", ")
        guard let values = AppDialogs.fields(title: "忽略这些 App 的全局快捷键与截图手势", labels: ["Bundle ID（逗号分隔）"], values: [names]) else { return }
        let ids = values[0].split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard ids.count <= 100, ids.allSatisfy({ $0.count <= 200 && $0.contains(".") && !$0.contains(" ") }) else { status.stringValue = "请输入 App 的 Bundle ID，例如 com.apple.Safari。"; return }
        ShortcutPolicy.ignoredApps = ids; status.stringValue = "已保存 \(ids.count) 个忽略项；切换到这些 App 时会释放全局快捷键。"
    }
    func windowWillClose(_ notification: Notification) { Self.current = nil }
}
