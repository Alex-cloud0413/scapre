import AppKit

@MainActor
final class OCRResultController: NSObject, NSWindowDelegate, NSTextViewDelegate {
    private static var alive: [OCRResultController] = []
    private let window: NSWindow
    private let textView = NSTextView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let progress = NSProgressIndicator()
    private let editButton = NSButton(title: "编辑", target: nil, action: nil)
    private let copyButton = NSButton(title: "复制", target: nil, action: nil)
    private let retryButton = NSButton(title: "重试", target: nil, action: nil)
    private let pngData: Data
    private let barcode: Bool
    private var task: Task<Void, Never>?
    private var requestID = UUID()
    private var state: OCRState = .loading

    static func present(image: NSImage, barcode: Bool = false) {
        guard let data = image.pngData else { AppDialogs.error("无法读取图片。"); return }
        present(pngData: data, barcode: barcode)
    }
    static func present(pngData: Data, barcode: Bool = false) {
        let controller = OCRResultController(pngData: pngData, barcode: barcode)
        alive.append(controller)
        NSApp.activate(ignoringOtherApps: true)
        controller.window.center()
        controller.window.makeKeyAndOrderFront(nil)
        controller.startRecognition()
    }
    private init(pngData: Data, barcode: Bool) {
        self.pngData = pngData
        self.barcode = barcode
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 480, height: 380),
                          styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = barcode ? "条码识别 · Scapare" : "文字识别 · Scapare"
        window.minSize = NSSize(width: 340, height: 240)
        window.isReleasedWhenClosed = false
        super.init()
        window.delegate = self
        textView.delegate = self
        textView.isEditable = false
        textView.isRichText = false
        textView.isSelectable = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 440, height: CGFloat.greatestFiniteMagnitude)
        textView.setAccessibilityLabel("识别出的文字")
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = textView
        scroll.translatesAutoresizingMaskIntoConstraints = false
        progress.style = .spinning
        progress.controlSize = .small
        progress.isDisplayedWhenStopped = false
        statusLabel.textColor = .secondaryLabelColor
        let statusRow = NSStackView(views: [progress, statusLabel])
        statusRow.spacing = 8
        statusRow.translatesAutoresizingMaskIntoConstraints = false
        for button in [editButton, copyButton, retryButton] { button.bezelStyle = .rounded; button.target = self }
        editButton.action = #selector(toggleEdit)
        copyButton.action = #selector(copyText)
        retryButton.action = #selector(startRecognition)
        copyButton.keyEquivalent = "\r"
        let close = NSButton(title: "关闭", target: self, action: #selector(closeWindow))
        close.bezelStyle = .rounded
        close.keyEquivalent = "\u{1b}"
        let buttons = NSStackView(views: [close, retryButton, editButton, copyButton])
        buttons.spacing = 10
        buttons.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        [scroll, statusRow, buttons].forEach { content.addSubview($0) }
        window.contentView = content
        NSLayoutConstraint.activate([
            statusRow.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            statusRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            statusRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: statusRow.bottomAnchor, constant: 10),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -12),
            buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            buttons.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
        ])
        render(.loading)
    }
    @objc private func startRecognition() {
        task?.cancel()
        requestID = UUID()
        let id = requestID
        let data = pngData
        render(.loading)
        task = Task { [weak self] in
            do {
                let text = try await (self?.barcode == true ? OCRService.barcodes(pngData: data) : OCRService.recognize(pngData: data))
                guard !Task.isCancelled, self?.requestID == id else { return }
                self?.render(.recognized(text))
            } catch {
                guard !Task.isCancelled, self?.requestID == id else { return }
                self?.render(.failure(error.localizedDescription))
            }
        }
    }
    private func render(_ newState: OCRState) {
        state = newState
        textView.string = newState.text
        textView.isEditable = false
        editButton.title = "编辑"
        editButton.isEnabled = newState.canCopy
        copyButton.isEnabled = newState.canCopy
        retryButton.isHidden = true
        progress.stopAnimation(nil)
        switch newState {
        case .loading: statusLabel.stringValue = barcode ? "正在识别条码…" : "正在识别文字…"; progress.startAnimation(nil)
        case .result: statusLabel.stringValue = "识别完成，可以编辑后复制。"
        case .empty: statusLabel.stringValue = barcode ? "未发现条码，可以重试或重新截图。" : "未识别到文字，可以重试或重新截图。"; retryButton.isHidden = false
        case .failure(let message): statusLabel.stringValue = "识别失败：\(message)"; retryButton.isHidden = false
        }
    }
    @objc private func toggleEdit() {
        textView.isEditable.toggle()
        editButton.title = textView.isEditable ? "完成" : "编辑"
        if textView.isEditable { window.makeFirstResponder(textView) }
    }
    func textDidChange(_ notification: Notification) {
        state = .recognized(textView.string)
        copyButton.isEnabled = state.canCopy
    }
    @objc private func copyText() {
        guard state.canCopy else { return }
        Clipboard.copy(text: textView.string)
        window.close()
    }
    @objc private func closeWindow() { window.close() }
    func windowWillClose(_ notification: Notification) {
        task?.cancel()
        requestID = UUID()
        Self.alive.removeAll { $0 === self }
    }
}
