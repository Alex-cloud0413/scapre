//
//  Overlay.swift
//  Scapare
//
//  截图时铺满整块屏幕的「遮罩窗口」。它显示刚拍下来的静止画面，
//  你在上面框选、标注。每块屏幕一个这样的窗口。
//

import AppKit

// 普通的无边框窗口默认无法成为「键盘焦点」窗口，导致收不到键盘事件(比如 Esc)。
// 这里重写一下让它可以接收键鼠。
final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class OverlayController {
    let window: KeyableWindow
    let editor: EditorView
    let screen: NSScreen

    init(shot: DisplayShot, controller: CaptureController) {
        screen = shot.screen
        let frame = shot.screen.frame

        editor = EditorView(shot: shot, controller: controller)
        editor.frame = CGRect(origin: .zero, size: frame.size)

        window = KeyableWindow(contentRect: frame,
                               styleMask: .borderless,
                               backing: .buffered,
                               defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.contentView = editor
        // 盖在所有东西之上，包括菜单栏和 Dock。
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        window.orderOut(nil)
    }
}
