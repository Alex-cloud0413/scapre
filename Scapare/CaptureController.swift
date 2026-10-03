import AppKit

@MainActor
private struct CaptureEntry {
    let shots: [DisplayShot]
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
    private var pinWindows: [PinWindowController] = []
    private var history = BoundedHistory<CaptureEntry>(capacity: 6)
    private init() {}

    func startCapture() {
        guard !isCapturing else { return }
        isCapturing = true
        Task {
            do {
                let entry = CaptureEntry(shots: try await ScreenshotEngine.captureAllDisplays())
                history.append(entry)
                for shot in entry.shots {
                    guard let id = shot.screen.displayID, let session = entry.sessions[id] else { continue }
                    let overlay = OverlayController(shot: shot, controller: self, session: session)
                    overlays.append(overlay)
                    overlay.show()
                }
                updateHistoryStatus()
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
    }
    func cancel() { guard !isSaving else { return }; dismissOverlays() }
    func copyToClipboard(_ image: NSImage) { Clipboard.copy(image: image); dismissOverlays() }
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
        dismissOverlays()
        let pin = PinWindowController(image: image, at: globalRect)
        pinWindows.append(pin)
        pin.onClose = { [weak self] controller in self?.pinWindows.removeAll { $0 === controller } }
        pin.show()
    }
    func recognizeText(_ image: NSImage) {
        guard let data = image.pngData else {
            updateHistoryStatus(message: "无法读取图片，请重试；选区和标注仍然保留。")
            return
        }
        dismissOverlays()
        OCRResultController.present(pngData: data)
    }
}
