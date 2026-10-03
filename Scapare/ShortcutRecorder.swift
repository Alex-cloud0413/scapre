import AppKit

@MainActor
final class ShortcutRecorder: NSView {
    private let label = NSTextField(labelWithString: "")
    private(set) var isRecording = false
    private var current: CaptureShortcut
    var onShortcutChanged: ((UInt32, UInt32) throws -> Void)?
    var onError: ((String) -> Void)?

    init(keyCode: UInt32, modifiers: UInt32) {
        current = CaptureShortcut(keyCode: keyCode, modifiers: modifiers)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 2
        label.font = .monospacedSystemFont(ofSize: 20, weight: .medium)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("截图快捷键")
        setAccessibilityHelp("按空格或回车开始录制，按 Esc 取消。")
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 200, height: 44) }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); refresh() }
    override func becomeFirstResponder() -> Bool { refresh(); return true }
    override func resignFirstResponder() -> Bool { isRecording = false; refresh(); return true }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill() }

    private func refresh() {
        let text = SettingsManager.shortcutDisplayString(keyCode: current.keyCode, modifiers: current.modifiers)
        label.stringValue = isRecording ? "按下快捷键…" : text
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        setAccessibilityValue(isRecording ? "正在录制，Esc 取消" : text)
    }
    private func startRecording() {
        window?.makeFirstResponder(self)
        isRecording = true
        onError?("")
        refresh()
    }
    private func stopRecording() { isRecording = false; refresh() }
    override func mouseDown(with event: NSEvent) {
        if isRecording { stopRecording() } else { startRecording() }
    }
    override func accessibilityPerformPress() -> Bool { startRecording(); return true }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording else { return super.performKeyEquivalent(with: event) }
        accept(event)
        return true
    }
    override func keyDown(with event: NSEvent) {
        if isRecording { accept(event); return }
        if [36, 49, 76].contains(event.keyCode) { startRecording() }
        else { super.keyDown(with: event) }
    }
    private func accept(_ event: NSEvent) {
        if event.keyCode == 53 { stopRecording(); onError?(""); return }
        let (key, modifiers) = SettingsManager.extract(from: event)
        let candidate = CaptureShortcut(keyCode: key, modifiers: modifiers)
        guard candidate.isValid else {
            onError?("请使用组合键或 F1–F12；按 Esc 取消。")
            return
        }
        do {
            try onShortcutChanged?(key, modifiers)
            current = candidate
            onError?("")
        } catch { onError?(error.localizedDescription) }
        stopRecording()
    }
}
