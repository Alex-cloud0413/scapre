import AppKit

enum AppDialogs {
    static func fields(title: String, labels: [String], values: [String]) -> [String]? {
        let alert = NSAlert(); alert.messageText = title
        let view = NSStackView(); view.orientation = .vertical; view.alignment = .leading; view.spacing = 8
        var inputs: [NSTextField] = []
        for (label, value) in zip(labels, values) {
            let field = NSTextField(string: value); field.setAccessibilityLabel(label)
            field.widthAnchor.constraint(equalToConstant: 240).isActive = true
            let row = NSStackView(views: [NSTextField(labelWithString: label), field]); row.spacing = 12
            view.addArrangedSubview(row); inputs.append(field)
        }
        view.layoutSubtreeIfNeeded(); view.setFrameSize(view.fittingSize)
        alert.accessoryView = view; alert.addButton(withTitle: "确定"); alert.addButton(withTitle: "取消")
        alert.window.level = NSApp.keyWindow?.level ?? .normal
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return inputs.map(\.stringValue)
    }
    static func error(_ message: String) {
        let alert = NSAlert(); alert.messageText = "操作未完成"; alert.informativeText = message
        alert.window.level = NSApp.keyWindow?.level ?? .normal
        alert.runModal()
    }
}

enum AnnotationInspector {
    static func edit(_ initial: Annotation) -> Annotation? {
        let alert = NSAlert(); alert.messageText = "标注样式"
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        var fields: [NSTextField] = []
        let labels = ["颜色 #", "线宽", "字号", "不透明度 %", "旋转角度", "圆角半径", "文字背景 #（留空为透明）", "文字描边宽度", "描边色 #", "字体名称（留空为系统）", "箭头样式（0 线 / 1 三角 / 2 圆点）"]
        let values = [initial.color.hexString, String(Double(initial.lineWidth)), String(Double(initial.fontSize)), String(Int(initial.opacity * 100)), String(Double(initial.rotation)), String(Double(initial.cornerRadius)), initial.textBackground ?? "", String(Double(initial.textOutline)), initial.textOutlineColor ?? "FFFFFF", initial.fontName ?? "", String(initial.arrowStyle ?? 0)]
        for (label, value) in zip(labels, values) {
            let input = NSTextField(string: value); input.setAccessibilityLabel(label); input.widthAnchor.constraint(equalToConstant: 120).isActive = true
            stack.addArrangedSubview(NSStackView(views: [NSTextField(labelWithString: label), input])); fields.append(input)
        }
        let flags = ["虚线", "填充形状", "双向箭头", "椭圆遮罩（马赛克 / 模糊 / 橡皮擦）"].map { NSButton(checkboxWithTitle: $0, target: nil, action: nil) }
        for (button, on) in zip(flags, [initial.dashed, initial.filled, initial.doubleArrow, initial.ellipticalMask]) { button.state = on ? .on : .off; stack.addArrangedSubview(button) }
        stack.layoutSubtreeIfNeeded(); stack.setFrameSize(stack.fittingSize); alert.accessoryView = stack
        alert.addButton(withTitle: "应用"); alert.addButton(withTitle: "取消"); alert.window.level = NSApp.keyWindow?.level ?? .normal
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let v = fields.map { $0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let color = NSColor(hex: v[0]), let width = Double(v[1]), let font = Double(v[2]), let opacity = Double(v[3]),
              let rotation = Double(v[4]), let radius = Double(v[5]), let outline = Double(v[7]),
              [width, font, opacity, rotation, radius, outline].allSatisfy(\.isFinite),
              (0.5...100).contains(width), (6...300).contains(font), (1...100).contains(opacity),
              (0...200).contains(radius), (0...20).contains(outline), v[6].isEmpty || NSColor(hex: v[6]) != nil,
              ["0", "1", "2"].contains(v[10]), NSColor(hex: v[8]) != nil, v[9].isEmpty || NSFont(name: v[9], size: font) != nil else {
            AppDialogs.error("请输入有效色值、线宽（0.5–100）、字号（6–300）和不透明度（1–100）。"); return nil
        }
        var ann = initial; ann.color = color; ann.lineWidth = width; ann.fontSize = font; ann.opacity = opacity / 100
        ann.rotation = rotation.truncatingRemainder(dividingBy: 360); ann.cornerRadius = radius; ann.textBackground = v[6].isEmpty ? nil : v[6]; ann.textOutline = outline
        ann.arrowStyle = Int(v[10]); ann.textOutlineColor = v[8]; ann.fontName = v[9]
        ann.dashed = flags[0].state == .on; ann.filled = flags[1].state == .on; ann.doubleArrow = flags[2].state == .on; ann.ellipticalMask = flags[3].state == .on
        return ann
    }
}

extension Annotation {
    mutating func scale(by factor: CGFloat, around anchor: CGPoint) {
        func convert(_ p: CGPoint) -> CGPoint { CGPoint(x: anchor.x + (p.x - anchor.x) * factor, y: anchor.y + (p.y - anchor.y) * factor) }
        start = convert(start); end = convert(end); points = points.map(convert)
        fontSize = max(6, min(300, fontSize * factor)); if let width = textMaxWidth { textMaxWidth = max(1, width * factor) }
    }
}
