//
//  ScreenshotEngine.swift
//  Scapare
//
//  负责把屏幕「拍」下来，得到一张静止的画面。
//  我们用苹果官方的 ScreenCaptureKit。第一次使用时，系统会弹窗请求
//  「屏幕录制」权限，需要你在「系统设置」里授权（并重启本 App 一次）。
//

import ScreenCaptureKit
import AppKit

// 一块屏幕拍下来的结果：对应哪块屏幕 + 这块屏幕的画面。
struct DisplayShot {
    let screen: NSScreen
    let image: CGImage
    var windows: [CGRect] = []
    var foregroundWindow: CGRect?
    var sourcePID: pid_t?
}

enum ScreenshotError: LocalizedError {
    case permissionDenied
    case captureFailed(String)
    case noDisplays
    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Scapare 尚未获得屏幕录制权限。"
        case .captureFailed(let reason): return reason
        case .noDisplays: return "没有找到可捕获的显示器，请确认显示器已连接。"
        }
    }
    static func classify(_ error: Error) -> ScreenshotError {
        let ns = error as NSError
        if ns.domain == SCStreamErrorDomain && ns.code == SCStreamError.Code.userDeclined.rawValue {
            return .permissionDenied
        }
        return .captureFailed(error.localizedDescription)
    }
}

enum ScreenshotEngine {
    // 把所有屏幕都拍一遍。返回每块屏幕对应的画面。
    static func captureAllDisplays() async throws -> [DisplayShot] {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: false)
        } catch {
            throw ScreenshotError.classify(error)
        }

        let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let zOrder = Dictionary(uniqueKeysWithValues: windowList.enumerated().compactMap { index, info -> (UInt32, Int)? in
            guard let id = info[kCGWindowNumber as String] as? UInt32 else { return nil }; return (id, index)
        })
        let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        // Keep visible desktop pins in the captured scene, while excluding our
        // editors, capture overlays, settings and other transient windows.
        let pinIDs = PinManager.shared.captureWindowIDs
        let pinnedWindows = content.windows.filter {
            $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier
                && $0.isOnScreen && pinIDs.contains($0.windowID)
        }
        let foregroundPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let referenceHeight = NSScreen.screens.first?.frame.height ?? 0
        var results: [DisplayShot] = []
        for display in content.displays {
            guard let screen = NSScreen.screens.first(where: {
                $0.displayID == display.displayID
            }) else { continue }

            let scale = Int(screen.backingScaleFactor)
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: pinnedWindows)
            let config = SCStreamConfiguration()
            config.width = display.width * scale      // 按真实像素拍，保证清晰
            config.height = display.height * scale
            config.showsCursor = SettingsManager.captureCursor                // 不把鼠标指针拍进去
            config.captureResolution = .best

            do {
                let cgImage = try await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: config)
                let candidates = content.windows.filter {
                    $0.isOnScreen && $0.frame.width > 20 && $0.frame.height > 20
                        && (($0.windowLayer == 0 && $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier)
                            || pinIDs.contains($0.windowID))
                }.sorted { (zOrder[$0.windowID] ?? Int.max) < (zOrder[$1.windowID] ?? Int.max) }
                func localFrame(_ window: SCWindow) -> CGRect {
                    CGRect(x: window.frame.minX - screen.frame.minX, y: referenceHeight - window.frame.maxY - screen.frame.minY,
                           width: window.frame.width, height: window.frame.height).intersection(CGRect(origin: .zero, size: screen.frame.size))
                }
                let rects = candidates.map(localFrame).filter { !$0.isNull }
                let foreground = candidates.first { $0.owningApplication?.processID == foregroundPID }.map(localFrame)
                results.append(DisplayShot(screen: screen, image: cgImage, windows: rects, foregroundWindow: foreground?.isNull == false ? foreground : nil, sourcePID: foregroundPID))
            } catch {
                throw ScreenshotError.classify(error)
            }
        }

        if results.isEmpty {
            throw ScreenshotError.noDisplays
        }
        return results
    }
}

extension ScreenshotEngine {
    static func captureDesktop() async throws -> NSImage {
        let shots = try await captureAllDisplays()
        let extent = shots.reduce(CGRect.null) { $0.union($1.screen.frame) }
        let scale = shots.map { $0.screen.backingScaleFactor }.max() ?? 1
        let width = Int(extent.width * scale), height = Int(extent.height * scale)
        guard width > 0, height > 0, width * height <= 60_000_000,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ImageError.tooLarge }
        for shot in shots {
            let frame = shot.screen.frame
            context.draw(shot.image, in: CGRect(x: (frame.minX - extent.minX) * scale, y: (frame.minY - extent.minY) * scale, width: frame.width * scale, height: frame.height * scale))
        }
        guard let image = context.makeImage() else { throw ImageError.decode }
        return NSImage(cgImage: image, size: CGSize(width: width, height: height))
    }
}
