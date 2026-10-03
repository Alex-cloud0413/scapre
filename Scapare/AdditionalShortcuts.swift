import AppKit

enum ShortcutAction: String, CaseIterable {
    case paste, togglePins, longCapture, fullScreen, repeatRegion, whiteboard, library, activeWindow, allScreens, delay, cancelDelay, showPins, hidePins, restoreMouse, transparentBoard, clipboardOCR, clipboardBarcode, editFile
    var title: String {
        switch self {
        case .paste: return "贴出剪贴板"; case .togglePins: return "显示 / 隐藏贴图"; case .longCapture: return "长截图"
        case .activeWindow: return "活动窗口"; case .allScreens: return "所有屏幕"; case .delay: return "延时 5 秒"; case .cancelDelay: return "取消延时"
        case .showPins: return "显示贴图"; case .hidePins: return "隐藏贴图"; case .restoreMouse: return "恢复鼠标交互"; case .transparentBoard: return "透明白板"
        case .clipboardOCR: return "识别剪贴板文字"; case .clipboardBarcode: return "识别剪贴板条码"; case .editFile: return "编辑图片文件"
        case .fullScreen: return "全屏截图"; case .repeatRegion: return "重复选区"; case .whiteboard: return "白板"; case .library: return "贴图库"
        }
    }
    func run() {
        switch self {
        case .paste: PinManager.shared.pasteClipboard()
        case .togglePins:
            if PinManager.shared.controllers.contains(where: { !$0.record.hidden }) { PinManager.shared.hideAll() } else { PinManager.shared.showAll() }
        case .longCapture: CaptureController.shared.startCapture(mode: .long)
        case .fullScreen: CaptureController.shared.startCapture(mode: .fullScreen)
        case .repeatRegion: CaptureController.shared.startCapture(mode: .repeatRegion)
        case .whiteboard: ImageInputs.whiteboard(transparent: false)
        case .library: PinLibrary.show()
        case .activeWindow: CaptureController.shared.startCapture(mode: .activeWindow)
        case .allScreens: Task { do { ImageWorkspace.open(try await ScreenshotEngine.captureDesktop()) } catch { AppDialogs.error(error.localizedDescription) } }
        case .delay: CaptureController.shared.delayedCapture(seconds: 5)
        case .cancelDelay: CaptureController.shared.cancelDelay()
        case .showPins: PinManager.shared.showAll()
        case .hidePins: PinManager.shared.hideAll()
        case .restoreMouse: PinManager.shared.restoreMouseInteraction()
        case .transparentBoard: ImageInputs.whiteboard(transparent: true)
        case .clipboardOCR, .clipboardBarcode:
            do { OCRResultController.present(image: try ImageInputs.clipboard(), barcode: self == .clipboardBarcode) } catch { AppDialogs.error(error.localizedDescription) }
        case .editFile: ImageInputs.openFiles(asPins: false)
        }
    }
}
final class AdditionalShortcuts {
    static let shared = AdditionalShortcuts()
    private var bindings: [ShortcutAction: ShortcutBinding<GlobalHotKey>] = [:]
    private(set) var errors: [String] = []
    func saved(_ action: ShortcutAction) -> CaptureShortcut? {
        guard let value = UserDefaults.standard.array(forKey: "action_shortcut_" + action.rawValue) as? [Int], value.count == 2,
              value.allSatisfy({ $0 >= 0 && $0 <= Int(UInt32.max) }) else { return nil }
        return CaptureShortcut(keyCode: UInt32(value[0]), modifiers: UInt32(value[1]))
    }
    func set(_ action: ShortcutAction, shortcut: CaptureShortcut?) throws {
        guard let shortcut else { bindings[action] = nil; UserDefaults.standard.removeObject(forKey: "action_shortcut_" + action.rawValue); return }
        let binding = bindings[action] ?? ShortcutBinding<GlobalHotKey>()
        try binding.replace(with: shortcut, register: { key in
            try GlobalHotKey(keyCode: key.keyCode, modifiers: key.modifiers) { action.run() }
        }, persist: { key in UserDefaults.standard.set([Int(key.keyCode), Int(key.modifiers)], forKey: "action_shortcut_" + action.rawValue) })
        bindings[action] = binding
    }
    func restore() {
        errors.removeAll()
        for action in ShortcutAction.allCases {
            if let shortcut = saved(action) { do { try set(action, shortcut: shortcut) } catch { errors.append(action.title + "：" + error.localizedDescription) } }
        }
    }
}
final class AdditionalShortcutWindow: NSObject, NSWindowDelegate {
    private static var current: AdditionalShortcutWindow?
    private let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 480, height: 540), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    private let status = NSTextField(wrappingLabelWithString: "")
    static func show() {
        if let current { current.window.makeKeyAndOrderFront(nil); return }
        let instance = AdditionalShortcutWindow(); current = instance; instance.window.center(); instance.window.makeKeyAndOrderFront(nil)
    }
    private override init() {
        super.init(); window.title = "全局快捷键 · Scapare"; window.isReleasedWhenClosed = false; window.delegate = self
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = true
        let hint = NSTextField(wrappingLabelWithString: "按需设置。在 Scapare 内编辑或录制快捷键时，全局键暂停，避免抢占文字编辑命令。")
        hint.font = .systemFont(ofSize: 12); hint.textColor = .secondaryLabelColor; stack.addArrangedSubview(hint)
        for (index, action) in ShortcutAction.allCases.enumerated() {
            let key = AdditionalShortcuts.shared.saved(action)
            let recorder = ShortcutRecorder(keyCode: key?.keyCode ?? .max, modifiers: key?.modifiers ?? 0)
            recorder.onShortcutChanged = { try AdditionalShortcuts.shared.set(action, shortcut: CaptureShortcut(keyCode: $0, modifiers: $1)) }
            recorder.onError = { [weak self] text in self?.status.stringValue = text }
            let label = NSTextField(labelWithString: action.title); label.widthAnchor.constraint(equalToConstant: 120).isActive = true
            let clear = NSButton(title: "清除", target: self, action: #selector(clearShortcut(_:))); clear.tag = index
            stack.addArrangedSubview(NSStackView(views: [label, recorder, clear]))
        }
        status.textColor = .systemRed; status.stringValue = AdditionalShortcuts.shared.errors.joined(separator: "\n")
        stack.addArrangedSubview(status)
        hint.widthAnchor.constraint(equalToConstant: 430).isActive = true; status.widthAnchor.constraint(equalToConstant: 430).isActive = true
        stack.layoutSubtreeIfNeeded(); stack.frame = CGRect(origin: CGPoint(x: 20, y: 20), size: stack.fittingSize)
        let document = NSView(frame: CGRect(x: 0, y: 0, width: 460, height: stack.frame.height + 40)); document.addSubview(stack)
        let scroll = NSScrollView(frame: window.contentView!.bounds); scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true; scroll.documentView = document; window.contentView?.addSubview(scroll)
        window.minSize = CGSize(width: 480, height: 360)
        scroll.contentView.scroll(to: CGPoint(x: 0, y: max(0, document.frame.height - scroll.contentSize.height)))
    }
    @objc private func clearShortcut(_ sender: NSButton) {
        try? AdditionalShortcuts.shared.set(ShortcutAction.allCases[sender.tag], shortcut: nil)
        window.close(); Self.show()
    }
    func windowWillClose(_ notification: Notification) { Self.current = nil }
}
