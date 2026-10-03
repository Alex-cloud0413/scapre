//
//  PinWindow.swift
//  Scapare
//
//  「钉图」：把截好的图变成一个浮动小窗，固定在屏幕最上层。
//  支持：拖动移动、滚轮/触控板缩放、双击复制、右键菜单(复制/保存/透明度/关闭)。
//

import AppKit
import UniformTypeIdentifiers

@MainActor
final class PinWindowController {
    private let window: PinWindow
    private let pinView: PinView
    var onClose: ((PinWindowController) -> Void)?

    init(image: NSImage, at globalRect: CGRect) {
        pinView = PinView(image: image)
        window = PinWindow(contentRect: globalRect,
                           styleMask: .borderless,
                           backing: .buffered,
                           defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = pinView

        pinView.onCopy = { Clipboard.copy(image: image) }
        pinView.onSave = { [weak self] in self?.saveImage(image) }
        pinView.onClose = { [weak self] in self?.close() }
        pinView.onSetOpacity = { [weak self] value in self?.window.alphaValue = value }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    private func close() {
        window.orderOut(nil)
        onClose?(self)
    }

    private func saveImage(_ image: NSImage) {
        _ = ImageFileSaver.save(image)
    }

}

// 贴图窗口需要能成为 key 窗口，才能接收键盘/双击等事件。
final class PinWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class PinView: NSView {
    private let image: NSImage
    private let aspect: CGFloat
    private var dragOffset: CGPoint = .zero

    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onClose: (() -> Void)?
    var onSetOpacity: ((CGFloat) -> Void)?

    init(image: NSImage) {
        self.image = image
        self.aspect = image.size.height > 0 ? image.size.width / image.size.height : 1
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    // MARK: - 拖动 & 双击复制

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onClose?()   // 双击销毁贴图（和 Snipaste 一致；复制改用右键菜单）
            return
        }
        guard let window = window else { return }
        let mouse = NSEvent.mouseLocation
        dragOffset = CGPoint(x: mouse.x - window.frame.origin.x,
                             y: mouse.y - window.frame.origin.y)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window = window else { return }
        let mouse = NSEvent.mouseLocation
        window.setFrameOrigin(CGPoint(x: mouse.x - dragOffset.x,
                                      y: mouse.y - dragOffset.y))
    }

    // MARK: - 缩放

    override func scrollWheel(with event: NSEvent) {
        zoom(by: 1 + event.scrollingDeltaY * 0.006)
    }
    override func magnify(with event: NSEvent) {
        zoom(by: 1 + event.magnification)
    }

    private func zoom(by factor: CGFloat) {
        guard let window = window else { return }
        let old = window.frame
        var newW = old.width * factor
        newW = min(max(newW, 50), 6000)
        let newH = newW / aspect
        // 以中心为锚点缩放。
        let newOrigin = CGPoint(x: old.midX - newW / 2, y: old.midY - newH / 2)
        window.setFrame(CGRect(origin: newOrigin, size: CGSize(width: newW, height: newH)),
                        display: true)
    }

    // MARK: - 键盘

    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onClose?() }      // Esc 关闭
        else { super.keyDown(with: event) }
    }

    // MARK: - 右键菜单

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "复制", action: #selector(copyAction), keyEquivalent: "").target = self
        menu.addItem(withTitle: "保存为图片…", action: #selector(saveAction), keyEquivalent: "").target = self

        menu.addItem(.separator())
        let opacityItem = NSMenuItem(title: "不透明度", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for value in [100, 80, 60, 40, 20] {
            let item = sub.addItem(withTitle: "\(value)%", action: #selector(opacityAction(_:)), keyEquivalent: "")
            item.target = self
            item.tag = value
        }
        opacityItem.submenu = sub
        menu.addItem(opacityItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "关闭", action: #selector(closeAction), keyEquivalent: "").target = self
        return menu
    }

    @objc private func copyAction() { onCopy?() }
    @objc private func saveAction() { onSave?() }
    @objc private func closeAction() { onClose?() }
    @objc private func opacityAction(_ sender: NSMenuItem) {
        onSetOpacity?(CGFloat(sender.tag) / 100.0)
    }
}
