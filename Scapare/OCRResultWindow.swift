//
//  OCRResultWindow.swift
//  Scapare
//
//  文字识别后的结果窗口（参考飞书）：显示识别到的文字，
//  提供「编辑」(可修正识别错误) 和「复制」两个按钮。
//

import AppKit

@MainActor
final class OCRResultController: NSObject, NSWindowDelegate {
    // 保持对已打开窗口的强引用，否则会被立刻释放。
    nonisolated(unsafe) private static var alive: [OCRResultController] = []

    private let window: NSWindow
    private let textView: NSTextView
    private let editButton: NSButton

    static func present(text: String) {
        let controller = OCRResultController(text: text)
        alive.append(controller)
        NSApp.activate(ignoringOtherApps: true)
        controller.window.makeKeyAndOrderFront(nil)
        controller.window.center()
    }

    private init(text: String) {
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 460, height: 360),
                          styleMask: [.titled, .closable, .resizable],
                          backing: .buffered,
                          defer: false)
        window.title = "文字识别结果"
        window.isReleasedWhenClosed = false

        // 文本区（默认只读，点「编辑」后可改）。
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        textView = NSTextView()
        textView.string = text.isEmpty ? "（未识别到文字）" : text
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        scroll.documentView = textView

        editButton = NSButton(title: "编辑", target: nil, action: nil)
        let copyButton = NSButton(title: "复制", target: nil, action: nil)
        editButton.bezelStyle = .rounded
        copyButton.bezelStyle = .rounded
        copyButton.keyEquivalent = "\r"   // 回车 = 复制

        super.init()

        window.delegate = self
        editButton.target = self
        editButton.action = #selector(toggleEdit)
        copyButton.target = self
        copyButton.action = #selector(copyText)

        let buttons = NSStackView(views: [editButton, copyButton])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(scroll)
        content.addSubview(buttons)
        window.contentView = content

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -12),

            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14),
        ])
    }

    @objc private func toggleEdit() {
        let editing = !textView.isEditable
        textView.isEditable = editing
        editButton.title = editing ? "完成" : "编辑"
        if editing {
            window.makeFirstResponder(textView)
        }
    }

    @objc private func copyText() {
        // 复制文字到剪贴板，并关闭结果窗口。
        Clipboard.copy(text: textView.string)
        window.close()
    }

    func windowWillClose(_ notification: Notification) {
        Self.alive.removeAll { $0 === self }
    }
}
