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
    let image: CGImage   // 像素级原图（高清）
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

        var results: [DisplayShot] = []
        for display in content.displays {
            guard let screen = NSScreen.screens.first(where: {
                $0.displayID == display.displayID
            }) else { continue }

            let scale = Int(screen.backingScaleFactor)
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width * scale      // 按真实像素拍，保证清晰
            config.height = display.height * scale
            config.showsCursor = false                // 不把鼠标指针拍进去
            config.captureResolution = .best

            do {
                let cgImage = try await SCScreenshotManager.captureImage(
                    contentFilter: filter, configuration: config)
                results.append(DisplayShot(screen: screen, image: cgImage))
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
