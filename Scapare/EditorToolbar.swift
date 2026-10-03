//
//  EditorToolbar.swift
//  Scapare
//
//  选区下方的浮动工具条。从左到右：
//    标注工具(矩形/椭圆/箭头/画笔/文字) | 颜色 | 粗细 | 撤销 | 文字识别/钉图/保存/复制/取消
//

import AppKit

// 用于 hex 面板的 associated object keys
private var hexPanelKey: UInt8 = 0
private var hexTextFieldKey: UInt8 = 0

@MainActor
final class EditorToolbar: NSView {
    private weak var editor: EditorView?
    private var toolButtons: [(tool: AnnotationTool, button: NSButton)] = []
    private var hexColorButton: NSButton?
    private var fontSettingsButton: NSButton?
    private var fontPopover: NSPopover?
    private let colorPopup = NSPopUpButton()
    private var undoButton: NSButton?
    private var redoButton: NSButton?
    private let colorNames = ["深红", "红色", "橙色", "黄色", "绿色", "蓝色", "紫色", "白色", "黑色"]

    private let colors: [NSColor] = [
        NSColor(red: 0.8, green: 0, blue: 0, alpha: 1.0),           // 深红 #CC0000（默认）
        NSColor(red: 1.0, green: 0.23, blue: 0.19, alpha: 1.0),      // 红 #FF3B30
        NSColor(red: 1.0, green: 0.58, blue: 0, alpha: 1.0),         // 橙 #FF9500
        NSColor(red: 1.0, green: 0.8, blue: 0, alpha: 1.0),          // 黄 #FFCC00
        NSColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1.0),      // 绿 #34C759
        NSColor(red: 0, green: 0.48, blue: 1.0, alpha: 1.0),         // 蓝 #007AFF
        NSColor(red: 0.69, green: 0.32, blue: 0.87, alpha: 1.0),     // 紫 #AF52DE
        .white,
        .black,
    ]
    private let widths: [CGFloat] = [2, 4, 8]
    private let fontWeights: [CGFloat] = [-0.6, 0, 0.4]      // thin, regular, bold
    private let fontSizes: [CGFloat] = [12, 14, 18, 24, 36, 48]

    init(editor: EditorView) {
        self.editor = editor
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.cornerRadius = 9
        buildUI()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // 工具条上的点击不应被当成「点在选区外」，自己消化掉。
    override func hitTest(_ point: NSPoint) -> NSView? {
        let v = super.hitTest(point)
        return v == self ? self : v
    }
    override func mouseDown(with event: NSEvent) { /* 吞掉，避免穿透到底层视图 */ }

    // 鼠标移到工具条上时恢复成正常的箭头(而不是截图用的十字)。
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
    }

    private func buildUI() {
        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])

        // 标注工具
        addTool(to: stack, tool: .rectangle, symbol: "rectangle", tip: "矩形")
        addTool(to: stack, tool: .ellipse, symbol: "circle", tip: "椭圆")
        addTool(to: stack, tool: .arrow, symbol: "arrow.up.right", tip: "箭头")
        addTool(to: stack, tool: .pen, symbol: "pencil.tip", tip: "画笔")
        addTool(to: stack, tool: .text, symbol: "textformat", tip: "文字")

        stack.addArrangedSubview(separator())

        // 颜色
        colorPopup.addItems(withTitles: zip(colorNames, colors).map { "\($0) #\($1.hexString)" })
        colorPopup.addItem(withTitle: "自定义颜色")
        colorPopup.target = self
        colorPopup.action = #selector(colorChanged(_:))
        colorPopup.setAccessibilityLabel("标注颜色")
        colorPopup.toolTip = "标注颜色"
        stack.addArrangedSubview(colorPopup)

        // 自定义十六进制颜色按钮
        addHexColorButton(to: stack)

        stack.addArrangedSubview(separator())

        // 粗细
        let seg = NSSegmentedControl(labels: ["细", "中", "粗"],
                                     trackingMode: .selectOne,
                                     target: self, action: #selector(widthChanged(_:)))
        seg.selectedSegment = widths.firstIndex(of: editor?.strokeWidth ?? 2) ?? 0
        seg.setAccessibilityLabel("线条粗细")
        stack.addArrangedSubview(seg)

        // 文字样式下拉按钮（仅文字工具激活时显示）
        let fontBtn = NSButton()
        fontBtn.image = NSImage(systemSymbolName: "character.textbox", accessibilityDescription: "文字样式")
        fontBtn.imageScaling = .scaleProportionallyDown
        fontBtn.isBordered = false
        fontBtn.bezelStyle = .regularSquare
        fontBtn.title = ""
        fontBtn.toolTip = "文字样式"
        fontBtn.target = self
        fontBtn.action = #selector(fontSettingsTapped)
        fontBtn.contentTintColor = .labelColor
        fontBtn.setAccessibilityLabel("文字样式")
        fontBtn.wantsLayer = true
        fontBtn.layer?.cornerRadius = 5
        fontBtn.isHidden = true
        fontBtn.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            fontBtn.widthAnchor.constraint(equalToConstant: 30),
            fontBtn.heightAnchor.constraint(equalToConstant: 28),
        ])
        fontSettingsButton = fontBtn
        stack.addArrangedSubview(fontBtn)

        stack.addArrangedSubview(separator())

        // 撤销
        let undo = actionButton(symbol: "arrow.uturn.backward", tip: "撤销（⌘Z）", action: #selector(undoTapped))
        let redo = actionButton(symbol: "arrow.uturn.forward", tip: "重做（⇧⌘Z）", action: #selector(redoTapped))
        undoButton = undo
        redoButton = redo
        stack.addArrangedSubview(undo)
        stack.addArrangedSubview(redo)

        stack.addArrangedSubview(separator())

        // 主要操作（统一白色，简约风格）
        stack.addArrangedSubview(actionButton(symbol: "text.viewfinder", tip: "文字识别(OCR)", action: #selector(ocrTapped)))
        stack.addArrangedSubview(actionButton(symbol: "pin.fill", tip: "钉在屏幕上", action: #selector(pinTapped)))
        stack.addArrangedSubview(actionButton(symbol: "square.and.arrow.down", tip: "保存为图片（⌘S）", action: #selector(saveTapped)))
        stack.addArrangedSubview(actionButton(symbol: "doc.on.doc", tip: "复制到剪贴板（⌘C）", action: #selector(copyTapped)))
        stack.addArrangedSubview(actionButton(symbol: "xmark", tip: "取消(Esc)", action: #selector(cancelTapped)))

        // 根据内容自动确定工具条大小。
        layoutSubtreeIfNeeded()
        setFrameSize(fittingSize)
        refreshToolSelection()
    }

    // MARK: - 控件构造

    private func addTool(to stack: NSStackView, tool: AnnotationTool, symbol: String, tip: String) {
        let b = actionButton(symbol: symbol, tip: tip, action: #selector(toolTapped(_:)))
        b.tag = toolButtons.count
        b.setButtonType(.pushOnPushOff)
        b.isBordered = true
        toolButtons.append((tool, b))
        stack.addArrangedSubview(b)
    }

    private func actionButton(symbol: String, tip: String, action: Selector, tint: NSColor = .labelColor) -> NSButton {
        let b = NSButton()
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        b.imageScaling = .scaleProportionallyDown
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.title = ""
        b.toolTip = tip
        b.setAccessibilityLabel(tip)
        b.focusRingType = .default
        b.target = self
        b.action = action
        b.contentTintColor = tint
        b.wantsLayer = true
        b.layer?.cornerRadius = 5
        b.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            b.widthAnchor.constraint(equalToConstant: 30),
            b.heightAnchor.constraint(equalToConstant: 28),
        ])
        return b
    }

    private func separator() -> NSView {
        let v = NSView()
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.separatorColor.cgColor
        v.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            v.widthAnchor.constraint(equalToConstant: 1),
            v.heightAnchor.constraint(equalToConstant: 22),
        ])
        return v
    }

    // MARK: - 自定义十六进制颜色按钮

    private func addHexColorButton(to stack: NSStackView) {
        let b = NSButton()
        b.title = "#"
        b.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold)
        b.isBordered = false
        b.bezelStyle = .regularSquare
        b.toolTip = "自定义颜色（输入十六进制值）"
        b.setAccessibilityLabel("自定义颜色")
        b.target = self
        b.action = #selector(hexColorTapped)
        b.wantsLayer = true
        b.layer?.cornerRadius = 9
        b.layer?.borderColor = NSColor.white.withAlphaComponent(0.6).cgColor
        b.layer?.borderWidth = 1
        b.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            b.widthAnchor.constraint(equalToConstant: 30),
            b.heightAnchor.constraint(equalToConstant: 28),
        ])
        hexColorButton = b
        refreshHexColorButton()
        stack.addArrangedSubview(b)
    }

    private func refreshHexColorButton() {
        guard let b = hexColorButton else { return }
        if let hex = SettingsManager.customColorHex, let color = NSColor(hex: hex) {
            b.layer?.backgroundColor = color.cgColor
            // 根据颜色深浅选白色或黑色文字
            let isDark: Bool = {
                guard let rgb = color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB)
                else { return true }
                let luminance = 0.299 * rgb.redComponent + 0.587 * rgb.greenComponent + 0.114 * rgb.blueComponent
                return luminance < 0.5
            }()
            b.contentTintColor = isDark ? .white : .black
        } else {
            b.layer?.backgroundColor = NSColor(white: 0.3, alpha: 1.0).cgColor
            b.contentTintColor = .white
        }
    }

    // MARK: - 高亮当前工具

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.borderColor = NSColor.separatorColor.cgColor
        refreshToolSelection()
    }
    func refreshToolSelection() {
        for (tool, button) in toolButtons {
            let active = editor?.activeTool == tool
            button.state = active ? .on : .off
            button.setAccessibilityValue(active ? "已选择" : "未选择")
            button.layer?.borderWidth = active ? 2 : 0
            button.layer?.borderColor = NSColor.labelColor.cgColor
        }
        if let color = editor?.strokeColor, colorPopup.numberOfItems > 0 {
            if let index = colors.firstIndex(where: { $0.hexString == color.hexString }) {
                colorPopup.selectItem(at: index)
            } else {
                colorPopup.item(at: colors.count)?.title = "自定义 #\(color.hexString)"
                colorPopup.selectItem(at: colors.count)
            }
            colorPopup.setAccessibilityValue("#" + color.hexString)
        }
        undoButton?.isEnabled = editor?.canUndo ?? false
        redoButton?.isEnabled = editor?.canRedo ?? false
        fontSettingsButton?.isHidden = editor?.activeTool != .text
        layoutSubtreeIfNeeded()
        setFrameSize(fittingSize)
    }

    // MARK: - 动作

    @objc private func toolTapped(_ sender: NSButton) {
        let tool = toolButtons[sender.tag].tool
        editor?.selectTool(tool)
    }
    @objc private func colorChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        if colors.indices.contains(index) { editor?.setColor(colors[index]) }
        else { refreshToolSelection(); presentHexColorPanel() }
    }
    @objc private func widthChanged(_ sender: NSSegmentedControl) {
        editor?.setWidth(widths[sender.selectedSegment])
    }
    @objc private func undoTapped() { editor?.undo() }
    @objc private func redoTapped() { editor?.redo() }
    @objc private func ocrTapped() { editor?.actionOCR() }
    @objc private func pinTapped() { editor?.actionPin() }
    @objc private func saveTapped() { editor?.actionSave() }
    @objc private func copyTapped() { editor?.actionCopy() }
    @objc private func cancelTapped() { editor?.actionCancel() }

    @objc private func fontSettingsTapped() {
        fontPopover?.close()
        guard let editor = editor, let button = fontSettingsButton else { return }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 200, height: 90)

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 90))

        // 字重标签
        let weightLabel = NSTextField(labelWithString: "字重")
        weightLabel.font = NSFont.systemFont(ofSize: 11)
        weightLabel.textColor = .secondaryLabelColor
        weightLabel.frame = NSRect(x: 16, y: 56, width: 34, height: 16)
        contentView.addSubview(weightLabel)

        // 字重下拉
        let weightPopup = NSPopUpButton(frame: NSRect(x: 52, y: 52, width: 130, height: 22))
        weightPopup.addItems(withTitles: ["细", "常规", "粗"])
        let currentWeightIndex = editor.textFontWeight == 0.4 ? 2 : (editor.textFontWeight == 0 ? 1 : 0)
        weightPopup.selectItem(at: currentWeightIndex)
        weightPopup.target = self
        weightPopup.action = #selector(popoverWeightChanged(_:))
        contentView.addSubview(weightPopup)

        // 字号标签
        let sizeLabel = NSTextField(labelWithString: "字号")
        sizeLabel.font = NSFont.systemFont(ofSize: 11)
        sizeLabel.textColor = .secondaryLabelColor
        sizeLabel.frame = NSRect(x: 16, y: 18, width: 34, height: 16)
        contentView.addSubview(sizeLabel)

        // 字号下拉
        let sizePopup = NSPopUpButton(frame: NSRect(x: 52, y: 14, width: 130, height: 22))
        sizePopup.addItems(withTitles: ["12", "14", "18", "24", "36", "48"])
        if let idx = fontSizes.firstIndex(of: editor.textFontSize) {
            sizePopup.selectItem(at: idx)
        } else {
            sizePopup.selectItem(at: 0)
        }
        sizePopup.target = self
        sizePopup.action = #selector(popoverSizeChanged(_:))
        contentView.addSubview(sizePopup)

        popover.contentViewController = {
            let vc = NSViewController()
            vc.view = contentView
            return vc
        }()

        fontPopover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .maxY)
    }

    @objc private func popoverWeightChanged(_ sender: NSPopUpButton) {
        editor?.setTextFontWeight(fontWeights[sender.indexOfSelectedItem])
    }

    @objc private func popoverSizeChanged(_ sender: NSPopUpButton) {
        editor?.setTextFontSize(fontSizes[sender.indexOfSelectedItem])
    }

    @objc private func hexColorTapped() {
        presentHexColorPanel()
    }

    private func presentHexColorPanel() {
        guard let editor = editor, let editorWindow = editor.window else { return }

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 100),
                            styleMask: [.titled, .closable],
                            backing: .buffered,
                            defer: false)
        panel.title = "自定义颜色"
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        panel.isReleasedWhenClosed = false

        let textField = NSTextField(frame: NSRect(x: 16, y: 52, width: 228, height: 24))
        textField.placeholderString = "CC0000"
        if let savedHex = SettingsManager.customColorHex {
            textField.stringValue = savedHex
        }
        panel.contentView?.addSubview(textField)

        let hint = NSTextField(labelWithString: "输入十六进制颜色值（如 CC0000 或 #FF00FF）")
        hint.font = NSFont.systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 16, y: 32, width: 228, height: 14)
        panel.contentView?.addSubview(hint)

        let okButton = NSButton(frame: NSRect(x: 164, y: 8, width: 80, height: 22))
        okButton.title = "确定"
        okButton.bezelStyle = .rounded
        okButton.keyEquivalent = "\r"

        let cancelButton = NSButton(frame: NSRect(x: 80, y: 8, width: 80, height: 22))
        cancelButton.title = "取消"
        cancelButton.bezelStyle = .rounded

        panel.contentView?.addSubview(okButton)
        panel.contentView?.addSubview(cancelButton)

        // 定位到 editorWindow 中央
        let editorFrame = editorWindow.frame
        let panelOrigin = CGPoint(x: editorFrame.midX - 130, y: editorFrame.midY - 50)
        panel.setFrameOrigin(panelOrigin)

        okButton.target = self
        okButton.action = #selector(hexPanelOKTapped(_:))
        cancelButton.target = self
        cancelButton.action = #selector(hexPanelCancelTapped(_:))

        // 把 panel 和 textField 关联起来以便回调中获取
        objc_setAssociatedObject(okButton, &hexPanelKey, panel, .OBJC_ASSOCIATION_ASSIGN)
        objc_setAssociatedObject(okButton, &hexTextFieldKey, textField, .OBJC_ASSOCIATION_ASSIGN)
        objc_setAssociatedObject(cancelButton, &hexPanelKey, panel, .OBJC_ASSOCIATION_ASSIGN)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func hexPanelOKTapped(_ sender: NSButton) {
        guard let panel = objc_getAssociatedObject(sender, &hexPanelKey) as? NSPanel,
              let textField = objc_getAssociatedObject(sender, &hexTextFieldKey) as? NSTextField else { return }
        let input = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let hex = input.hasPrefix("#") ? String(input.dropFirst()) : input
        guard hex.count == 6, let _ = UInt32(hex, radix: 16),
              let color = NSColor(hex: hex) else {
            let err = NSAlert()
            err.messageText = "无效的颜色值"
            err.informativeText = "请输入六位十六进制值，如 CC0000 或 #FF00FF"
            err.addButton(withTitle: "好的")
            err.beginSheetModal(for: panel)
            return
        }
        SettingsManager.customColorHex = hex
        editor?.setColor(color)
        refreshHexColorButton()
        panel.close()
    }

    @objc private func hexPanelCancelTapped(_ sender: NSButton) {
        guard let panel = objc_getAssociatedObject(sender, &hexPanelKey) as? NSPanel else { return }
        panel.close()
    }
}
