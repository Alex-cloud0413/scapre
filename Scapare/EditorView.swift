//
//  EditorView.swift
//  Scapare
//
//  截图工具的核心界面。铺在屏幕上，显示静止画面，并处理：
//    • 拖动框选区域、移动/缩放选区(8 个把手)
//    • 在选区里画标注(矩形/椭圆/箭头/画笔/文字)
//    • 底部浮动工具条上的各种操作
//    • 生成最终的结果图片(截图 + 标注合成)
//
//  坐标说明：本视图未翻转，原点在左下角，和图片绘制坐标一致。
//

import AppKit

enum EditorOutput { case copy, save, pin, ocr, barcode, share, quickSave }

@MainActor
final class EditorView: NSView, NSTextViewDelegate, NSMenuItemValidation {

    // MARK: - 数据

    var onOutput: ((EditorOutput, NSImage) -> Void)?
    var onCancel: (() -> Void)?
    var isLiveCapture = true
    private var externalToolbar = false
    private var raster: PixelRaster?
    private var hoverPoint: CGPoint?
    private var hoverWindow: CGRect?
    private var elementCandidates: [CGRect] = []
    private var lastElementQuery = Date.distantPast
    private var elementIndex = 0
    private var decoration = ImageDecoration()
    private var showMagnifier = AppearanceSettings.options.magnifierVisible
    private var fixedRatio: CGFloat?
    private var annotationStyle = Annotation(tool: .rectangle, color: .red, lineWidth: 2)
    private var selectedIndices: Set<Int> = []
    private var textReplacement: (snapshot: EditSnapshot, index: Int)?
    var editingSnapshot: EditSnapshot { finishTextEditing(); return session.snapshot }
    private var shot: DisplayShot
    private weak var controller: CaptureController?
    private var displayImage: NSImage

    private var session: EditingSession
    private var interactionStart: EditSnapshot?
    private let textUndoManager = UndoManager()
    private let historyLabel = NSTextField(labelWithString: "")
    private var selection: CGRect? {
        get { session.snapshot.selection }
        set { session.snapshot.selection = newValue }
    }
    private var annotations: [Annotation] {
        get { session.snapshot.annotations }
        set { session.snapshot.annotations = newValue }
    }
    override var undoManager: UndoManager? { session.undoManager }
    var canUndo: Bool { session.undoManager.canUndo }
    var canRedo: Bool { session.undoManager.canRedo }

    private var currentAnnotation: Annotation?

    // 当前选中的标注工具；nil 表示「选区模式」(可移动/缩放选区)。
    private(set) var activeTool: AnnotationTool?
    private(set) var strokeColor: NSColor = SettingsManager.defaultStrokeColor
    private(set) var strokeWidth: CGFloat = 2
    private(set) var textFontSize: CGFloat = AppearanceSettings.options.fontSize
    private(set) var textFontWeight: CGFloat = 0  // regular

    private var toolbar: EditorToolbar?
    private var toolbarScroll: NSScrollView?
    private var textView: NSTextView?
    private var textScrollView: NSScrollView?

    // 文字标注选择与拖动
    private var selectedAnnotationIndex: Int?
    private enum AnnotationDrag { case none, movingText, resizingText }
    private var annotationDrag: AnnotationDrag = .none

    // RGB 实时显示
    private var rgbLabel: NSTextField?

    // MARK: - 鼠标拖动状态

    private enum Handle { case tl, t, tr, r, br, b, bl, l }
    private enum DragMode { case none, creating, moving, resizing(Handle), annotating }
    private var dragMode: DragMode = .none
    private var dragStart: CGPoint = .zero
    private var selectionAtDragStart: CGRect = .zero

    // MARK: - 初始化

    init(shot: DisplayShot, controller: CaptureController, session: EditingSession, canvasSize: CGSize? = nil) {
        self.session = session
        self.shot = shot
        self.controller = controller
        self.displayImage = NSImage(cgImage: shot.image, size: canvasSize ?? shot.screen.frame.size)
        self.raster = try? PixelRaster(shot.image)
        super.init(frame: CGRect(origin: .zero, size: canvasSize ?? shot.screen.frame.size))
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("截图编辑器")
        bindSession()
        historyLabel.font = .systemFont(ofSize: 12)
        historyLabel.textColor = .white
        historyLabel.backgroundColor = .black.withAlphaComponent(0.8)
        historyLabel.drawsBackground = true
        addSubview(historyLabel)
    }

    // 切换背景为另一张历史截图（供 , / . 回溯截图历史使用）。
    func setBackground(_ newShot: DisplayShot, session newSession: EditingSession) {
        finishTextEditing()
        session.onChange = nil
        session = newSession
        shot = newShot
        displayImage = NSImage(cgImage: newShot.image, size: newShot.screen.frame.size)
        raster = try? PixelRaster(newShot.image)
        currentAnnotation = nil
        selectedAnnotationIndex = nil
        interactionStart = nil
        activeTool = nil
        hideToolbar()
        hideRGBLabel()
        bindSession()
        refreshSessionView()
    }
    func finishPendingEditing() { finishTextEditing() }
    func detachSession() { session.onChange = nil }
    private func bindSession() {
        session.onChange = { [weak self] in self?.refreshSessionView() }
    }
    private func refreshSessionView() {
        selectedAnnotationIndex = nil
        selectedIndices.removeAll()
        if selection != nil { showToolbar() } else { hideToolbar() }
        toolbar?.refreshToolSelection()
        layoutToolbar()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }
    func setHistoryStatus(_ text: String) {
        historyLabel.stringValue = "  " + text + "  "
        historyLabel.sizeToFit()
        historyLabel.setFrameOrigin(CGPoint(x: 16, y: bounds.height - historyLabel.frame.height - 16))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)

