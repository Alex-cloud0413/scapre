//
//  ShortcutRecorder.swift
//  Scapare
//
//  一个快捷键「录制」控件。点击后进入录制模式，等待用户按下一个组合键，
//  然后显示该快捷键（如 ⌘S），并通过回调通知外部。
//

import AppKit

@MainActor
final class ShortcutRecorder: NSView {
    private let label: NSTextField
    private var isRecording = false
    private var currentKeyCode: UInt32
    private var currentModifiers: UInt32
    var onShortcutChanged: ((UInt32, UInt32) -> Void)?

    init(keyCode: UInt32, modifiers: UInt32) {
        currentKeyCode = keyCode
        currentModifiers = modifiers
        label = NSTextField(labelWithString: "")
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 2
        label.font = NSFont.monospacedSystemFont(ofSize: 20, weight: .medium)
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        updateDisplay()
        refreshAppearance()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    var displayString: String {
        SettingsManager.shortcutDisplayString(keyCode: currentKeyCode, modifiers: currentModifiers)
    }

    private func updateDisplay() {
        label.stringValue = isRecording ? "按下快捷键…" : displayString
    }

    private func refreshAppearance() {
        if isRecording {
            layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.15).cgColor
            layer?.borderColor = NSColor.systemBlue.cgColor
        } else {
            layer?.backgroundColor = NSColor(white: 1, alpha: 0.08).cgColor
            layer?.borderColor = NSColor(white: 1, alpha: 0.3).cgColor
        }
    }

    override func mouseDown(with event: NSEvent) {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        refreshAppearance()
        updateDisplay()
        window?.makeFirstResponder(self)
    }

    private func stopRecording() {
        isRecording = false
        refreshAppearance()
        updateDisplay()
        window?.makeFirstResponder(nil)
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }

        // 忽略单独按修饰键（必须有非修饰键）
        let modifierOnlyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        if modifierOnlyCodes.contains(event.keyCode) { return }

        let (kc, mods) = SettingsManager.extract(from: event)

        // 要求至少有一个修饰键（或功能键 F1-F12 可单独使用）
        if mods == 0 && !(kc >= 122 && kc <= 111) { return }

        currentKeyCode = kc
        currentModifiers = mods
        stopRecording()
        onShortcutChanged?(kc, mods)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 180, height: 44)
    }
}
