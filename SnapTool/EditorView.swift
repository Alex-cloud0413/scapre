//
//  EditorView.swift
//  SnapTool
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

@MainActor
final class EditorView: NSView, NSTextViewDelegate {

    // MARK: - 数据

    private var shot: DisplayShot
    private weak var controller: CaptureController?
    private var displayImage: NSImage

    private var selection: CGRect?
    private var annotations: [Annotation] = []
    private var currentAnnotation: Annotation?

    // 当前选中的标注工具；nil 表示「选区模式」(可移动/缩放选区)。
    private(set) var activeTool: AnnotationTool?
    private(set) var strokeColor: NSColor = SettingsManager.defaultStrokeColor
    private(set) var strokeWidth: CGFloat = 2
    private(set) var textFontSize: CGFloat = 14
    private(set) var textFontWeight: CGFloat = 0  // regular

    private var toolbar: EditorToolbar?
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

    init(shot: DisplayShot, controller: CaptureController) {
        self.shot = shot
        self.controller = controller
        self.displayImage = NSImage(cgImage: shot.image, size: shot.screen.frame.size)
        super.init(frame: CGRect(origin: .zero, size: shot.screen.frame.size))
        wantsLayer = true
    }

    // 切换背景为另一张历史截图（供 , / . 回溯截图历史使用）。
    func setBackground(_ newShot: DisplayShot) {
        finishTextEditing()
        shot = newShot
        displayImage = NSImage(cgImage: newShot.image, size: newShot.screen.frame.size)
        selection = nil
        annotations.removeAll()
        currentAnnotation = nil
        selectedAnnotationIndex = nil
        activeTool = nil
        hideToolbar()
        hideRGBLabel()
        needsDisplay = true
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

        guard let sel = selection else { return }

        // 3. 选区里的标注(裁剪到选区内)。
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: sel).addClip()
        for ann in annotations { ann.draw() }
        currentAnnotation?.draw()
        NSGraphicsContext.restoreGraphicsState()

        // 4. 选区边框。
        NSColor.systemBlue.setStroke()
        let border = NSBezierPath(rect: sel)
        border.lineWidth = 1.5
        border.stroke()

        // 5. 选中的文字标注：画高亮边框和缩放把手。
        if let idx = selectedAnnotationIndex, idx < annotations.count {
            let ann = annotations[idx]
            let br = ann.textBoundingRect()
            NSColor.systemBlue.withAlphaComponent(0.5).setStroke()
            let highlight = NSBezierPath(rect: br.insetBy(dx: -3, dy: -3))
            highlight.lineWidth = 1.5
            highlight.setLineDash([4, 3], count: 2, phase: 0)
            highlight.stroke()
            // 右下角缩放三角把手
            let handleCenter = CGPoint(x: br.maxX, y: br.minY)
            let handleSize: CGFloat = 7
            let handleRect = CGRect(x: handleCenter.x - handleSize, y: handleCenter.y - handleSize,
                                     width: handleSize * 2, height: handleSize * 2)
            NSColor.systemBlue.setFill()
            let handlePath = NSBezierPath(ovalIn: handleRect)
            handlePath.fill()
        }

        // 6. 尺寸标签。
        let label = "\(Int(sel.width)) × \(Int(sel.height))"
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
        let p = clamp(convert(event.locationInWindow, from: nil))
        dragStart = p
        annotationDrag = .none

        if let tool = activeTool {
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
            var ann = Annotation(tool: tool, color: strokeColor, lineWidth: strokeWidth)
            ann.start = p
            ann.end = p
            if tool == .pen { ann.points = [p] }
            currentAnnotation = ann
            dragMode = .annotating
            return
        }

