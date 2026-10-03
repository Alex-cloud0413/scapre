//
//  ScapareApp.swift
//  Scapare
//
//  截图工具的程序入口。它是一个常驻「菜单栏」的小工具：
//  屏幕顶部菜单栏会出现一把剪刀图标，点开里面有「截图 / 退出」等菜单。
//  真正的截图逻辑放在 AppDelegate 与 CaptureController 里。
//

import SwiftUI

@main
struct ScapareApp: App {
    // 把 AppKit 的 AppDelegate 接进来，用于注册全局快捷键 ⌘S。
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 菜单栏图标改由 AppDelegate 用 NSStatusItem 创建（更稳）。
        // 这里只放一个不会显示窗口的占位场景。
        Settings {
            EmptyView()
        }
    }
}
