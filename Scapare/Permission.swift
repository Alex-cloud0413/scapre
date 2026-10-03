//
//  Permission.swift
//  Scapare
//
//  截图需要系统的「屏幕录制」权限。第一次用、或被关掉时，
//  这里弹个提示，并可一键打开「系统设置」的对应页面。
//

import AppKit

enum PermissionHelper {
    static func showScreenRecordingHint() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "需要「屏幕录制」权限"
        alert.informativeText = """
        Scapare 需要「屏幕录制」权限才能截图。

        请点击下面的「打开系统设置」，在
        隐私与安全性 → 屏幕录制 里，
        把 Scapare 的开关打开，然后重新打开本 App 即可。
        """
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")

        if alert.runModal() == .alertFirstButtonReturn {
            let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
