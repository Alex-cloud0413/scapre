import AppKit

struct AppearanceOptions: Codable, Equatable {
    var theme = 0 // system, light, dark
    var accent = ""
    var fontName = "" // system font when empty
    var fontSize: Double = 14
    var controlsSize: Double = 13
    var spaciousToolbar = false
    var statusSymbol = "scissors"
    var statusClick = 0 // menu, capture, paste
    var magnifierSize: Double = 96
    var magnifierRound = false
    var magnifierCrosshair = true
    var magnifierVisible = true
    var pinOpacity: Double = 1
    var palette = ["CC0000", "FF3B30", "FF9500", "FFCC00", "34C759", "007AFF", "AF52DE", "FFFFFF", "000000"]
    var isValid: Bool {
        (0...2).contains(theme) && (0...2).contains(statusClick)
        && (accent.isEmpty || NSColor(hex: accent) != nil) && fontName.count < 200
        && [fontSize, controlsSize, magnifierSize, pinOpacity].allSatisfy(\.isFinite)
        && (6...100).contains(fontSize) && (11...18).contains(controlsSize)
        && (64...200).contains(magnifierSize) && (0.1...1).contains(pinOpacity)
        && ["scissors", "camera", "viewfinder", "crop"].contains(statusSymbol)
        && (1...32).contains(palette.count) && palette.allSatisfy { NSColor(hex: $0) != nil }
    }
}
enum AppearanceSettings {
    static let changed = Notification.Name("ScapareAppearanceChanged")
    static var options: AppearanceOptions {
        guard let data = UserDefaults.standard.data(forKey: "appearance_v1"), let result = try? JSONDecoder().decode(AppearanceOptions.self, from: data), result.isValid else { return AppearanceOptions() }
        return result
    }
    static var accent: NSColor { NSColor(hex: options.accent) ?? .controlAccentColor }
    static func save(_ options: AppearanceOptions) throws {
        guard options.isValid, options.fontName.isEmpty || NSFont(name: options.fontName, size: options.fontSize) != nil else { throw AutomationError.invalid("外观设置包含无效的颜色、字体、尺寸或透明度。") }
        UserDefaults.standard.set(try JSONEncoder().encode(options), forKey: "appearance_v1")
        applyTheme(); NotificationCenter.default.post(name: changed, object: nil)
    }
    static func applyTheme() { NSApp.appearance = options.theme == 1 ? NSAppearance(named: .aqua) : options.theme == 2 ? NSAppearance(named: .darkAqua) : nil }
    static func font(size: CGFloat, weight: CGFloat = 0, name: String? = nil) -> NSFont {
        NSFont(name: name ?? options.fontName, size: size) ?? .systemFont(ofSize: size, weight: NSFont.Weight(weight))
    }
    static func style(for tool: AnnotationTool) -> Annotation? {
        guard let data = UserDefaults.standard.data(forKey: "style_" + tool.rawValue), let value = try? JSONDecoder().decode(Annotation.self, from: data), value.isValid else { return nil }; return value
    }
    static func remember(_ annotation: Annotation) {
        var style = annotation; style.start = .zero; style.end = .zero; style.points = []; style.text = ""; style.textMaxWidth = nil; style.number = 1
        guard style.isValid, let data = try? JSONEncoder().encode(style) else { return }
        UserDefaults.standard.set(data, forKey: "style_" + style.tool.rawValue)
    }
}

