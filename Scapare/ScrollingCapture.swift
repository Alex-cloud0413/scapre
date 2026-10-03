import AppKit

@MainActor
final class ScrollingCaptureController: NSObject, NSWindowDelegate {
    private static var current: ScrollingCaptureController?
    private let panel: NSPanel
    private let status = NSTextField(wrappingLabelWithString: "正在准备…")
    private let finishButton = NSButton(title: "完成并编辑", target: nil, action: nil)
    private let pauseButton = NSButton(title: "暂停", target: nil, action: nil)
    private var task: Task<Void, Never>?
    private var stitcher: ScrollStitcher?
    private var paused = false
    private var closed = false
    private let onClose: () -> Void
    static func start(screen: NSScreen, selection: CGRect, onClose: @escaping () -> Void) {
        guard current == nil else { onClose(); return }
        let controller = ScrollingCaptureController(screen: screen, onClose: onClose)
        current = controller; controller.panel.orderFrontRegardless()
        controller.run(screen: screen, selection: selection)
    }
    private init(screen: NSScreen, onClose: @escaping () -> Void) {
        self.onClose = onClose
        panel = NSPanel(contentRect: CGRect(x: screen.visibleFrame.minX + 16, y: screen.visibleFrame.maxY - 180, width: 460, height: 164),
                        styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = "滚动长截图 · Scapare"; panel.level = .floating; panel.isReleasedWhenClosed = false; panel.delegate = self
        let hint = NSTextField(wrappingLabelWithString: "在原窗口缓慢向下滚动，每次保留至少三分之一重叠，稍停片刻。完成后可预览和编辑。")
        hint.font = .systemFont(ofSize: 12); hint.textColor = .secondaryLabelColor
        finishButton.target = self; finishButton.action = #selector(finish); finishButton.isEnabled = false
        pauseButton.target = self; pauseButton.action = #selector(togglePause)
        let cancel = NSButton(title: "取消", target: self, action: #selector(cancel))
        let buttons = NSStackView(views: [cancel, pauseButton, finishButton]); buttons.spacing = 10
        let stack = NSStackView(views: [hint, status, buttons]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(stack)
        if let content = panel.contentView {
            NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16), stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 14), hint.widthAnchor.constraint(equalTo: stack.widthAnchor), status.widthAnchor.constraint(equalTo: stack.widthAnchor)])
        }
    }
    private func run(screen: NSScreen, selection: CGRect) {
        task = Task { [weak self] in
            do {
                let source = try await RegionCaptureSource(screen: screen, selection: selection)
                let first = try await source.capture()
                let initial = try await Task.detached { try PixelRaster(first) }.value
                guard !Task.isCancelled, let self, !self.closed else { return }
                self.stitcher = ScrollStitcher(first: initial); self.finishButton.isEnabled = true
                self.updateStatus()
                var lastSample: PixelRaster?
                while !Task.isCancelled && !self.closed {
                    try await Task.sleep(for: .milliseconds(450))
                    guard !self.paused else { continue }
                    let image = try await source.capture()
                    let raster = try await Task.detached { try PixelRaster(image) }.value
                    guard !Task.isCancelled, !self.closed else { return }
                    // Accept only a settled frame, so smooth scrolling cannot create a seam.
                    let stable: Bool
                    if let last = lastSample { stable = (try? ScrollMatcher.match(last, raster)) == .unchanged } else { stable = false }
                    lastSample = raster
                    guard stable, let previous = self.stitcher else { continue }
                    do {
                        let updated = try await Task.detached { var copy = previous; _ = try copy.append(raster); return copy }.value
                        guard !Task.isCancelled, !self.closed else { return }
                        self.stitcher = updated; self.updateStatus()
                    } catch {
                        self.status.stringValue = error.localizedDescription
                        if case ImageError.tooLarge = error { self.paused = true; self.pauseButton.title = "继续" }
                    }
                }
            } catch {
                guard !Task.isCancelled, let self, !self.closed else { return }
                self.status.stringValue = "捕获已暂停：" + error.localizedDescription
                self.pauseButton.isEnabled = false
            }
        }
    }
    private func updateStatus() {
        guard let stitcher else { return }
        status.stringValue = "已拼接 \(stitcher.frameCount) 帧 · \(stitcher.previous.width) × \(stitcher.height) px"
    }
    @objc private func togglePause() { paused.toggle(); pauseButton.title = paused ? "继续" : "暂停" }
    @objc private func finish() {
        guard let image = stitcher?.image() else { return }
        panel.close()
        ImageWorkspace.open(NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height)), title: "长截图 · Scapare")
    }
    @objc private func cancel() { panel.close() }
    func windowWillClose(_ notification: Notification) {
        guard !closed else { return }; closed = true; task?.cancel(); task = nil; Self.current = nil; onClose()
    }
}