        // 选区模式：先检查是否点击到已有的文字标注
        if let sel = selection {
            var hitTextIndex: Int? = nil
            for i in annotations.indices.reversed() where annotations[i].tool == .text {
                let br = annotations[i].textBoundingRect()
                if br.contains(p) {
                    hitTextIndex = i
                    break
                }
            }

            if let idx = hitTextIndex {
                // 点击到文字标注：选中它
                selectedAnnotationIndex = idx
                let ann = annotations[idx]
                if ann.textBoundingRect().maxY - p.y < 16 {  // 点击在底部附近 → 缩放文字
                    annotationDrag = .resizingText
                } else {
                    annotationDrag = .movingText
                }
                dragMode = .none
                needsDisplay = true
                return
            }

            // 没有点中文字标注，取消选中
            selectedAnnotationIndex = nil

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
            selection = rect(from: dragStart, to: p)

        case .moving:
            var newRect = selectionAtDragStart
            newRect.origin.x += p.x - dragStart.x
            newRect.origin.y += p.y - dragStart.y
            selection = clampRectIntoBounds(newRect)

        case .resizing(let h):
            selection = resized(selectionAtDragStart, handle: h, to: p)

        case .annotating:
            if currentAnnotation?.tool == .pen {
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
            annotations[idx].start.x += dx
            annotations[idx].start.y += dy
            dragStart = p
        case .resizingText:
            guard let idx = selectedAnnotationIndex, idx < annotations.count else { break }
            let dy = p.y - dragStart.y
            var newSize = annotations[idx].fontSize + dy * 0.3
            newSize = min(max(newSize, 10), 200)
            annotations[idx].fontSize = newSize
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
                selection = nil
                hideToolbar()
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
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        updateRGBLabel(at: p)
    }

    override func mouseExited(with event: NSEvent) {
        hideRGBLabel()
    }

    override func keyDown(with event: NSEvent) {
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
            controller?.cancel()
        case 36, 76: // Return / Enter
            actionCopy()
        case 43: // 逗号 , ：回到上一张截图历史
            controller?.navigateHistory(delta: -1)
        case 47: // 句号 . ：前往下一张截图历史
            controller?.navigateHistory(delta: 1)
        case 51, 117: // Delete / Backspace：删除选中的文字标注
            if let idx = selectedAnnotationIndex, idx < annotations.count {
                annotations.remove(at: idx)
                selectedAnnotationIndex = nil
                needsDisplay = true
            }
        default:
            super.keyDown(with: event)
        }
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
        case .pen: return ann.points.count > 1
        case .text: return !ann.text.isEmpty
        default: return abs(ann.end.x - ann.start.x) > 2 || abs(ann.end.y - ann.start.y) > 2
        }
    }

    // MARK: - 工具条交互（由 EditorToolbar 调用）

    func selectTool(_ tool: AnnotationTool) {
        finishTextEditing()
        selectedAnnotationIndex = nil
        activeTool = (activeTool == tool) ? nil : tool
        toolbar?.refreshToolSelection()
        layoutToolbar()
        needsDisplay = true
    }

    func setColor(_ color: NSColor) {
        strokeColor = color
        textView?.textColor = color
    }

    func setWidth(_ width: CGFloat) {
        strokeWidth = width
    }

    func setTextFontSize(_ size: CGFloat) {
        textFontSize = size
        textView?.font = NSFont.systemFont(ofSize: size, weight: NSFont.Weight(textFontWeight))
    }

    func setTextFontWeight(_ weight: CGFloat) {
        textFontWeight = weight
        textView?.font = NSFont.systemFont(ofSize: textFontSize, weight: NSFont.Weight(weight))
    }

    func undo() {
        if !annotations.isEmpty {
            annotations.removeLast()
            needsDisplay = true
        }
    }

    func actionCancel() { controller?.cancel() }

    func actionCopy() {
        guard let image = renderResult() else { return }
        controller?.copyToClipboard(image)
    }

    func actionSave() {
        guard let image = renderResult() else { return }
        controller?.saveToFile(image)
    }

    func actionPin() {
        guard let image = renderResult(), let sel = selection else { return }
        let global = CGRect(x: shot.screen.frame.minX + sel.minX,
                            y: shot.screen.frame.minY + sel.minY,
                            width: sel.width, height: sel.height)
        controller?.pin(image, at: global)
    }

    func actionOCR() {
        guard let image = renderResult() else { return }
        controller?.recognizeText(image)
    }

    // MARK: - 文字输入

    private func beginTextEditing(at point: CGPoint) {
        finishTextEditing()

        guard let sel = selection else { return }
        let availableWidth: CGFloat = sel.maxX - point.x
        let availableHeight: CGFloat = point.y - sel.minY

        let initialWidth: CGFloat = max(200, availableWidth)
        let initialHeight: CGFloat = 40
        let frame = CGRect(x: point.x, y: point.y - initialHeight,
                           width: initialWidth, height: initialHeight)

        let scroll = NSScrollView(frame: frame)
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.autoresizingMask = []
        addSubview(scroll)
        textScrollView = scroll

        let tv = NSTextView(frame: NSRect(origin: .zero, size: frame.size))
        tv.font = NSFont.systemFont(ofSize: textFontSize, weight: NSFont.Weight(textFontWeight))
        tv.textColor = strokeColor
        tv.backgroundColor = .clear
        tv.drawsBackground = false
        tv.isEditable = true
        tv.isSelectable = true
        tv.isRichText = false
        tv.isHorizontallyResizable = true
        tv.isVerticallyResizable = true
        tv.minSize = NSSize(width: 80, height: 20)
        tv.maxSize = NSSize(width: max(availableWidth, 10000), height: max(availableHeight, 10000))
        tv.autoresizingMask = []
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = false
        tv.textContainer?.heightTracksTextView = false
        tv.textContainer?.containerSize = NSSize(width: max(availableWidth, 10000), height: max(availableHeight, 10000))
        tv.delegate = self
        scroll.documentView = tv

        window?.makeFirstResponder(tv)
        textView = tv
    }

    // 每次文字变化时，让文本视图和滚动视图自动撑大以容纳全部内容，不裁剪溢出文字。
    func textDidChange(_ notification: Notification) {
        guard let tv = textView, let scroll = textScrollView else { return }
        let ideal = tv.layoutManager?.usedRect(for: tv.textContainer!) ?? .zero
        let padding: CGFloat = 12
        let newTextSize = NSSize(
            width: max(ideal.width + padding, 80),
            height: max(ideal.height + padding, 30)
        )
        tv.setFrameSize(newTextSize)
        var newOrigin = scroll.frame.origin
        let oldHeight = scroll.frame.height
        scroll.setFrameSize(newTextSize)
        if newTextSize.height != oldHeight {
            newOrigin.y -= newTextSize.height - oldHeight
            scroll.setFrameOrigin(newOrigin)
        }
    }

    private func finishTextEditing() {
        guard let tv = textView, let scroll = textScrollView else { return }
        let str = tv.string
        let origin = scroll.frame.origin
        textView = nil
        textScrollView = nil
        scroll.removeFromSuperview()
        if !str.isEmpty {
            var ann = Annotation(tool: .text, color: strokeColor, lineWidth: strokeWidth)
            ann.text = str
            ann.start = CGPoint(x: origin.x, y: origin.y + 4)
            ann.fontSize = textFontSize
            ann.fontWeight = textFontWeight
            ann.textMaxWidth = scroll.frame.width   // 记录编辑框宽度用于多行换行
            annotations.append(ann)
            // 自动选中刚创建的文字标注，方便用户直接拖动调整
            selectedAnnotationIndex = annotations.count - 1
            needsDisplay = true
        }
        window?.makeFirstResponder(self)
    }

    private func cancelTextEditing() {
        guard let scroll = textScrollView else { return }
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
        let cg = shot.image
        let scaleX = CGFloat(cg.width) / bounds.width
        let scaleY = CGFloat(cg.height) / bounds.height
        let px = Int(point.x * scaleX)
        let py = Int((bounds.height - point.y) * scaleY)  // CGImage y flipped
        guard px >= 0, py >= 0, px < cg.width, py < cg.height else { return nil }

        guard let data = cg.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }
        let bpp = cg.bitsPerPixel / 8
        let offset = py * cg.bytesPerRow + px * bpp
        guard offset + 2 < CFDataGetLength(data) else { return nil }
        let r = ptr[offset]
        let g = ptr[offset + 1]
        let b = ptr[offset + 2]
        return NSColor(red: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: 1.0)
    }

    // MARK: - 工具条显示/定位

    private func showToolbar() {
        if toolbar == nil {
            let tb = EditorToolbar(editor: self)
            addSubview(tb)
            toolbar = tb
        }
        layoutToolbar()
    }

    private func hideToolbar() {
        toolbar?.removeFromSuperview()
        toolbar = nil
    }

    private func layoutToolbar() {
        guard let tb = toolbar, let sel = selection else { return }
        let size = tb.frame.size
        var x = sel.midX - size.width / 2
        var y = sel.minY - size.height - 8          // 选区下方
        if y < 8 { y = sel.maxY + 8 }               // 下方放不下就放上方
        if y + size.height > bounds.height - 8 { y = bounds.height - size.height - 8 }
        x = max(8, min(x, bounds.width - size.width - 8))
        tb.setFrameOrigin(CGPoint(x: x, y: y))
        window?.invalidateCursorRects(for: tb)   // 刷新光标区域，让工具条上显示箭头
    }

    // MARK: - 生成最终结果图

    private func renderResult() -> NSImage? {
        finishTextEditing()
        guard let sel = selection, sel.width >= 1, sel.height >= 1 else { return nil }

        let cg = shot.image
        // 用「像素图尺寸 ÷ 视图点尺寸」算出每 1 点对应多少像素，保证裁剪精确。
        let pxScaleX = CGFloat(cg.width) / bounds.width
        let pxScaleY = CGFloat(cg.height) / bounds.height

        // CGImage 原点在左上角，y 方向要翻转。
        let cropRect = CGRect(x: sel.minX * pxScaleX,
                              y: (bounds.height - sel.maxY) * pxScaleY,
                              width: sel.width * pxScaleX,
                              height: sel.height * pxScaleY).integral
        guard let cropped = cg.cropping(to: cropRect) else { return nil }

        // 没有标注：直接返回原始像素裁剪结果，最清晰、尺寸最精确。
        if annotations.isEmpty {
            return NSImage(cgImage: cropped, size: sel.size)
        }

        // 有标注：把裁剪图与标注合成在一起。
        let croppedImage = NSImage(cgImage: cropped, size: sel.size)
        let result = NSImage(size: sel.size)
        result.lockFocus()
        croppedImage.draw(in: CGRect(origin: .zero, size: sel.size))
        let xform = NSAffineTransform()
        xform.translateX(by: -sel.minX, yBy: -sel.minY)
        xform.concat()
        for ann in annotations { ann.draw() }
        result.unlockFocus()
        return result
    }
}
