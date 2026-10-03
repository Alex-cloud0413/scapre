import AppKit

@MainActor
protocol ScrollingCaptureSource {
    func frames() async throws -> AsyncThrowingStream<PixelRaster, Error>
    func stop() async
    func validateDisplay() throws
}

extension ScrollingCaptureSource { func validateDisplay() throws {} }

@MainActor
final class ScrollingCaptureController: NSObject, NSWindowDelegate {
    private static var current: ScrollingCaptureController?
    let panel: NSPanel
    let regionOutline: NSPanel
    let status = NSTextField(wrappingLabelWithString: "正在准备，请稍候…")
    let finishButton = NSButton(title: "完成并编辑", target: nil, action: nil)
    private let pauseButton = NSButton(title: "暂停", target: nil, action: nil)
    private let preview = NSImageView()
    private let progress = NSTextField(labelWithString: "")
    private var task: Task<Void, Never>?
    let copyButton = NSButton(title: "完成并复制", target: nil, action: nil)
    private let assembler = ScrollCaptureAssembler()
    private var source: (any ScrollingCaptureSource)?
    private enum FinishAction { case edit, copy }
    private var finishAction: FinishAction?
    private var loopEnded = false
    private var delivering = false
    private var paused = false
    private var closed = false
    private let onClose: () -> Void
    private let onFinish: @MainActor (CGImage) -> Void
    private let onCopy: @MainActor (CGImage) -> Bool
    private let makeSource: @MainActor () async throws -> any ScrollingCaptureSource

    static func start(screen: NSScreen, selection: CGRect, onClose: @escaping () -> Void) {
        guard current == nil else { current?.panel.orderFrontRegardless(); onClose(); return }
        let controller = ScrollingCaptureController(screen: screen, selection: selection, onClose: onClose)
        current = controller
        controller.present()
    }

