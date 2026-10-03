//
//  CaptureController.swift
//  SnapTool
//
//  整个截图流程的「总指挥」。全局只有一个(shared)。
//  负责：发起截图 → 在每块屏幕铺遮罩 → 接收用户最终的操作(复制/保存/贴图/识别)。
//

import AppKit
import UniformTypeIdentifiers

@MainActor
final class CaptureController {
    static let shared = CaptureController()

    private var overlays: [OverlayController] = []
    private var isCapturing = false
    private var pinWindows: [PinWindowController] = []

    // 截图历史：每次截图存一组(每块屏幕一张)。按 , / . 在历史间回溯。
    private var history: [[DisplayShot]] = []
    private var historyIndex = 0
    private let maxHistory = 6

    private init() {}

    // 入口：按 ⌘S 或点菜单都会调到这里。
    func startCapture() {
        guard !isCapturing else { return }
        isCapturing = true

        Task {
            do {
                let shots = try await ScreenshotEngine.captureAllDisplays()
                self.recordHistory(shots)
                self.presentOverlays(shots)
            } catch {
                self.isCapturing = false
                PermissionHelper.showScreenRecordingHint()
            }
        }
    }

    private func presentOverlays(_ shots: [DisplayShot]) {
        for shot in shots {
            let overlay = OverlayController(shot: shot, controller: self)
            overlays.append(overlay)
            overlay.show()
        }
        // 让本 App 抢到焦点，这样遮罩能收到键盘(Esc)。
        NSApp.activate(ignoringOtherApps: true)
    }

    private func recordHistory(_ shots: [DisplayShot]) {
        history.append(shots)
        if history.count > maxHistory {
            history.removeFirst(history.count - maxHistory)
        }
        historyIndex = history.count - 1
    }

    // 按 , (delta=-1) / . (delta=+1) 回溯截图历史，切换所有遮罩的背景画面。
    func navigateHistory(delta: Int) {
        guard !history.isEmpty else { return }
        let newIndex = min(max(0, historyIndex + delta), history.count - 1)
        guard newIndex != historyIndex else { return }
        historyIndex = newIndex
        let entry = history[newIndex]
        for overlay in overlays {
            if let shot = entry.first(where: { $0.screen.displayID == overlay.screen.displayID }) {
                overlay.editor.setBackground(shot)
            }
        }
    }

    // 关闭所有遮罩，结束本次截图。
    func dismissOverlays() {
        for overlay in overlays { overlay.close() }
        overlays.removeAll()
        isCapturing = false
    }

    // 用户取消（按 Esc 或点取消）。
    func cancel() {
        dismissOverlays()
    }

    // 复制到剪贴板。
    func copyToClipboard(_ image: NSImage) {
        Clipboard.copy(image: image)
        dismissOverlays()
    }

    // 保存为 PNG 文件。
    func saveToFile(_ image: NSImage) {
        dismissOverlays()
        guard let data = image.pngData else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        panel.nameFieldStringValue = "截图 \(formatter.string(from: Date())).png"

        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    // 把截图「钉」在屏幕上，变成一个浮动小窗。
    func pin(_ image: NSImage, at globalRect: CGRect) {
        dismissOverlays()
        let pin = PinWindowController(image: image, at: globalRect)
        pinWindows.append(pin)
        pin.onClose = { [weak self] controller in
            self?.pinWindows.removeAll { $0 === controller }
        }
        pin.show()
    }

    // 文字识别(OCR)：先收起遮罩，再识别，最后弹出结果窗口。
    func recognizeText(_ image: NSImage) {
        dismissOverlays()
        guard let data = image.pngData else { return }

        Task {
            let text = await OCRService.recognize(pngData: data)
            OCRResultController.present(text: text)
        }
    }
}
