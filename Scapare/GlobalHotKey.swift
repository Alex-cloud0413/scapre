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
    private let keyCode: UInt32
    private let modifiers: UInt32
    private class WeakReference { weak var value: GlobalHotKey?; init(_ value: GlobalHotKey) { self.value = value } }
    private static var instances: [WeakReference] = []
    private static var suspended = false
    static var lastResumeError: String?

    // 所有热键的回调集中存在这里，按 id 区分。用 nonisolated(unsafe) 是因为
    // 它会被底层 C 回调访问；我们保证全部在主线程使用，所以是安全的。
    nonisolated(unsafe) private static var handlers: [UInt32: () -> Void] = [:]
    nonisolated(unsafe) private static var nextID: UInt32 = 1
    nonisolated(unsafe) private static var installed = false

    init(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) throws {
        self.keyCode = keyCode; self.modifiers = modifiers
        guard !Self.instances.contains(where: { $0.value?.keyCode == keyCode && $0.value?.modifiers == modifiers }) else {
            throw NSError(domain: "Scapare.Shortcut", code: 1, userInfo: [NSLocalizedDescriptionKey: "这个快捷键已分配给 Scapare 的另一个操作。"])
        }
        myID = Self.nextID
        Self.nextID += 1
        try Self.installHandlerIfNeeded()

        try resume()
        Self.handlers[myID] = handler
        Self.instances.removeAll { $0.value == nil }
        Self.instances.append(WeakReference(self))
        if Self.suspended { pause() }
    }
    private func resume() throws {
        guard hotKeyRef == nil else { return }
        let hotKeyID = EventHotKeyID(signature: OSType(0x534E5054), id: myID)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, ref != nil else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: "快捷键无法注册，可能被其他 App 占用。请换一个组合键。"])
        }
        hotKeyRef = ref
    }
    private func pause() { if let ref = hotKeyRef { UnregisterEventHotKey(ref); hotKeyRef = nil } }
    static func pauseAll() { suspended = true; instances.forEach { $0.value?.pause() } }
    static func resumeAll() {
        suspended = false; lastResumeError = nil
        for entry in instances { do { try entry.value?.resume() } catch { lastResumeError = error.localizedDescription } }
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