    init(screen: NSScreen, selection: CGRect, onClose: @escaping () -> Void,
         makeSource: (@MainActor () async throws -> any ScrollingCaptureSource)? = nil,
         onCopy: @escaping @MainActor (CGImage) -> Bool = { Clipboard.copy(image: NSImage(cgImage: $0, size: CGSize(width: $0.width, height: $0.height))) },
         onFinish: @escaping @MainActor (CGImage) -> Void = {
             ImageWorkspace.open(NSImage(cgImage: $0, size: CGSize(width: $0.width, height: $0.height)), title: "长截图 · Scapare")
         }) {
        self.onClose = onClose
        self.onFinish = onFinish
        self.onCopy = onCopy
        self.makeSource = makeSource ?? { try await RegionCaptureSource(screen: screen, selection: selection) }
        let region = selection.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
        panel = NSPanel(contentRect: CGRect(origin: .zero, size: CGSize(width: 440, height: 240)),
                        styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        regionOutline = NSPanel(contentRect: region.insetBy(dx: -3, dy: -3), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = "滚动截图 · Scapare"
        panel.level = .floating
        // NSPanel defaults to hiding on deactivation. Capturing requires the original
        // app to be active, so both windows must remain visible across that handoff.
        for window in [panel, regionOutline] {
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
        panel.delegate = self
        panel.setFrameOrigin(ScrollCaptureLayout.panelOrigin(size: panel.frame.size, region: region, visibleFrame: screen.visibleFrame))
        regionOutline.level = .floating
        regionOutline.isOpaque = false
        regionOutline.backgroundColor = .clear
        regionOutline.hasShadow = false
        regionOutline.ignoresMouseEvents = true
        let outline = NSView(frame: CGRect(origin: .zero, size: regionOutline.frame.size))
        outline.wantsLayer = true
        outline.layer?.borderColor = NSColor.controlAccentColor.cgColor
        outline.layer?.borderWidth = 3
        regionOutline.contentView = outline

        let hint = NSTextField(wrappingLabelWithString: "在框内自然向下滚动，画面会连续拼接。完成后可直接复制，或继续编辑。")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 13, weight: .medium)
        progress.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        progress.textColor = .secondaryLabelColor
        finishButton.target = self
        finishButton.action = #selector(finish)
        finishButton.isEnabled = false
        finishButton.toolTip = "结束滚动，打开已拼接的图片进行编辑"
        pauseButton.target = self
        pauseButton.action = #selector(togglePause)
        pauseButton.isEnabled = false
        pauseButton.toolTip = "暂时停止采集，保留已拼接的内容"
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancel))
        cancel.toolTip = "取消本次滚动截图"
        copyButton.target = self
        copyButton.action = #selector(finishAndCopy)
        copyButton.isEnabled = false
        copyButton.toolTip = "结束滚动并复制长图，可直接粘贴到其他应用"
        copyButton.keyEquivalent = "\r"
        let auxiliaryButtons = NSStackView(views: [cancel, pauseButton])
        auxiliaryButtons.spacing = 8
        let buttons = NSStackView(views: [finishButton, copyButton])
        buttons.spacing = 8
        let stack = NSStackView(views: [status, hint, progress, auxiliaryButtons, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        preview.imageScaling = .scaleProportionallyUpOrDown
        preview.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        preview.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        preview.setAccessibilityLabel("已拼接的长截图预览")
        preview.wantsLayer = true
        preview.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        preview.translatesAutoresizingMaskIntoConstraints = false
        if let content = panel.contentView {
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            content.addSubview(stack)
            content.addSubview(preview)
            NSLayoutConstraint.activate([
                content.widthAnchor.constraint(equalToConstant: 440),
                content.heightAnchor.constraint(equalToConstant: 240),
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
                stack.trailingAnchor.constraint(equalTo: preview.leadingAnchor, constant: -16),
                hint.widthAnchor.constraint(equalTo: stack.widthAnchor),
                status.widthAnchor.constraint(equalTo: stack.widthAnchor),
                preview.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
                preview.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
                preview.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
                preview.widthAnchor.constraint(equalToConstant: 96)
            ])
        }
    }

    func present() {
        regionOutline.orderFrontRegardless()
        panel.orderFrontRegardless()
        run()
    }

    func run() {
        guard task == nil, !closed else { return }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let source = try await self.makeSource()
                self.source = source
                guard !Task.isCancelled, !self.closed else { await source.stop(); return }
                let frames = try await source.frames()
                var lastDisplayCheck = ContinuousClock.now
                for try await raster in frames {
                    guard !Task.isCancelled, !self.closed else { break }
                    guard !self.paused else { continue }
                    if lastDisplayCheck.duration(to: .now) > .seconds(1) {
                        try source.validateDisplay()
                        lastDisplayCheck = .now
                    }
                    do {
                        let update = try await self.assembler.accept(raster)
                        guard !Task.isCancelled, !self.closed else { break }
                        self.progress.stringValue = "\(update.frameCount) 帧 · \(update.width) × \(update.height) px"
                        if let image = update.preview { self.preview.image = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height)) }
                        if self.finishAction == nil {
                            self.finishButton.isEnabled = true; self.copyButton.isEnabled = true
                            self.pauseButton.isEnabled = true
                            self.status.stringValue = self.paused ? "已暂停，已拼接内容会保留" : "正在连续拼接，可直接完成并复制"
                        }
                    } catch {
                        self.status.stringValue = error.localizedDescription
                        if case ImageError.tooLarge = error {
                            self.paused = true
                            self.pauseButton.isEnabled = false
                        }
                    }
                }
            } catch {
                if !Task.isCancelled, !self.closed {
                    self.status.stringValue = "捕获已停止：" + error.localizedDescription
                    self.pauseButton.isEnabled = false
                }
            }
            await self.source?.stop()
            self.loopEnded = true
            if self.finishAction != nil { await self.deliverResult() }
        }
    }

    @objc private func togglePause() {
        paused.toggle()
        pauseButton.title = paused ? "继续" : "暂停"
        status.stringValue = paused ? "已暂停，已拼接内容会保留" : "正在连续拼接"
    }
    @objc func finish() { requestFinish(.edit) }
    @objc func finishAndCopy() { requestFinish(.copy) }
    private func requestFinish(_ action: FinishAction) {
        guard !closed, finishAction == nil else { return }
        finishAction = action
        paused = false
        finishButton.isEnabled = false; copyButton.isEnabled = false; pauseButton.isEnabled = false
        status.stringValue = "正在处理最后的画面…"
        // Finish the stream, then drain already delivered frames before exporting.
        // Cancelling the consumer here would silently lose the last scroll movement.
        Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .milliseconds(60))
            await self.source?.stop()
            if self.loopEnded { await self.deliverResult() }
        }
    }
    private func deliverResult() async {
        guard !closed, !delivering, let action = finishAction else { return }
        delivering = true
        guard let image = await assembler.image() else {
            delivering = false; finishAction = nil
            status.stringValue = "未获得可用画面，请取消后重新截图。"
            return
        }
        guard !closed else { return }
        switch action {
        case .copy:
            if onCopy(image) { close() }
            else {
                delivering = false; finishAction = nil
                finishButton.isEnabled = true; copyButton.isEnabled = true
                status.stringValue = "复制失败，长图仍然保留。可以重试或打开编辑器保存。"
            }
        case .edit: close(); onFinish(image)
        }
    }
    @objc private func cancel() { close() }
    func close() {
        guard !closed else { return }
        closed = true
        task?.cancel()
        task = nil
        if let source { Task { await source.stop() } }
        regionOutline.close()
        panel.close()
        if Self.current === self { Self.current = nil }
        onClose()
    }
    func windowWillClose(_ notification: Notification) { close() }
}

nonisolated enum ScrollCaptureLayout {
    static func panelOrigin(size: CGSize, region: CGRect, visibleFrame: CGRect) -> CGPoint {
        let available = visibleFrame.insetBy(dx: 8, dy: 8)
        func clamp(_ point: CGPoint) -> CGPoint {
            CGPoint(x: max(available.minX, min(point.x, available.maxX - size.width)),
                    y: max(available.minY, min(point.y, available.maxY - size.height)))
        }
        let candidates = [
            CGPoint(x: region.maxX + 12, y: region.maxY - size.height),
            CGPoint(x: region.minX - size.width - 12, y: region.maxY - size.height),
            CGPoint(x: region.midX - size.width / 2, y: region.minY - size.height - 12),
            CGPoint(x: region.midX - size.width / 2, y: region.maxY + 12)
        ].map(clamp)
        return candidates.first { !CGRect(origin: $0, size: size).intersects(region) }
            ?? clamp(CGPoint(x: available.maxX - size.width, y: available.maxY - size.height))
    }
}
