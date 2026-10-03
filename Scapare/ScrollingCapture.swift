import AppKit

@MainActor
protocol ScrollingCaptureSource {
    func capture() async throws -> CGImage
}

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
    private var stitcher: ScrollStitcher?
    private var paused = false
    private var closed = false
    private let onClose: () -> Void
    private let onFinish: @MainActor (CGImage) -> Void
    private let makeSource: @MainActor () async throws -> any ScrollingCaptureSource

    static func start(screen: NSScreen, selection: CGRect, onClose: @escaping () -> Void) {
        guard current == nil else { current?.panel.orderFrontRegardless(); onClose(); return }
        let controller = ScrollingCaptureController(screen: screen, selection: selection, onClose: onClose)
        current = controller
        controller.present()
    }

    init(screen: NSScreen, selection: CGRect, onClose: @escaping () -> Void,
         makeSource: (@MainActor () async throws -> any ScrollingCaptureSource)? = nil,
         onFinish: @escaping @MainActor (CGImage) -> Void = {
             ImageWorkspace.open(NSImage(cgImage: $0, size: CGSize(width: $0.width, height: $0.height)), title: "长截图 · Scapare")
         }) {
        self.onClose = onClose
        self.onFinish = onFinish
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

        let hint = NSTextField(wrappingLabelWithString: "将鼠标移到框内，缓慢向下滚动并稍作停顿。内容会自动拼接。")
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
        let buttons = NSStackView(views: [cancel, pauseButton, finishButton])
        buttons.spacing = 8
        let stack = NSStackView(views: [status, hint, progress, buttons])
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
            do {
                guard let source = try await self?.makeSource() else { return }
                // Let the original window finish activating before taking the first frame.
                try await Task.sleep(for: .milliseconds(250))
                let first = try await source.capture()
                let initial = try await Task.detached { try PixelRaster(first) }.value
                guard !Task.isCancelled, let self, !self.closed else { return }
                self.stitcher = ScrollStitcher(first: initial)
                self.finishButton.isEnabled = true
                self.pauseButton.isEnabled = true
                self.updatePreview()
                self.status.stringValue = "已就绪，可在框内向下滚动"
                var lastSample = initial
                while !Task.isCancelled && !self.closed {
                    try await Task.sleep(for: .milliseconds(350))
                    guard !self.paused else { continue }
                    let image = try await source.capture()
                    let last = lastSample
                    let (raster, stable) = try await Task.detached {
                        let raster = try PixelRaster(image)
                        return (raster, ScrollMatcher.isUnchanged(last, raster))
                    }.value
                    guard !Task.isCancelled, !self.closed else { return }
                    lastSample = raster
                    guard !self.paused else { continue }
                    guard stable, let previous = self.stitcher else {
                        self.status.stringValue = "正在滚动，稍停片刻即可拼接"
                        continue
                    }
                    do {
                        let (updated, appended) = try await Task.detached {
                            var copy = previous
                            let appended = try copy.append(raster)
                            return (copy, appended)
                        }.value
                        guard !Task.isCancelled, !self.closed, !self.paused else { continue }
                        self.stitcher = updated
                        if appended { self.updatePreview() }
                        self.status.stringValue = "已拼接，可继续向下滚动或完成"
                    } catch {
                        self.status.stringValue = error.localizedDescription
                        if case ImageError.tooLarge = error {
                            self.paused = true
                            self.pauseButton.isEnabled = false
                        }
                    }
                }
            } catch {
                guard !Task.isCancelled, let self, !self.closed else { return }
                self.status.stringValue = "捕获已停止：" + error.localizedDescription
                self.pauseButton.isEnabled = false
                // Keep Cancel available, and allow exporting any frames already captured.
            }
        }
    }

    private func updatePreview() {
        guard let stitcher else { return }
        progress.stringValue = "\(stitcher.frameCount) 帧 · \(stitcher.previous.width) × \(stitcher.height) px"
        if let image = stitcher.preview(maxSize: CGSize(width: 192, height: 416)) {
            preview.image = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
        }
    }
    @objc private func togglePause() {
        paused.toggle()
        pauseButton.title = paused ? "继续" : "暂停"
        status.stringValue = paused ? "已暂停，已拼接内容会保留" : "可继续向下滚动"
    }
    @objc func finish() {
        guard !closed, let image = stitcher?.image() else { return }
        close()
        onFinish(image)
    }
    @objc private func cancel() { close() }
    func close() {
        guard !closed else { return }
        closed = true
        task?.cancel()
        task = nil
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