final class AppearanceWindow: NSObject, NSWindowDelegate {
    private static var current: AppearanceWindow?
    private let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 560, height: 640), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    private var fields: [String: NSTextField] = [:]
    private var checks: [String: NSButton] = [:]
    private var popups: [String: NSPopUpButton] = [:]
    private let status = NSTextField(wrappingLabelWithString: "外观立即应用；工具条布局和放大镜设置在下一次截图生效。每种标注工具会分别记住样式。")
    static func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let current { current.window.makeKeyAndOrderFront(nil); return }
        let instance = AppearanceWindow(); current = instance; instance.window.center(); instance.window.makeKeyAndOrderFront(nil)
    }
    private override init() {
        super.init(); window.title = "外观与调色板 · Scapare"; window.delegate = self; window.isReleasedWhenClosed = false; window.minSize = CGSize(width: 560, height: 420)
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 12
        func field(_ key: String, _ title: String) {
            let input = NSTextField(); input.widthAnchor.constraint(equalToConstant: 280).isActive = true; input.setAccessibilityLabel(title); fields[key] = input
            stack.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: title), input]))
        }
        func popup(_ key: String, _ title: String, _ items: [String]) {
            let menu = NSPopUpButton(); menu.addItems(withTitles: items); menu.setAccessibilityLabel(title); popups[key] = menu
            stack.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: title), menu]))
        }
        func check(_ key: String, _ title: String) { let control = NSButton(checkboxWithTitle: title, target: nil, action: nil); checks[key] = control; stack.addArrangedSubview(control) }
        popup("theme", "主题", ["跟随系统", "浅色", "深色"])
        field("accent", "选区强调色 #（留空跟随系统）")
        field("fontName", "标注字体名称（留空为系统）")
        field("fontSize", "默认标注字号")
        field("controls", "工具条字号（11–18）")
        popup("icon", "菜单栏图标", ["剪刀", "相机", "取景框", "裁剪"])
        popup("click", "菜单栏左键", ["打开菜单", "立即截图", "贴出剪贴板"])
        field("magnifier", "放大镜大小（64–200）")
        field("opacity", "新贴图不透明度 %")
        field("palette", "调色板 #（逗号分隔，可排序）")
        stack.addArrangedSubview(NSButton(title: "拖动排列色板…", target: self, action: #selector(reorderPalette)))
        check("spacious", "宽松工具条间距")
        check("round", "圆形放大镜")
        check("crosshair", "放大镜显示十字线")
        check("visible", "默认显示放大镜")
        status.textColor = .secondaryLabelColor; status.font = .systemFont(ofSize: 12); status.widthAnchor.constraint(equalToConstant: 490).isActive = true; stack.addArrangedSubview(status)
        let controls = NSStackView(views: [NSButton(title: "应用", target: self, action: #selector(apply)), NSButton(title: "导出配置…", target: self, action: #selector(exportOptions)), NSButton(title: "导入配置…", target: self, action: #selector(importOptions)), NSButton(title: "恢复默认", target: self, action: #selector(reset))]); stack.addArrangedSubview(controls)
        stack.layoutSubtreeIfNeeded(); stack.frame = CGRect(origin: CGPoint(x: 20, y: 20), size: stack.fittingSize)
        let document = NSView(frame: CGRect(x: 0, y: 0, width: 540, height: stack.frame.height + 40)); document.addSubview(stack)
        let scroll = NSScrollView(frame: window.contentView!.bounds); scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true; scroll.documentView = document; window.contentView?.addSubview(scroll)
        scroll.contentView.scroll(to: CGPoint(x: 0, y: max(0, document.frame.height - scroll.contentSize.height)))
        load(AppearanceSettings.options)
    }
    private func load(_ options: AppearanceOptions) {
        fields["accent"]?.stringValue = options.accent; fields["fontName"]?.stringValue = options.fontName
        fields["fontSize"]?.stringValue = String(options.fontSize); fields["controls"]?.stringValue = String(options.controlsSize)
        fields["magnifier"]?.stringValue = String(Int(options.magnifierSize)); fields["opacity"]?.stringValue = String(Int(options.pinOpacity * 100))
        fields["palette"]?.stringValue = options.palette.joined(separator: ", ")
        popups["theme"]?.selectItem(at: options.theme); popups["click"]?.selectItem(at: options.statusClick)
        popups["icon"]?.selectItem(at: ["scissors", "camera", "viewfinder", "crop"].firstIndex(of: options.statusSymbol) ?? 0)
        for (key, value) in [("spacious", options.spaciousToolbar), ("round", options.magnifierRound), ("crosshair", options.magnifierCrosshair), ("visible", options.magnifierVisible)] { checks[key]?.state = value ? .on : .off }
    }
    private func selectedOptions() throws -> AppearanceOptions {
        var value = AppearanceSettings.options
        func text(_ key: String) -> String { fields[key]?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }
        guard let font = Double(text("fontSize")), let controls = Double(text("controls")), let magnifier = Double(text("magnifier")), let opacity = Double(text("opacity")) else { throw AutomationError.invalid("请输入有效的字号、放大镜大小和透明度。") }
        value.theme = popups["theme"]!.indexOfSelectedItem; value.statusClick = popups["click"]!.indexOfSelectedItem; value.statusSymbol = ["scissors", "camera", "viewfinder", "crop"][popups["icon"]!.indexOfSelectedItem]
        value.accent = text("accent"); value.fontName = text("fontName"); value.fontSize = font; value.controlsSize = controls; value.magnifierSize = magnifier; value.pinOpacity = opacity / 100
        value.palette = text("palette").components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        value.spaciousToolbar = checks["spacious"]?.state == .on; value.magnifierRound = checks["round"]?.state == .on; value.magnifierCrosshair = checks["crosshair"]?.state == .on; value.magnifierVisible = checks["visible"]?.state == .on
        guard value.isValid else { throw AutomationError.invalid("请检查颜色、范围和调色板（1–32 个六位色值）。") }; return value
    }
    @objc private func reorderPalette() {
        do {
            let options = try selectedOptions()
            if let values = PaletteOrder.edit(options.palette) { fields["palette"]?.stringValue = values.joined(separator: ", ") }
        } catch { status.stringValue = error.localizedDescription }
    }
    @objc private func apply() { do { try AppearanceSettings.save(selectedOptions()); status.stringValue = "已保存。下次截图将使用新的工具条与放大镜。" } catch { status.stringValue = error.localizedDescription } }
    @objc private func reset() { load(AppearanceOptions()); apply() }
    @objc private func exportOptions() {
        do {
            let options = try selectedOptions(); let panel = NSSavePanel(); panel.nameFieldStringValue = "Scapare 外观.json"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(options).write(to: url, options: .atomic)
        } catch { status.stringValue = error.localizedDescription }
    }
    @objc private func importOptions() {
        let panel = NSOpenPanel(); guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) < 50_000 else { throw ImageError.tooLarge }
            let options = try JSONDecoder().decode(AppearanceOptions.self, from: Data(contentsOf: url)); try AppearanceSettings.save(options); load(options); status.stringValue = "外观配置已导入。"
        } catch { status.stringValue = error.localizedDescription }
    }
    func windowWillClose(_ notification: Notification) { Self.current = nil }
}
