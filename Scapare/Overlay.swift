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
final class KeyableWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayController {
    let window: KeyableWindow
    let editor: EditorView
    let screen: NSScreen

    init(shot: DisplayShot, controller: CaptureController, session: EditingSession) {
        screen = shot.screen
        let frame = shot.screen.frame

        editor = EditorView(shot: shot, controller: controller, session: session)
        editor.frame = CGRect(origin: .zero, size: frame.size)

        window = KeyableWindow(contentRect: frame,
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered,
                               defer: false)
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.animationBehavior = .none
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.contentView = editor
        // 盖在所有东西之上，包括菜单栏和 Dock。
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
    }

    func show() {
        // Paint the frozen desktop before revealing it. Only the screen under the
        // pointer takes keyboard focus; displaying the other screens must not
        // activate the app or briefly reveal an empty backing surface.
        editor.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        window.orderFrontRegardless()
    }

    func close() {
        window.orderOut(nil)
    }
}
