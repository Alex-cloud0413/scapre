//
//  SettingsManager.swift
//  Scapare
//
//  通过 UserDefaults 持久化用户偏好设置（快捷键等）。
//  首次启动无记录时给出默认值（⌘E）。
//

import AppKit
import Carbon.HIToolbox

@MainActor
enum SettingsManager {
    private static let kKeyCode = "shortcut_keyCode"
    private static let kModifiers = "shortcut_modifiers"
    private static let kHasSet = "shortcut_hasSet"
    private static let kSetupCompleted = "setup_completed"
    private static let kCustomColor = "custom_color_hex"

    // 默认快捷键 ⌘E
    static let defaultKeyCode: UInt32 = UInt32(kVK_ANSI_E)
    static let defaultModifiers: UInt32 = UInt32(cmdKey)

    static var keyCode: UInt32 {
        get { UInt32(UserDefaults.standard.integer(forKey: kKeyCode)) }
        set { UserDefaults.standard.set(newValue, forKey: kKeyCode) }
    }
    static var modifiers: UInt32 {
        get { UInt32(UserDefaults.standard.integer(forKey: kModifiers)) }
        set { UserDefaults.standard.set(newValue, forKey: kModifiers) }
    }
    static var hasSetShortcut: Bool {
        get { UserDefaults.standard.bool(forKey: kHasSet) }
        set { UserDefaults.standard.set(newValue, forKey: kHasSet) }
    }

    static var setupCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: kSetupCompleted) }
        set { UserDefaults.standard.set(newValue, forKey: kSetupCompleted) }
    }

    // Migrate existing users without losing their saved shortcut.
    // 首次启动时确保有默认值。
    static func initializeDefaults(in defaults: UserDefaults = .standard) {
        if defaults.object(forKey: kSetupCompleted) == nil {
            defaults.set(defaults.bool(forKey: kHasSet), forKey: kSetupCompleted)
        }
        if !defaults.bool(forKey: kHasSet) {
            defaults.set(defaultKeyCode, forKey: kKeyCode)
            defaults.set(defaultModifiers, forKey: kModifiers)
            // 不设 hasSetShortcut = true，让首次引导弹窗触发
        }
    }

    // 保存自定义快捷键并标记已设置过。
    static func save(keyCode: UInt32, modifiers: UInt32, in defaults: UserDefaults = .standard) {
        defaults.set(keyCode, forKey: kKeyCode)
        defaults.set(modifiers, forKey: kModifiers)
        defaults.set(true, forKey: kHasSet)
    }

    // MARK: - 自定义颜色

    static var customColorHex: String? {
        get { UserDefaults.standard.string(forKey: kCustomColor) }
        set { UserDefaults.standard.set(newValue, forKey: kCustomColor) }
    }

    /// 默认标注色：如果用户设置过自定义颜色则用它，否则用深红 #CC0000
    static var defaultStrokeColor: NSColor {
        if let hex = customColorHex, let color = NSColor(hex: hex) {
            return color
        }
        return NSColor(red: 0.8, green: 0, blue: 0, alpha: 1.0) // 深红 #CC0000
    }

    // MARK: - 可读显示

    /// Carbon modifier → 显示符号
    static func modifierSymbols(_ mods: UInt32) -> String {
        var s = ""
        if mods & UInt32(controlKey) != 0 { s += "⌃" }
        if mods & UInt32(optionKey)  != 0 { s += "⌥" }
        if mods & UInt32(shiftKey)   != 0 { s += "⇧" }
        if mods & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s
    }

    /// 键码 → 显示名称（覆盖常用键）
    static func keyDisplayName(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case 0x00: return "A"; case 0x01: return "S"; case 0x02: return "D"
        case 0x03: return "F"; case 0x04: return "H"; case 0x05: return "G"
        case 0x06: return "Z"; case 0x07: return "X"; case 0x08: return "C"
        case 0x09: return "V"; case 0x0B: return "B"; case 0x0C: return "Q"
        case 0x0D: return "W"; case 0x0E: return "E"; case 0x0F: return "R"
        case 0x10: return "Y"; case 0x11: return "T"; case 0x12: return "1"
        case 0x13: return "2"; case 0x14: return "3"; case 0x15: return "4"
        case 0x16: return "6"; case 0x17: return "5"; case 0x18: return "="
        case 0x19: return "9"; case 0x1A: return "7"; case 0x1B: return "-"
        case 0x1C: return "8"; case 0x1D: return "0"; case 0x1E: return "]"
        case 0x1F: return "O"; case 0x20: return "U"; case 0x21: return "["
        case 0x22: return "I"; case 0x23: return "P"; case 0x25: return "L"
        case 0x26: return "J"; case 0x27: return "'"; case 0x28: return "K"
        case 0x29: return ";"; case 0x2A: return "\\"; case 0x2B: return ","
        case 0x2C: return "/"; case 0x2D: return "N"; case 0x2E: return "M"
        case 0x2F: return "."; case 0x31: return " "; case 0x32: return "`"
        case 0x41: return "↹";  // tab
        case 0x33: return "⌫"; // delete
        case 0x24: return "↩"; // return
        case 0x30: return "⇥"; case 0x35: return "⎋"; // esc
        case 122: return "F1";  case 120: return "F2"
        case 99:  return "F3";  case 118: return "F4"
        case 96:  return "F5";  case 97:  return "F6"
        case 98:  return "F7";  case 100: return "F8"
        case 101: return "F9";  case 109: return "F10"
        case 103: return "F11"; case 111: return "F12"
        default:  return "🔑\(keyCode)"
        }
    }

    /// 组合快捷键的可读字符串，如 "⌘S"、"⌘⇧A"、"F1"
    static func shortcutDisplayString(keyCode: UInt32, modifiers: UInt32) -> String {
        let mods = modifierSymbols(modifiers)
        let key = keyDisplayName(keyCode)
        return mods + key
    }

    static var currentShortcutString: String {
        shortcutDisplayString(keyCode: keyCode, modifiers: modifiers)
    }

    // MARK: - 键盘事件捕获辅助

    /// 从 NSEvent 中提取 keyCode 和 Carbon 风格的 modifiers。
    static func extract(from event: NSEvent) -> (keyCode: UInt32, modifiers: UInt32) {
        var mods: UInt32 = 0
        let f = event.modifierFlags
        if f.contains(.command) { mods |= UInt32(cmdKey) }
        if f.contains(.shift)   { mods |= UInt32(shiftKey) }
        if f.contains(.option)  { mods |= UInt32(optionKey) }
        if f.contains(.control) { mods |= UInt32(controlKey) }
        return (UInt32(event.keyCode), mods)
    }
}