        // 添加 TrackingArea 以接收 mouseMoved（用于 RGB 显示）
        let options: NSTrackingArea.Options = [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
        guard activeTool == nil, let selection else { return }
        addCursorRect(selection, cursor: .openHand)
        for (handle, rect) in handleRects(for: selection) {
            let cursor: NSCursor
            if #available(macOS 15.0, *) {
                let position: NSCursor.FrameResizePosition
                switch handle {
                case .tl: position = .topLeft
                case .t: position = .top
                case .tr: position = .topRight
                case .r: position = .right
                case .br: position = .bottomRight
                case .b: position = .bottom
                case .bl: position = .bottomLeft
                case .l: position = .left
                }
                cursor = .frameResize(position: position, directions: [.inward, .outward])
            } else {
                cursor = [.t, .b].contains(handle) ? .resizeUpDown : .resizeLeftRight
            }
            addCursorRect(rect.insetBy(dx: -4, dy: -4).intersection(bounds), cursor: cursor)
        }
        if let i = selectedAnnotationIndex, annotations.indices.contains(i) {
            addCursorRect(PixelGeometry.textHandle(for: annotations[i].tool == .text ? annotations[i].textBoundingRect() : annotations[i].boundingRect).intersection(bounds), cursor: .crosshair)
        }
    }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        // 1. 画静止的屏幕画面。
        displayImage.draw(at: .zero, from: .zero, operation: .copy, fraction: 1.0)

        // 2. 画半透明黑色遮罩；选区位置「挖空」露出原图。
        NSColor.black.withAlphaComponent(0.45).setFill()
        let mask = NSBezierPath(rect: bounds)
        if let sel = selection {
            mask.append(NSBezierPath(rect: sel))
            mask.windingRule = .evenOdd
        }
        mask.fill()

        if selection == nil, let hoverWindow {
            AppearanceSettings.accent.setStroke()
            let outline = NSBezierPath(rect: hoverWindow); outline.lineWidth = 2; outline.stroke()
        }
        if showMagnifier, let point = hoverPoint, activeTool == nil, textView == nil { drawMagnifier(at: point) }
        guard let sel = selection else { return }

        // 3. 选区里的标注(裁剪到选区内)。
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: sel).addClip()
        for ann in annotations { ann.draw(source: shot.image, viewSize: bounds.size) }
        if let currentAnnotation, [.mosaic, .blur].contains(currentAnnotation.tool) {
            NSColor.black.setFill(); NSBezierPath(rect: currentAnnotation.normalizedRect).fill()
        } else { currentAnnotation?.draw(source: shot.image, viewSize: bounds.size) }
        NSGraphicsContext.restoreGraphicsState()

        // 4. 选区边框。
        AppearanceSettings.accent.setStroke()
        let border = NSBezierPath(rect: sel)
        border.lineWidth = 1.5
        border.stroke()
        if activeTool == nil {
            for (_, rect) in handleRects(for: sel) {
                NSColor.white.setFill()
                AppearanceSettings.accent.setStroke()
                let handle = NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2)
                handle.fill()
                handle.lineWidth = 1.5
                handle.stroke()
            }
        }

        for i in selectedIndices where annotations.indices.contains(i) && i != selectedAnnotationIndex {
            AppearanceSettings.accent.setStroke(); NSBezierPath(rect: annotations[i].boundingRect).stroke()
        }
        // 5. 选中的文字标注：画高亮边框和缩放把手。
        if let idx = selectedAnnotationIndex, idx < annotations.count {
            let ann = annotations[idx]
            let br = ann.tool == .text ? ann.textBoundingRect() : ann.boundingRect
            AppearanceSettings.accent.withAlphaComponent(0.5).setStroke()
            let highlight = NSBezierPath(rect: br.insetBy(dx: -3, dy: -3))
            highlight.lineWidth = 1.5
            highlight.setLineDash([4, 3], count: 2, phase: 0)
            highlight.stroke()
            // 右下角缩放三角把手
            let handleRect = PixelGeometry.textHandle(for: br)
            AppearanceSettings.accent.setFill()
            let handlePath = NSBezierPath(ovalIn: handleRect)
            handlePath.fill()
        }

        // 6. 尺寸标签。
        let pixelRect = PixelGeometry.cropRect(selection: sel, viewSize: bounds.size,
                                               imageSize: CGSize(width: shot.image.width, height: shot.image.height))
        let label = UserDefaults.standard.bool(forKey: "selection_in_points") ? "\(Int(sel.width)) × \(Int(sel.height)) pt · \(Int(pixelRect.width)) × \(Int(pixelRect.height)) px" : "\(Int(pixelRect.width)) × \(Int(pixelRect.height)) px"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = (label as NSString).size(withAttributes: attrs)
        var labelOrigin = CGPoint(x: sel.minX, y: sel.maxY + 6)
        if labelOrigin.y + textSize.height > bounds.height {
            labelOrigin.y = sel.maxY - textSize.height - 6
        }
        let bg = CGRect(x: labelOrigin.x, y: labelOrigin.y,
                        width: textSize.width + 10, height: textSize.height + 4)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 3, yRadius: 3).fill()
        (label as NSString).draw(at: CGPoint(x: labelOrigin.x + 5, y: labelOrigin.y + 2),
                                 withAttributes: attrs)

    }

    // MARK: - 缩放把手

    private func handleRects(for sel: CGRect) -> [(Handle, CGRect)] {
        let s: CGFloat = 9
        func r(_ x: CGFloat, _ y: CGFloat) -> CGRect {
            CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s)
        }
        return [
            (.tl, r(sel.minX, sel.maxY)), (.t, r(sel.midX, sel.maxY)), (.tr, r(sel.maxX, sel.maxY)),
            (.r,  r(sel.maxX, sel.midY)),
            (.br, r(sel.maxX, sel.minY)), (.b, r(sel.midX, sel.minY)), (.bl, r(sel.minX, sel.minY)),
            (.l,  r(sel.minX, sel.midY))
        ]
    }

    private func handleHit(at point: CGPoint, in sel: CGRect) -> Handle? {
        for (h, rect) in handleRects(for: sel) {
            if rect.insetBy(dx: -4, dy: -4).contains(point) { return h }
        }
        return nil
    }

    // MARK: - 鼠标

    override func mouseDown(with event: NSEvent) {
        finishTextEditing()
        window?.makeFirstResponder(self)
        interactionStart = session.snapshot
        let p = clamp(convert(event.locationInWindow, from: nil))
        dragStart = p
        annotationDrag = .none

        if let tool = activeTool {
            if tool == .number, selection?.contains(p) == true {
                var ann = makeAnnotation(tool); ann.start = p
                ann.number = (annotations.filter { $0.tool == .number }.map(\.number).max() ?? 0) + 1
                annotations.append(ann)
                if let old = interactionStart { session.commit(from: old) }
                interactionStart = nil; dragMode = .none; return
            }
            if tool == .polyline, selection?.contains(p) == true {
                if currentAnnotation == nil { currentAnnotation = makeAnnotation(tool); currentAnnotation?.start = p }
                currentAnnotation?.points.append(p); currentAnnotation?.end = p
                interactionStart = nil
                if event.clickCount == 2 { finishPolyline() }
                dragMode = .none; needsDisplay = true; return
            }
            // 标注模式
            if tool == .text {
                if selection?.contains(p) ?? false {
                    beginTextEditing(at: p)
                }
                dragMode = .none
                return
            }
            guard selection?.contains(p) ?? false else { dragMode = .none; return }
            selectedAnnotationIndex = nil
            var ann = makeAnnotation(tool)
            ann.start = p
            ann.end = p
            if tool == .pen || tool == .highlighter { ann.points = [p] }
            currentAnnotation = ann
            dragMode = .annotating
            return
        }

        // 选区模式：先检查是否点击到已有的文字标注
        if let sel = selection {
            if let i = selectedAnnotationIndex, annotations.indices.contains(i),
               PixelGeometry.textHandle(for: annotations[i].tool == .text ? annotations[i].textBoundingRect() : annotations[i].boundingRect).insetBy(dx: -4, dy: -4).contains(p) {
                annotationDrag = .resizingText
                dragMode = .none
                return
            }
            var hitTextIndex: Int? = nil
            for i in annotations.indices.reversed() {
                let br = annotations[i].boundingRect
                if br.contains(p) {
                    hitTextIndex = i
                    break
                }
            }

            if let idx = hitTextIndex {
                // 点击到文字标注：选中它
                if event.modifierFlags.contains(.shift) { selectedIndices.formSymmetricDifference([idx]) }
                else if !selectedIndices.contains(idx) { selectedIndices = [idx] }
                selectedAnnotationIndex = idx
                if event.clickCount == 2, annotations[idx].tool == .text {
                    editTextAnnotation(at: idx); interactionStart = nil; dragMode = .none; return
                }
                annotationDrag = .movingText
                dragMode = .none
                needsDisplay = true
                return
            }

            // 没有点中文字标注，取消选中
            selectedAnnotationIndex = nil
            selectedIndices.removeAll()

            if let h = handleHit(at: p, in: sel) {
                dragMode = .resizing(h)
                selectionAtDragStart = sel
            } else if sel.contains(p) {
                dragMode = .moving
                selectionAtDragStart = sel
            } else {
                dragMode = .creating
                selection = CGRect(origin: p, size: .zero)
                hideToolbar()
            }
        } else {
            dragMode = .creating
            selection = CGRect(origin: p, size: .zero)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let p = clamp(convert(event.locationInWindow, from: nil))

        switch dragMode {
        case .creating:
            var proposed = rect(from: dragStart, to: p)
            if let ratio = fixedRatio { proposed.size.height = proposed.width / ratio }
            selection = proposed.intersection(bounds)

        case .moving:
            var newRect = selectionAtDragStart
            newRect.origin.x += p.x - dragStart.x
            newRect.origin.y += p.y - dragStart.y
            selection = clampRectIntoBounds(newRect)

        case .resizing(let h):
            selection = resized(selectionAtDragStart, handle: h, to: p)

        case .annotating:
            if currentAnnotation?.tool == .pen || currentAnnotation?.tool == .highlighter {
                currentAnnotation?.points.append(clampIntoSelection(p))
            } else {
                currentAnnotation?.end = clampIntoSelection(p)
            }

        case .none:
            break
        }

        // 文字标注拖动
        switch annotationDrag {
        case .movingText:
            guard let idx = selectedAnnotationIndex, idx < annotations.count else { break }
            let dx = p.x - dragStart.x
            let dy = p.y - dragStart.y
            let indices = selectedIndices.isEmpty ? Set([idx]) : selectedIndices
            for i in indices where annotations.indices.contains(i) { annotations[i].translate(x: dx, y: dy) }
            dragStart = p
        case .resizingText:
            guard let idx = selectedAnnotationIndex, idx < annotations.count else { break }
            let dy = p.y - dragStart.y
            var newSize = annotations[idx].fontSize + ((p.x - dragStart.x) - dy) * 0.3
            newSize = min(max(newSize, 10), 200)
            if annotations[idx].tool == .text { annotations[idx].fontSize = newSize }
            else {
                let b = annotations[idx].boundingRect
                annotations[idx].scale(by: max(0.1, 1 + ((p.x - dragStart.x) - dy) / max(20, b.width + b.height)), around: CGPoint(x: b.minX, y: b.maxY))
            }
            dragStart = p
        case .none:
            break
        }

        updateRGBLabel(at: p)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch dragMode {
        case .creating:
            if let sel = selection, sel.width < 3 || sel.height < 3 {
                selection = hoverWindow
                if selection != nil { showToolbar() } else { hideToolbar() }
            } else {
                showToolbar()
            }
        case .moving, .resizing:
            layoutToolbar()
        case .annotating:
            if let ann = currentAnnotation, isMeaningful(ann) {
                annotations.append(ann)
            }
            currentAnnotation = nil
        case .none:
            break
        }
        dragMode = .none
        annotationDrag = .none
        // Preserve the active text selection when registering the undo action.
        let selected = selectedAnnotationIndex
        let selectedSet = selectedIndices
        if let previous = interactionStart { session.commit(from: previous) }
        selectedAnnotationIndex = selected
        selectedIndices = selectedSet
        interactionStart = nil
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        hoverPoint = p
        if currentAnnotation?.tool == .polyline { currentAnnotation?.end = clampIntoSelection(p) }
        if selection == nil, isLiveCapture {
            if let pid = shot.sourcePID, ElementPicker.enabled, Date().timeIntervalSince(lastElementQuery) > 0.12 {
                let global = CGPoint(x: shot.screen.frame.minX + p.x, y: shot.screen.frame.minY + p.y)
                elementCandidates = ElementPicker.frames(at: global, processID: pid).map { $0.offsetBy(dx: -shot.screen.frame.minX, dy: -shot.screen.frame.minY).intersection(bounds) }.filter { !$0.isNull }
                lastElementQuery = Date(); elementIndex = 0
            }
            hoverWindow = elementCandidates.first ?? shot.windows.first(where: { $0.contains(p) })
        }
        updateRGBLabel(at: p)
        needsDisplay = true
    }

    override func scrollWheel(with event: NSEvent) {
        if selection == nil, !elementCandidates.isEmpty {
            elementIndex = max(0, min(elementCandidates.count - 1, elementIndex + (event.scrollingDeltaY < 0 ? 1 : -1)))
            hoverWindow = elementCandidates[elementIndex]; needsDisplay = true
        } else { super.scrollWheel(with: event) }
    }
    override func mouseExited(with event: NSEvent) {
        hideRGBLabel()
        hoverPoint = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if handleCommand(event) { return }
        // 如果正在输入文字
        if textView != nil {
            switch event.keyCode {
            case 53: // Esc: 取消文字编辑
                cancelTextEditing()
            case 36 where event.modifierFlags.contains(.command): // Cmd+Return: 确认
                finishTextEditing()
            default:
                super.keyDown(with: event)
            }
            return
        }

        switch event.keyCode {
        case 53: // Esc
            if currentAnnotation?.tool == .polyline { currentAnnotation = nil; needsDisplay = true }
            else { actionCancel() }
        case 36, 76: // Return / Enter
            if currentAnnotation?.tool == .polyline { finishPolyline() } else { actionCopy() }
        case 123, 124, 125, 126: nudge(with: event)
        case 8: copyColor()
        case 9:
            if let sel = selection {
                let r = PixelGeometry.cropRect(selection: sel, viewSize: bounds.size, imageSize: CGSize(width: shot.image.width, height: shot.image.height))
                Clipboard.copy(text: "\(Int(r.width)) × \(Int(r.height)) px")
            }
        case 49 where selection == nil:
            if let hoverWindow { selection = hoverWindow; showToolbar(); needsDisplay = true }
        case 43: // 逗号 , ：回到上一张截图历史
            controller?.navigateHistory(delta: -1)
        case 47: // 句号 . ：前往下一张截图历史
            controller?.navigateHistory(delta: 1)
        case 51, 117: // Delete / Backspace：删除选中的文字标注
            if let idx = selectedAnnotationIndex, idx < annotations.count {
                let previous = session.snapshot
                let indices = selectedIndices.isEmpty ? Set([idx]) : selectedIndices
                annotations = annotations.enumerated().filter { !indices.contains($0.offset) }.map(\.element)
                session.commit(from: previous)
                selectedAnnotationIndex = nil
                needsDisplay = true
            }
        default:
            if event.keyCode == 48 { window?.selectNextKeyView(self) }
            else { super.keyDown(with: event) }
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        handleCommand(event) || super.performKeyEquivalent(with: event)
    }
    private func handleCommand(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags == .command || flags == [.command, .shift] else { return false }
        if textView != nil {
            if event.keyCode == 36 { finishTextEditing(); return true }
            return false // NSTextView owns typing, selection, clipboard and text undo.
        }
        let shifted = flags.contains(.shift)
        switch event.keyCode {
        case 6: shifted ? redo() : undo()
        case 8 where shifted: copyAnnotations()
        case 9 where shifted: pasteAnnotations()
        case 8 where !shifted: actionCopy()
        case 1 where !shifted: actionSave()
        case 0 where !shifted:
            let previous = session.snapshot
            selection = bounds
            session.commit(from: previous)
        case 31 where shifted: actionOCR()
        case 35 where shifted: actionPin()
        default: return false
        }
        return true
    }
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { cancelTextEditing(); return true }
        return false
    }
    func undoManager(for view: NSTextView) -> UndoManager? { textUndoManager }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, _ key: String = "", shift: Bool = false) {
            let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
            item.target = self
            item.keyEquivalentModifierMask = shift ? [.command, .shift] : .command
        }
        add("撤销", #selector(undoCommand), "z")
        add("重做", #selector(redoCommand), "z", shift: true)
        menu.addItem(.separator())
        add("复制截图", #selector(copyCommand), "c")
        add("保存截图…", #selector(saveCommand), "s")
        add("文字识别", #selector(ocrCommand), "o", shift: true)
        add("贴图", #selector(pinCommand), "p", shift: true)
        menu.addItem(.separator())
        let toolsItem = NSMenuItem(title: "标注工具", action: nil, keyEquivalent: ""), toolsMenu = NSMenu()
        for (index, tool) in AnnotationTool.allCases.enumerated() {
            let item = toolsMenu.addItem(withTitle: tool.title, action: #selector(toolCommand(_:)), keyEquivalent: "")
            item.tag = index; item.target = self; item.state = activeTool == tool ? .on : .off
        }
        toolsItem.submenu = toolsMenu; menu.addItem(toolsItem)
        menu.addItem(.separator())
        add("标注样式…", #selector(styleCommand))
        add("精确选区尺寸…", #selector(sizeCommand))
        add("固定宽高比…", #selector(ratioCommand))
        add("复制光标处颜色（C）", #selector(colorCommand))
        add("切换选区单位（像素 / 点）", #selector(unitCommand))
        add("显示/隐藏放大镜", #selector(magnifierCommand))
        add("快速保存", #selector(quickSaveCommand))
        add("复制图片为文件", #selector(copyFileCommand))
        add("圆角 / 边框 / 阴影导出…", #selector(decorationCommand))
        add("分享…", #selector(shareCommand))
        add("识别条码 / 二维码", #selector(barcodeCommand))
        if isLiveCapture { add("滚动长截图…", #selector(longCaptureCommand)); add("刷新背景", #selector(refreshCommand)) }
        add("上一张历史截图（,）", #selector(previousHistory))
        add("下一张历史截图（.）", #selector(nextHistory))
        add("取消截图（Esc）", #selector(cancelCommand))
        return menu
    }
    @objc private func undoCommand() { undo() }
    @objc private func redoCommand() { redo() }
    @objc private func copyCommand() { actionCopy() }
    @objc private func saveCommand() { actionSave() }
    @objc private func ocrCommand() { actionOCR() }
    @objc private func pinCommand() { actionPin() }
    @objc private func cancelCommand() { actionCancel() }
    @objc private func previousHistory() { controller?.navigateHistory(delta: -1) }
    @objc private func nextHistory() { controller?.navigateHistory(delta: 1) }
    // Standard AppKit Edit/File menu actions also work through the responder chain.
    @objc func undo(_ sender: Any?) { undo() }
    @objc func redo(_ sender: Any?) { redo() }
    @objc func copy(_ sender: Any?) { actionCopy() }
    @objc func saveDocument(_ sender: Any?) { actionSave() }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undo(_:)), #selector(undoCommand): return canUndo
        case #selector(redo(_:)), #selector(redoCommand): return canRedo
        case #selector(copy(_:)), #selector(copyCommand), #selector(saveDocument(_:)),
             #selector(saveCommand), #selector(ocrCommand), #selector(pinCommand):
            return selection.map { $0.width >= 1 && $0.height >= 1 } ?? false
        default: return true
        }
    }
    @objc private func toolCommand(_ item: NSMenuItem) {
        selectTool(AnnotationTool.allCases[item.tag])
    }

    // MARK: - 几何辅助

    private func clamp(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(0, p.x), bounds.width),
                y: min(max(0, p.y), bounds.height))
    }

    private func clampIntoSelection(_ p: CGPoint) -> CGPoint {
        guard let sel = selection else { return p }
        return CGPoint(x: min(max(sel.minX, p.x), sel.maxX),
                       y: min(max(sel.minY, p.y), sel.maxY))
    }

    private func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y),
               width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func clampRectIntoBounds(_ r: CGRect) -> CGRect {
        var r = r
        r.origin.x = min(max(0, r.origin.x), bounds.width - r.width)
        r.origin.y = min(max(0, r.origin.y), bounds.height - r.height)
        return r
    }

    private func resized(_ original: CGRect, handle: Handle, to p: CGPoint) -> CGRect {
        var minX = original.minX, maxX = original.maxX
        var minY = original.minY, maxY = original.maxY
        switch handle {
        case .tl: minX = p.x; maxY = p.y
        case .t:  maxY = p.y
        case .tr: maxX = p.x; maxY = p.y
        case .r:  maxX = p.x
        case .br: maxX = p.x; minY = p.y
        case .b:  minY = p.y
        case .bl: minX = p.x; minY = p.y
        case .l:  minX = p.x
        }
        return CGRect(x: min(minX, maxX), y: min(minY, maxY),
                      width: abs(maxX - minX), height: abs(maxY - minY))
    }

    private func isMeaningful(_ ann: Annotation) -> Bool {
        switch ann.tool {
        case .pen, .polyline, .highlighter: return ann.points.count > 1
        case .number: return true
        case .text: return !ann.text.isEmpty
        default: return abs(ann.end.x - ann.start.x) > 2 || abs(ann.end.y - ann.start.y) > 2
        }
    }

    // MARK: - 工具条交互（由 EditorToolbar 调用）

    func selectTool(_ tool: AnnotationTool) {
        finishTextEditing()
        selectedAnnotationIndex = nil
        selectedIndices.removeAll()
        if currentAnnotation?.tool == .polyline { finishPolyline() }
        if let activeTool { AppearanceSettings.remember(makeAnnotation(activeTool)) }
        activeTool = (activeTool == tool) ? nil : tool
        if activeTool != nil {
            if let saved = AppearanceSettings.style(for: tool) { annotationStyle = saved; strokeColor = saved.color; strokeWidth = saved.lineWidth; textFontSize = saved.fontSize; textFontWeight = saved.fontWeight }
            else { annotationStyle = Annotation(tool: tool, color: strokeColor, lineWidth: strokeWidth); annotationStyle.fontName = AppearanceSettings.options.fontName }
        }
        toolbar?.refreshToolSelection()
        layoutToolbar()
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    func setColor(_ color: NSColor) {
        strokeColor = color
        if let activeTool { AppearanceSettings.remember(makeAnnotation(activeTool)) }
        textView?.textColor = color
        toolbar?.refreshToolSelection()
        layoutToolbar()
    }

    func adjustOpacity(_ delta: CGFloat) {
        annotationStyle.opacity = max(0.05, min(1, annotationStyle.opacity + delta))
        if let activeTool { AppearanceSettings.remember(makeAnnotation(activeTool)) }
        setHistoryStatus("标注不透明度 \(Int(annotationStyle.opacity * 100))%")
    }
    func setWidth(_ width: CGFloat) {
        strokeWidth = width
        if let activeTool { AppearanceSettings.remember(makeAnnotation(activeTool)) }
    }

    func setTextFontSize(_ size: CGFloat) {
        textFontSize = size
        textView?.font = AppearanceSettings.font(size: size, weight: textFontWeight, name: annotationStyle.fontName)
    }

    func setTextFontWeight(_ weight: CGFloat) {
        textFontWeight = weight
        textView?.font = AppearanceSettings.font(size: textFontSize, weight: weight, name: annotationStyle.fontName)
    }

    func undo() {
        finishTextEditing()
        if session.undoManager.canUndo { session.undoManager.undo() }
        toolbar?.refreshToolSelection()
    }
    func redo() {
        finishTextEditing()
        if session.undoManager.canRedo { session.undoManager.redo() }
        toolbar?.refreshToolSelection()
    }

    func actionCancel() { if let onCancel { onCancel() } else { controller?.cancel() } }

    func actionCopy() {
        guard let image = renderResult() else { return }
        rememberRegion()
        if let onOutput { onOutput(.copy, image) } else { controller?.copyToClipboard(image) }
    }

    func actionSave() {
        guard let image = renderResult() else { return }
        rememberRegion()
        if let onOutput { onOutput(.save, image) } else { controller?.saveToFile(image) }
    }

    func actionPin() {
        guard let image = renderResult(), let sel = selection else { return }
        let global = CGRect(x: shot.screen.frame.minX + sel.minX,
                            y: shot.screen.frame.minY + sel.minY,
                            width: sel.width, height: sel.height)
        rememberRegion()
        if let onOutput { onOutput(.pin, image) } else { controller?.pin(image, at: global) }
    }

    func actionOCR() {
        guard let image = renderResult() else { return }
        if let onOutput { onOutput(.ocr, image) } else { controller?.recognizeText(image) }
    }

    // MARK: - 文字输入

    private func beginTextEditing(at point: CGPoint) {
        finishTextEditing()

        guard let sel = selection else { return }
        let availableWidth: CGFloat = sel.maxX - point.x
        let availableHeight: CGFloat = point.y - sel.minY

        let initialWidth: CGFloat = max(20, availableWidth)
        let initialHeight: CGFloat = max(20, min(40, availableHeight))
        let frame = CGRect(x: point.x, y: point.y - initialHeight,
                           width: initialWidth, height: initialHeight)

        let scroll = NSScrollView(frame: frame)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autoresizingMask = []
        addSubview(scroll)
        textScrollView = scroll

        let tv = NSTextView(frame: NSRect(origin: .zero, size: frame.size))
        tv.font = AppearanceSettings.font(size: textFontSize, weight: textFontWeight, name: annotationStyle.fontName)
        tv.textColor = strokeColor
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.allowsUndo = true
        textUndoManager.removeAllActions()
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.minSize = NSSize(width: initialWidth, height: 20)
        tv.maxSize = NSSize(width: initialWidth, height: 30000)
        tv.textContainerInset = .zero
        tv.autoresizingMask = []
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.heightTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: initialWidth, height: 30000)
        tv.delegate = self
        scroll.documentView = tv

        window?.makeFirstResponder(tv)
        textView = tv
    }

    // 每次文字变化时，让文本视图和滚动视图自动撑大以容纳全部内容，不裁剪溢出文字。
    func textDidChange(_ notification: Notification) {
        guard let tv = textView, let scroll = textScrollView else { return }
        let ideal = tv.layoutManager?.usedRect(for: tv.textContainer!) ?? .zero
        let top = scroll.frame.maxY
        let contentHeight = max(30, ideal.height)
        tv.setFrameSize(CGSize(width: scroll.frame.width, height: contentHeight))
        let visibleHeight = min(contentHeight, max(20, top - (selection?.minY ?? 0)))
        scroll.frame = CGRect(x: scroll.frame.minX, y: top - visibleHeight, width: scroll.frame.width, height: visibleHeight)
    }

    private func finishTextEditing() {
        guard let tv = textView, let scroll = textScrollView else { return }
        let str = tv.string
        let origin = scroll.frame.origin
        let replacement = textReplacement
        textReplacement = nil
        textView = nil
        textScrollView = nil
        scroll.removeFromSuperview()
        if !str.isEmpty {
            let previous = replacement?.snapshot ?? session.snapshot
            var ann = makeAnnotation(.text)
            ann.text = str
            ann.start = CGPoint(x: origin.x, y: origin.y)
            ann.fontSize = textFontSize
            ann.fontWeight = textFontWeight
            ann.textMaxWidth = scroll.frame.width
            ann.start.y = scroll.frame.maxY - ann.textBoundingRect().height
            if let replacement { annotations.insert(ann, at: min(replacement.index, annotations.count)) }
            else { annotations.append(ann) }
            session.commit(from: previous)
            // 自动选中刚创建的文字标注，方便用户直接拖动调整
            selectedAnnotationIndex = annotations.count - 1
            needsDisplay = true
        }
        if str.isEmpty, let replacement { session.commit(from: replacement.snapshot) }
        window?.makeFirstResponder(self)
    }

    private func cancelTextEditing() {
        guard let scroll = textScrollView else { return }
        if let replacement = textReplacement { session.snapshot = replacement.snapshot; textReplacement = nil; needsDisplay = true }
        textView = nil
        textScrollView = nil
        scroll.removeFromSuperview()
        window?.makeFirstResponder(self)
    }

    // MARK: - RGB 实时显示

    private func ensureRGBLabel() {
        guard rgbLabel == nil else { return }
        let label = NSTextField()
        label.isBezeled = false
        label.drawsBackground = true
        label.backgroundColor = NSColor.black.withAlphaComponent(0.75)
        label.textColor = .white
        label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.isEditable = false
        label.isSelectable = false
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.cornerRadius = 5
        label.isHidden = true
        addSubview(label)
        rgbLabel = label
    }

    private func updateRGBLabel(at point: CGPoint) {
        ensureRGBLabel()
        guard let label = rgbLabel else { return }
        guard point.x >= 0, point.y >= 0, point.x < bounds.width, point.y < bounds.height else {
            label.isHidden = true
            return
        }
        guard let color = getPixelColor(at: point) else {
            label.isHidden = true
            return
        }

        let r = Int(round(color.redComponent * 255))
        let g = Int(round(color.greenComponent * 255))
        let b = Int(round(color.blueComponent * 255))
        let hex = String(format: "#%02X%02X%02X", r, g, b)

        label.stringValue = "R:\(r) G:\(g) B:\(b) \(hex)"
        label.sizeToFit()
        let w = label.frame.width + 10
        let h: CGFloat = 22
        let offset: CGFloat = 16
        var lx = point.x + offset
        var ly = point.y + offset
        if lx + w > bounds.width { lx = point.x - w - offset }
        if ly + h > bounds.height { ly = point.y - h - offset }
        label.frame = CGRect(x: lx, y: ly, width: w, height: h)
        label.isHidden = false
    }

    private func hideRGBLabel() {
        rgbLabel?.isHidden = true
    }

    private func getPixelColor(at point: CGPoint) -> NSColor? {
        guard let raster else { return nil }
        let x = min(raster.width - 1, max(0, Int(point.x * CGFloat(raster.width) / bounds.width)))
        let y = min(raster.height - 1, max(0, Int((bounds.height - point.y) * CGFloat(raster.height) / bounds.height)))
        guard let (r, g, b) = raster.color(x: x, y: y) else { return nil }
        return NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    // MARK: - 工具条显示/定位

    private func showToolbar() {
        if toolbar == nil {
            let tb = EditorToolbar(editor: self)
            let container = NSScrollView()
            container.documentView = tb; container.hasHorizontalScroller = true; container.autohidesScrollers = true; container.drawsBackground = false
            addSubview(container); toolbarScroll = container
            toolbar = tb
        }
        layoutToolbar()
    }

    private func hideToolbar() {
        guard !externalToolbar else { return }
        toolbarScroll?.removeFromSuperview(); toolbarScroll = nil
        toolbar?.removeFromSuperview()
        toolbar = nil
    }

    private func layoutToolbar() {
        guard !externalToolbar, let tb = toolbar, let sel = selection else { return }
        let width = min(tb.frame.width, max(100, bounds.width - 16))
        let size = CGSize(width: width, height: tb.frame.height + (width < tb.frame.width ? 14 : 0))
        var x = sel.midX - size.width / 2
        var y = sel.minY - size.height - 8          // 选区下方
        if y < 8 { y = sel.maxY + 8 }               // 下方放不下就放上方
        if y + size.height > bounds.height - 8 { y = bounds.height - size.height - 8 }
        x = max(8, min(x, bounds.width - size.width - 8))
        toolbarScroll?.frame = CGRect(x: x, y: y, width: size.width, height: size.height)
        tb.setFrameOrigin(.zero)
        window?.invalidateCursorRects(for: tb)   // 刷新光标区域，让工具条上显示箭头
    }

    // MARK: - 生成最终结果图

    func renderResult() -> NSImage? {
        finishTextEditing()
        guard let sel = selection, sel.width >= 1, sel.height >= 1 else { return nil }

        guard let image = ScreenshotRenderer.render(image: shot.image, selection: sel,
                                                     viewSize: bounds.size, annotations: annotations) else { return nil }
        guard let decorated = decoration.apply(image) else { AppDialogs.error("图片过大，无法添加边框效果。"); return nil }
        return NSImage(cgImage: decorated, size: CGSize(width: decorated.width, height: decorated.height))
    }
    func installExternalToolbar(_ toolbar: EditorToolbar) {
        toolbarScroll?.removeFromSuperview(); toolbarScroll = nil
        self.toolbar?.removeFromSuperview(); self.toolbar = toolbar; externalToolbar = true
        historyLabel.isHidden = true
    }
    func setSelection(_ rect: CGRect) {
        selection = rect.intersection(bounds); refreshSessionView()
    }
    func replaceBackground(_ image: CGImage) {
        shot = DisplayShot(screen: shot.screen, image: image, windows: shot.windows)
        displayImage = NSImage(cgImage: image, size: bounds.size); raster = try? PixelRaster(image); needsDisplay = true
    }
    private func makeAnnotation(_ tool: AnnotationTool) -> Annotation {
        var ann = annotationStyle; ann.tool = tool; ann.color = strokeColor; ann.lineWidth = strokeWidth
        ann.fontSize = textFontSize; ann.fontWeight = textFontWeight; return ann
    }
    private func finishPolyline() {
        guard let ann = currentAnnotation, ann.points.count >= 2 else { currentAnnotation = nil; return }
        let previous = session.snapshot; annotations.append(ann); currentAnnotation = nil; session.commit(from: previous)
    }
    private func editTextAnnotation(at index: Int) {
        let original = session.snapshot, ann = annotations[index]
        annotations.remove(at: index)
        annotationStyle = ann; strokeColor = ann.color; textFontSize = ann.fontSize; textFontWeight = ann.fontWeight
        beginTextEditing(at: CGPoint(x: ann.start.x, y: ann.start.y + ann.textBoundingRect().height))
        textReplacement = (original, index); textView?.string = ann.text
        textDidChange(Notification(name: NSText.didChangeNotification))
    }
    private func nudge(with event: NSEvent) {
        guard var rect = selection else {
            guard isLiveCapture else { return }
            let amount = (event.modifierFlags.contains(.option) ? 10.0 : 1.0) / shot.screen.backingScaleFactor
            var point = hoverPoint ?? CGPoint(x: bounds.midX, y: bounds.midY)
            if event.keyCode == 123 { point.x -= amount }; if event.keyCode == 124 { point.x += amount }
            if event.keyCode == 125 { point.y -= amount }; if event.keyCode == 126 { point.y += amount }
            point.x = max(0, min(bounds.width - amount, point.x)); point.y = max(0, min(bounds.height - amount, point.y))
            let global = CGPoint(x: shot.screen.frame.minX + point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - shot.screen.frame.minY - point.y)
            // Native cursor movement is performed only for a user's arrow-key action
            // while the capture surface owns keyboard focus.
            CGWarpMouseCursorPosition(global); hoverPoint = point; updateRGBLabel(at: point); needsDisplay = true
            return
        }
        let pixel = bounds.width / CGFloat(shot.image.width)
        let step: CGFloat = event.modifierFlags.contains(.option) ? pixel * 10 : pixel
        let dx: CGFloat = event.keyCode == 123 ? -step : (event.keyCode == 124 ? step : 0)
        let dy: CGFloat = event.keyCode == 125 ? -step : (event.keyCode == 126 ? step : 0)
        let previous = session.snapshot
        if !selectedIndices.isEmpty {
            for i in selectedIndices where annotations.indices.contains(i) { annotations[i].translate(x: dx, y: dy) }
        } else if event.modifierFlags.contains(.shift) {
            rect.size.width = max(pixel, min(bounds.maxX - rect.minX, rect.width + dx))
            rect.size.height = max(pixel, min(bounds.maxY - rect.minY, rect.height + dy)); selection = rect
        } else { rect.origin.x += dx; rect.origin.y += dy; selection = clampRectIntoBounds(rect) }
        let selected = selectedIndices, primary = selectedAnnotationIndex
        session.commit(from: previous); selectedIndices = selected; selectedAnnotationIndex = primary
    }
    private func copyColor() {
        if let p = hoverPoint, let c = getPixelColor(at: p) { Clipboard.copy(text: "#" + c.hexString); setHistoryStatus("已复制 #" + c.hexString) }
    }
    private func drawMagnifier(at point: CGPoint) {
        let options = AppearanceSettings.options
        let side: CGFloat = options.magnifierSize
        var box = CGRect(x: point.x + 22, y: point.y - side - 22, width: side, height: side)
        box.origin.x = max(4, min(box.minX, bounds.width - side - 4)); box.origin.y = max(4, min(box.minY, bounds.height - side - 4))
        let sample = CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16).intersection(bounds)
        let pixels = PixelGeometry.cropRect(selection: sample, viewSize: bounds.size, imageSize: CGSize(width: shot.image.width, height: shot.image.height))
        if let image = shot.image.cropping(to: pixels) {
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current?.imageInterpolation = .none
            let shape = options.magnifierRound ? NSBezierPath(ovalIn: box) : NSBezierPath(rect: box)
            shape.addClip(); NSImage(cgImage: image, size: box.size).draw(in: box); NSGraphicsContext.restoreGraphicsState()
            NSColor.labelColor.setStroke(); shape.stroke()
            guard options.magnifierCrosshair else { return }
            let cross = NSBezierPath(); cross.move(to: CGPoint(x: box.midX - 5, y: box.midY)); cross.line(to: CGPoint(x: box.midX + 5, y: box.midY))
            cross.move(to: CGPoint(x: box.midX, y: box.midY - 5)); cross.line(to: CGPoint(x: box.midX, y: box.midY + 5)); NSColor.systemRed.setStroke(); cross.stroke()
        }
    }
    private func rememberRegion() {
        guard isLiveCapture, let selection, let id = shot.screen.displayID else { return }
        SettingsManager.rememberRegion(selection, displayID: id)
    }
    func actionLongCapture() {
        guard isLiveCapture else { return }
        guard let selection, selection.width >= 32, selection.height >= 64 else {
            setHistoryStatus("选区太小，无法滚动截图。请扩大到至少 32 × 64 点，并避开固定页眉。")
            return
        }
        finishPendingEditing()
        controller?.startLongCapture(on: shot.screen, selection: selection)
    }
    func actionBarcode() { guard let image = renderResult() else { return }; OCRResultController.present(image: image, barcode: true) }
    func actionQuickSave() { guard let image = renderResult() else { return }; if ImageFileSaver.quickSave(image) { setHistoryStatus("已快速保存") } }
    func actionShare() {
        guard let image = renderResult() else { return }
        NSSharingServicePicker(items: [image]).show(relativeTo: toolbarScroll?.frame ?? visibleRect, of: self, preferredEdge: .minY)
    }
    func showStyleOptions() {
        let initial = selectedAnnotationIndex.flatMap { annotations.indices.contains($0) ? annotations[$0] : nil } ?? makeAnnotation(activeTool ?? .rectangle)
        guard let changed = AnnotationInspector.edit(initial) else { return }
        AppearanceSettings.remember(changed)
        annotationStyle = changed; strokeColor = changed.color; strokeWidth = changed.lineWidth; textFontSize = changed.fontSize; textFontWeight = changed.fontWeight
        if let i = selectedAnnotationIndex, annotations.indices.contains(i) {
            let previous = session.snapshot
            let indices = selectedIndices.isEmpty ? Set([i]) : selectedIndices
            for index in indices where annotations.indices.contains(index) {
                var value = changed; value.tool = annotations[index].tool; value.start = annotations[index].start
                value.end = annotations[index].end; value.points = annotations[index].points; value.text = annotations[index].text
                value.number = annotations[index].number; value.textMaxWidth = annotations[index].textMaxWidth; annotations[index] = value
            }
            session.commit(from: previous)
        }
        toolbar?.refreshToolSelection(); needsDisplay = true
    }
    private func copyAnnotations() {
        let values = selectedIndices.sorted().compactMap { annotations.indices.contains($0) ? annotations[$0] : nil }
        guard !values.isEmpty, let data = try? JSONEncoder().encode(values) else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setData(data, forType: .init("com.gaoyiming.Scapare.annotations"))
    }
    private func pasteAnnotations() {
        guard let data = NSPasteboard.general.data(forType: .init("com.gaoyiming.Scapare.annotations")), data.count < 10_000_000,
              var values = try? JSONDecoder().decode([Annotation].self, from: data), values.count <= 1000, values.allSatisfy(\.isValid) else { return }
        let previous = session.snapshot
        for i in values.indices { values[i].translate(x: 10, y: -10) }
        annotations += values; session.commit(from: previous)
    }
    @objc private func styleCommand() { showStyleOptions() }
    @objc private func colorCommand() { copyColor() }
    @objc private func magnifierCommand() { showMagnifier.toggle(); needsDisplay = true }
    @objc private func longCaptureCommand() { actionLongCapture() }
    @objc private func barcodeCommand() { actionBarcode() }
    @objc private func quickSaveCommand() { actionQuickSave() }
    @objc private func shareCommand() { actionShare() }
    @objc private func refreshCommand() { controller?.refreshCapture() }
    @objc private func copyFileCommand() { if let image = renderResult() { ImageFileSaver.copyAsFile(image) } }
    @objc private func decorationCommand() {
        guard let values = AppDialogs.fields(title: "导出效果（像素，选区尺寸不含边框）", labels: ["圆角", "边框", "阴影（0 关 / 1 开）"], values: [String(Int(decoration.cornerRadius)), String(Int(decoration.borderWidth)), decoration.shadow ? "1" : "0"]),
              let radius = Double(values[0]), let border = Double(values[1]), radius.isFinite, border.isFinite,
              (0...500).contains(radius), (0...100).contains(border), ["0", "1"].contains(values[2]) else { return }
        decoration = ImageDecoration(cornerRadius: radius, borderWidth: border, shadow: values[2] == "1")
        setHistoryStatus("导出效果已设置：内容尺寸不含边框与阴影留白")
    }
    @objc private func unitCommand() { UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: "selection_in_points"), forKey: "selection_in_points"); needsDisplay = true }
    @objc private func sizeCommand() {
        let current = selection ?? bounds
        let scale = UserDefaults.standard.bool(forKey: "selection_in_points") ? 1 : CGFloat(shot.image.width) / bounds.width
        let unit = UserDefaults.standard.bool(forKey: "selection_in_points") ? "点" : "像素"
        guard let values = AppDialogs.fields(title: "精确选区（\(unit)，左上角为原点）", labels: ["X", "Y", "宽度", "高度"], values: [String(Int(current.minX * scale)), String(Int((bounds.height - current.maxY) * scale)), String(Int(current.width * scale)), String(Int(current.height * scale))]),
              let x = Double(values[0]), let y = Double(values[1]), let w = Double(values[2]), let h = Double(values[3]), [x, y, w, h].allSatisfy({ $0.isFinite && abs($0) <= 100_000 }), w > 0, h > 0 else { return }
        let previous = session.snapshot
        selection = clampRectIntoBounds(CGRect(x: x / scale, y: bounds.height - (y + h) / scale, width: min(bounds.width, w / scale), height: min(bounds.height, h / scale)))
        session.commit(from: previous)
    }
    @objc private func ratioCommand() {
        guard let values = AppDialogs.fields(title: "固定宽高比（0 为自由）", labels: ["宽", "高"], values: ["0", "0"]),
              let w = Double(values[0]), let h = Double(values[1]), w.isFinite, h.isFinite else { return }
        fixedRatio = w > 0 && h > 0 ? w / h : nil
    }
}
