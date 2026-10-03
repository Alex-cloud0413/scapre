import AppKit

/// Scrollable document editor shared by long captures, imported images, whiteboards and pin re-editing.
final class ImageWorkspace: NSObject, NSWindowDelegate {
    private static var alive: [ImageWorkspace] = []
    private let window: NSWindow
    private let editor: EditorView
    private let scroll = NSScrollView()
    private var initialSnapshot: EditSnapshot
    private var deliveredSnapshot: EditSnapshot?
    private var allowClose = false
    private var onApply: ((NSImage, EditSnapshot) -> Void)?
    static func open(_ image: NSImage, title: String = "图片编辑 · Scapare", snapshot: EditSnapshot? = nil,
                     onApply: ((NSImage, EditSnapshot) -> Void)? = nil) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil), let screen = NSScreen.main else { AppDialogs.error("无法打开图片。"); return }
        let controller = ImageWorkspace(image: cg, screen: screen, title: title, snapshot: snapshot, onApply: onApply)
        alive.append(controller); NSApp.activate(ignoringOtherApps: true); controller.window.center(); controller.window.makeKeyAndOrderFront(nil)
        controller.scroll.contentView.scroll(to: CGPoint(x: 0, y: max(0, controller.editor.bounds.height - controller.scroll.contentSize.height)))
        controller.scroll.reflectScrolledClipView(controller.scroll.contentView)
    }
    private init(image: CGImage, screen: NSScreen, title: String, snapshot: EditSnapshot?, onApply: ((NSImage, EditSnapshot) -> Void)?) {
        let canvasSize = CGSize(width: image.width, height: image.height)
        let session = EditingSession(); session.snapshot = snapshot ?? EditSnapshot(selection: CGRect(origin: .zero, size: canvasSize))
        initialSnapshot = session.snapshot
        editor = EditorView(shot: DisplayShot(screen: screen, image: image), controller: .shared, session: session, canvasSize: canvasSize)
        editor.isLiveCapture = false
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 760), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        self.onApply = onApply
        super.init()
        window.title = title; window.minSize = NSSize(width: 580, height: 400); window.isReleasedWhenClosed = false; window.delegate = self
        let content = NSView(); window.contentView = content
        scroll.documentView = editor; scroll.hasHorizontalScroller = true; scroll.hasVerticalScroller = true
        scroll.allowsMagnification = true; scroll.minMagnification = 0.05; scroll.maxMagnification = 4
        scroll.magnification = min(1, 950 / CGFloat(image.width)); scroll.translatesAutoresizingMaskIntoConstraints = false
        let toolbar = EditorToolbar(editor: editor); editor.installExternalToolbar(toolbar)
        let toolsScroll = NSScrollView(); toolsScroll.documentView = toolbar; toolsScroll.hasHorizontalScroller = true
        toolsScroll.translatesAutoresizingMaskIntoConstraints = false
        let done = NSButton(title: onApply == nil ? "关闭" : "应用到贴图", target: self, action: #selector(doneTapped))
        done.bezelStyle = .rounded; done.translatesAutoresizingMaskIntoConstraints = false
        let hint = NSTextField(labelWithString: "⌘Z 撤销 · ⇧⌘Z 重做 · Shift 点击多选标注 · 双击编辑文字 · 右键更多操作")
        hint.font = .systemFont(ofSize: 11); hint.textColor = .secondaryLabelColor; hint.translatesAutoresizingMaskIntoConstraints = false
        [scroll, toolsScroll, done, hint].forEach { content.addSubview($0) }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: content.topAnchor), scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: toolsScroll.topAnchor, constant: -8), toolsScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            toolsScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12), toolsScroll.heightAnchor.constraint(equalToConstant: 64),
            toolsScroll.bottomAnchor.constraint(equalTo: done.topAnchor, constant: -8), done.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16), done.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            hint.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16), hint.centerYAnchor.constraint(equalTo: done.centerYAnchor), hint.trailingAnchor.constraint(lessThanOrEqualTo: done.leadingAnchor, constant: -12)
        ])
        editor.onCancel = { [weak self] in self?.window.performClose(nil) }
        editor.onOutput = { [weak self] output, image in self?.output(output, image) }
    }
    private func output(_ action: EditorOutput, _ image: NSImage) {
        switch action {
        case .copy: Clipboard.copy(image: image); deliveredSnapshot = editor.editingSnapshot
        case .save: if case .saved = ImageFileSaver.save(image) { deliveredSnapshot = editor.editingSnapshot }
        case .pin: if PinManager.shared.add(image) { deliveredSnapshot = editor.editingSnapshot }
        case .ocr: OCRResultController.present(image: image)
        case .barcode: OCRResultController.present(image: image, barcode: true)
        case .share: NSSharingServicePicker(items: [image]).show(relativeTo: .zero, of: editor, preferredEdge: .minY)
        case .quickSave: if ImageFileSaver.quickSave(image) { deliveredSnapshot = editor.editingSnapshot }
        }
    }
    @objc private func doneTapped() {
        if let onApply, let image = editor.renderResult() { onApply(image, editor.editingSnapshot); allowClose = true; window.close() }
        else { window.performClose(nil) }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowClose { return true }
        let snapshot = editor.editingSnapshot
        if onApply != nil && snapshot == initialSnapshot { return true }
        if deliveredSnapshot == snapshot { return true }
        let alert = NSAlert(); alert.messageText = onApply == nil ? "保存这张图片后关闭？" : "将修改应用到贴图？"
        alert.informativeText = "关闭后无法恢复本窗口中未保存的编辑。"; alert.addButton(withTitle: onApply == nil ? "保存…" : "应用"); alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "放弃修改")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            guard let image = editor.renderResult() else { return false }
            if let onApply { onApply(image, snapshot); return true }
            if case .saved = ImageFileSaver.save(image) { return true }; return false
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }
    func windowWillClose(_ notification: Notification) { editor.detachSession(); Self.alive.removeAll { $0 === self } }
}
