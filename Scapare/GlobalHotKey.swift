//
//  GlobalHotKey.swift
//  Scapare
//
//  用 macOS 底层的 Carbon 接口注册「全局快捷键」。
//  「全局」的意思是：不管你正在用哪个 App，按下这个键都会触发我们的截图。
//  这是 macOS 上注册全局热键最稳妥的方式。
//

import AppKit
import Carbon.HIToolbox

final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private let myID: UInt32

    // 所有热键的回调集中存在这里，按 id 区分。用 nonisolated(unsafe) 是因为
    // 它会被底层 C 回调访问；我们保证全部在主线程使用，所以是安全的。
    nonisolated(unsafe) private static var handlers: [UInt32: () -> Void] = [:]
    nonisolated(unsafe) private static var nextID: UInt32 = 1
    nonisolated(unsafe) private static var installed = false

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) throws {
        myID = Self.nextID
        Self.nextID += 1
        try Self.installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: OSType(0x534E5054), id: myID) // 'SNPT'
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, ref != nil else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "这个快捷键无法注册，可能已被其他 App 占用。请换一个组合键。原有快捷键保持不变。"] )
        }
        hotKeyRef = ref
        Self.handlers[myID] = handler
    }

    deinit {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
        }
        Self.handlers[myID] = nil
    }

    // 安装一个统一的事件处理器，负责接收「热键被按下」的系统事件并分发。
    private static func installHandlerIfNeeded() throws {
        guard !installed else { return }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))

        let status = InstallEventHandler(GetApplicationEventTarget(), { (_, event, _) -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event,
                              EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID),
                              nil,
                              MemoryLayout<EventHotKeyID>.size,
                              nil,
                              &hkID)
            let id = hkID.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    GlobalHotKey.fire(id: id)
                }
            }
            return noErr
        }, 1, &spec, nil, nil)
        guard status == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        installed = true
    }

    @MainActor
    private static func fire(id: UInt32) {
        handlers[id]?()
    }
}
