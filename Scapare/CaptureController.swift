import AppKit

@MainActor
private final class CaptureEntry {
    var shots: [DisplayShot]
    let sessions: [CGDirectDisplayID: EditingSession]
    init(shots: [DisplayShot]) {
        self.shots = shots
        sessions = Dictionary(uniqueKeysWithValues: shots.compactMap { shot in
            shot.screen.displayID.map { ($0, EditingSession()) }
        })
    }
}

@MainActor
final class CaptureController {
    static let shared = CaptureController()
    private var overlays: [OverlayController] = []
    private var isCapturing = false
    private var isSaving = false
    private var sourceApplication: NSRunningApplication?
    private var captureDelay: Task<Void, Never>?
    private var history = BoundedHistory<CaptureEntry>(capacity: 6)
    private let beginScrollingCapture: @MainActor (NSScreen, CGRect, @escaping () -> Void) -> Void
    init(beginScrollingCapture: @escaping @MainActor (NSScreen, CGRect, @escaping () -> Void) -> Void = {
        ScrollingCaptureController.start(screen: $0, selection: $1, onClose: $2)
    }) {
        self.beginScrollingCapture = beginScrollingCapture
    }

    enum Mode { case region, fullScreen, activeWindow, repeatRegion, long }
    func startCapture(mode: Mode = .region) {
        guard !isCapturing else { return }
        sourceApplication = NSWorkspace.shared.frontmostApplication
        let pointer = NSEvent.mouseLocation
        isCapturing = true
        Task {
            do {
                let entry = CaptureEntry(shots: try await ScreenshotEngine.captureAllDisplays())
                history.append(entry)
                for shot in entry.shots {
                    guard let id = shot.screen.displayID, let session = entry.sessions[id] else { continue }
                    switch mode {
                    case .fullScreen: session.snapshot.selection = CGRect(origin: .zero, size: shot.screen.frame.size)
                    case .activeWindow: session.snapshot.selection = shot.foregroundWindow
                    case .repeatRegion: session.snapshot.selection = SettingsManager.lastRegion(displayID: id)?.intersection(CGRect(origin: .zero, size: shot.screen.frame.size))
                    default: break
                    }
                    let overlay = OverlayController(shot: shot, controller: self, session: session)
                    overlays.append(overlay)
                    overlay.show()
                    if let rect = session.snapshot.selection { overlay.editor.setSelection(rect) }
                }
                overlays.first { $0.screen.frame.contains(pointer) }?.window.makeKeyAndOrderFront(nil)
                updateHistoryStatus(message: mode == .long ? "先框选滚动内容（避开固定页眉），再点工具条的长截图按钮" : nil)
                NSApp.activate(ignoringOtherApps: true)
            } catch {
                isCapturing = false
                PermissionHelper.showCaptureError(error) { [weak self] in self?.startCapture() }
            }
        }
    }
    func navigateHistory(delta: Int) {
        guard !isSaving else { return }
        guard let index = history.destination(delta: delta) else {
            updateHistoryStatus(message: delta < 0 ? "已经是最早一张" : "已经是最新一张")
            return
        }
        let entry = history.entries[index]
        let displayIDs = Set(overlays.compactMap { $0.screen.displayID })
        guard displayIDs == Set(entry.sessions.keys) else {
            updateHistoryStatus(message: "这张历史截图的显示器配置已改变")
            return
        }
        for overlay in overlays { overlay.editor.finishPendingEditing() }
        history.move(to: index)
        for overlay in overlays {
            if let id = overlay.screen.displayID,
               let shot = entry.shots.first(where: { $0.screen.displayID == id }),
               let session = entry.sessions[id] {
                overlay.editor.setBackground(shot, session: session)
            }
        }
        updateHistoryStatus()
    }
    private func updateHistoryStatus(message: String? = nil) {
        let text = message ?? "截图 \(history.index + 1)/\(history.entries.count) · , 上一张 · . 下一张 · 右键查看操作"
        for overlay in overlays { overlay.editor.setHistoryStatus(text) }
    }
    func dismissOverlays() {
        for overlay in overlays {
            overlay.editor.finishPendingEditing()
            overlay.editor.detachSession()
            overlay.close()
        }
        overlays.removeAll()
        isCapturing = false
        sourceApplication?.activate(options: [])
    }
    func cancel() { guard !isSaving else { return }; dismissOverlays() }
    func copyToClipboard(_ image: NSImage) {
        if SettingsManager.autoSave && !ImageFileSaver.quickSave(image, allowChoose: false) { return }
        Clipboard.copy(image: image); dismissOverlays()
    }
    func saveToFile(_ image: NSImage) {
        guard !isSaving else { return }
        isSaving = true
        let focusedWindow = NSApp.keyWindow
        for overlay in overlays { overlay.close() }
        let result = ImageFileSaver.save(image)
        isSaving = false
        switch result {
        case .saved: dismissOverlays()
        case .cancelled:
            for overlay in overlays { overlay.show() }
            focusedWindow?.makeKeyAndOrderFront(nil)
        }
    }
    func pin(_ image: NSImage, at globalRect: CGRect) {
        if SettingsManager.autoSave && !ImageFileSaver.quickSave(image, allowChoose: false) { return }
        if PinManager.shared.add(image, frame: globalRect) { dismissOverlays() }
    }
    func recognizeText(_ image: NSImage) {
        guard let data = image.pngData else {
            updateHistoryStatus(message: "无法读取图片，请重试；选区和标注仍然保留。")
            return
        }
        dismissOverlays()
        OCRResultController.present(pngData: data)
    }
    func startLongCapture(on screen: NSScreen, selection: CGRect) {
        dismissOverlays(); isCapturing = true
        beginScrollingCapture(screen, selection) { [weak self] in self?.isCapturing = false }
    }
    func delayedCapture(seconds: Int) {
        captureDelay?.cancel()
        captureDelay = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            self?.startCapture()
        }
    }
    func cancelDelay() { captureDelay?.cancel(); captureDelay = nil }
    func refreshCapture() {
        guard isCapturing, !isSaving else { return }
        Task {
            do {
                let shots = try await ScreenshotEngine.captureAllDisplays()
                guard isCapturing else { return }
                for overlay in overlays {
                    if let shot = shots.first(where: { $0.screen.displayID == overlay.screen.displayID }), shot.screen.frame.size == overlay.editor.bounds.size {
                        overlay.editor.replaceBackground(shot.image)
                    }
                }
                history.current?.shots = shots
                updateHistoryStatus(message: "背景已刷新，标注保留")
            } catch { updateHistoryStatus(message: error.localizedDescription) }
        }
    }
}
