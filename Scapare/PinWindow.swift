import AppKit
import ImageIO

final class PinWindowController: NSObject, NSWindowDelegate {
    private(set) var record: PinRecord
    let window: PinWindow
    private let pinView: PinView
    var onChange: (() -> Void)?
    private var displayImage: NSImage?
    private var fullFrame: CGRect?
    private var gifSource: CGImageSource?
    private var gifTask: Task<Void, Never>?
    private var gifFrame = 0
    private var gifPaused = false
    private var gifSpeed: Double = 1
    var currentImage: NSImage? { displayImage }
    init(record: PinRecord) {
        self.record = record
        self.fullFrame = record.normalFrame
        pinView = PinView()
        window = PinWindow(contentRect: record.frame, styleMask: .borderless, backing: .buffered, defer: false)
        super.init()
        window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = true; window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; window.delegate = self
        window.contentView = pinView; pinView.controller = self
        gifSource = CGImageSourceCreateWithData(record.imageData as CFData, nil)
        refresh(); startGIF()
    }
    func refresh() {
        guard let source = gifSource, let base = CGImageSourceCreateImageAtIndex(source, min(gifFrame, CGImageSourceGetCount(source) - 1), nil) else { return }
        let size = CGSize(width: base.width, height: base.height)
        let rendered: CGImage
        if let snapshot = record.snapshot, let rect = snapshot.selection,
           let image = ScreenshotRenderer.render(image: base, selection: rect, viewSize: size, annotations: snapshot.annotations) { rendered = image }
        else { rendered = base }
        let transformed = (try? ImageTransform.apply(rendered, quarterTurns: record.quarterTurns, flipHorizontal: record.flipHorizontal, flipVertical: record.flipVertical)) ?? rendered
        let image = ImageEffects.colorTransform(transformed, grayscale: record.grayscale, inverted: record.inverted) ?? transformed
        displayImage = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
        window.alphaValue = record.opacity; window.level = record.topmost ? .floating : .normal
        pinView.needsDisplay = true
    }
    func showIfVisible() {
        guard !record.hidden else { return }
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(window.frame) }), let screen = NSScreen.main {
            window.setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - window.frame.width / 2, y: screen.visibleFrame.midY - window.frame.height / 2))
        }
        window.orderFrontRegardless()
    }
    func setHidden(_ hidden: Bool) { record.hidden = hidden; hidden ? window.orderOut(nil) : showIfVisible(); onChange?() }
    func setClickThrough(_ value: Bool) { window.ignoresMouseEvents = value }
    func dispose() { gifTask?.cancel(); gifTask = nil; window.orderOut(nil) }
    func windowDidMove(_ notification: Notification) { record.frame = window.frame; onChange?() }
    func windowDidResize(_ notification: Notification) { record.frame = window.frame; onChange?() }
    func zoom(_ factor: CGFloat) {
        let old = window.frame, ratio = old.width / max(1, old.height)
        let width = min(6000, 6000 * ratio, max(40, old.width * max(0.1, factor))), height = width / ratio
        window.setFrame(CGRect(x: old.midX - width / 2, y: old.midY - height / 2, width: width, height: height), display: true)
    }
    func opacity(_ value: Double) { record.opacity = max(0.1, min(1, value)); window.alphaValue = record.opacity; onChange?() }
    func rotate(_ steps: Int) {
        record.quarterTurns = (record.quarterTurns + steps + 4) % 4
        let old = window.frame
        window.setFrame(CGRect(x: old.midX - old.height / 2, y: old.midY - old.width / 2, width: old.height, height: old.width), display: true)
        refresh(); onChange?()
    }
    func flip(horizontal: Bool) { if horizontal { record.flipHorizontal.toggle() } else { record.flipVertical.toggle() }; refresh(); onChange?() }
    func thumbnail() {
        if let old = fullFrame { window.setFrame(old, display: true); fullFrame = nil; record.thumbnail = false }
        else { fullFrame = window.frame; zoom(120 / max(window.frame.width, window.frame.height)); record.thumbnail = true }
        record.normalFrame = fullFrame
        onChange?()
    }
    func edit() {
        guard let image = NSImage(data: record.imageData) else { return }
        ImageWorkspace.open(image, title: "编辑贴图 · Scapare", snapshot: record.snapshot) { [weak self] image, snapshot in
            guard let self else { return }; self.record.snapshot = snapshot; self.refresh()
            let old = self.window.frame, ratio = (self.currentImage?.size.width ?? 1) / max(1, self.currentImage?.size.height ?? 1)
            self.window.setFrame(CGRect(x: old.minX, y: old.minY, width: old.width, height: old.width / ratio), display: true)
            self.onChange?()
        }
    }
    func editSourceText() {
        let original = record.sourceText ?? record.sourceHTML.map { ClipboardText.html($0).string }
        guard let original else { return }
        guard let values = AppDialogs.fields(title: "编辑文字或色卡（将生成新的原图）", labels: ["文字 / #RRGGBB"], values: [original]), values[0].count <= 100_000 else { return }
        if record.snapshot != nil {
            let alert = NSAlert(); alert.messageText = "替换原图并清除这张贴图的标注？"; alert.informativeText = "原来的标注位置可能不适合新的文字。"; alert.addButton(withTitle: "替换"); alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let image = ImageInputs.textImage(values[0]); guard let data = image.pngData else { return }
        record.sourceText = values[0]; record.sourceHTML = nil; record.imageData = data; record.snapshot = nil
        gifSource = CGImageSourceCreateWithData(data as CFData, nil); gifFrame = 0; refresh()
        let old = window.frame; window.setFrame(CGRect(x: old.minX, y: old.minY, width: old.width, height: old.width * image.size.height / max(1, image.size.width)), display: true); onChange?()
    }
    func setGroup(_ group: String) { record.group = String(group.prefix(100)); onChange?() }
    func rename() {
        guard let values = AppDialogs.fields(title: "贴图名称和分组", labels: ["名称", "分组"], values: [record.title, record.group]) else { return }
        record.title = String(values[0].prefix(200)); setGroup(values[1].isEmpty ? "默认" : values[1])
    }
    func preciseSize() {
        guard let v = AppDialogs.fields(title: "贴图显示宽度（点）", labels: ["宽度"], values: [String(Int(window.frame.width))]), let w = Double(v[0]), w.isFinite, w > 0 else { return }
        zoom(w / window.frame.width)
    }
    func action(_ action: String) {
        switch action {
        case "copy": if let image = displayImage { Clipboard.copy(image: image) }
        case "file": if let image = displayImage { ImageFileSaver.copyAsFile(image) }
        case "save": if let image = displayImage { _ = ImageFileSaver.save(image) }
        case "quick": if let image = displayImage { _ = ImageFileSaver.quickSave(image) }
        case "share": if let image = displayImage { NSSharingServicePicker(items: [image]).show(relativeTo: pinView.bounds, of: pinView, preferredEdge: .minY) }
        case "ocr": if let image = displayImage { OCRResultController.present(image: image) }
        case "barcode": if let image = displayImage { OCRResultController.present(image: image, barcode: true) }
        case "edit": edit()
        case "source": editSourceText()
        case "left": rotate(-1)
        case "right": rotate(1)
        case "horizontal": flip(horizontal: true)
        case "vertical": flip(horizontal: false)
        case "gray": record.grayscale.toggle(); refresh(); onChange?()
        case "invert": record.inverted.toggle(); refresh(); onChange?()
        case "top": record.topmost.toggle(); refresh(); onChange?()
        case "through": setClickThrough(true)
        case "thumbnail": thumbnail()
        case "hide": setHidden(true)
        case "solo": PinManager.shared.solo(self)
        case "name": rename()
        case "size": preciseSize()
        case "background": record.background = (record.background + 1) % 5; pinView.needsDisplay = true; onChange?()
        case "gif": gifPaused.toggle()
        case "previous": stepGIF(-1)
        case "next": stepGIF(1)
        default: break
        }
    }
    private func startGIF() {
        guard let source = gifSource, CGImageSourceGetCount(source) > 1 else { return }
        gifTask = Task { [weak self] in
            while !Task.isCancelled {
                let delay = self?.gifDelay() ?? 0.1
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard let self else { return }
                if !self.record.hidden && !self.gifPaused && self.record.snapshot == nil { self.stepGIF(1, pause: false) }
            }
        }
    }
    private func gifDelay() -> Double {
        guard let source = gifSource, let props = CGImageSourceCopyPropertiesAtIndex(source, gifFrame, nil) as? [CFString: Any],
              let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] else { return 0.1 }
        return max(0.03, (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? gif[kCGImagePropertyGIFDelayTime] as? Double ?? 0.1) / gifSpeed)
    }
    func stepGIF(_ delta: Int, pause: Bool = true) {
        guard let source = gifSource else { return }; let count = CGImageSourceGetCount(source); guard count > 1 else { return }
        gifFrame = (gifFrame + delta + count) % count; if pause { gifPaused = true }; refresh()
    }
    func adjustGIFSpeed(_ factor: Double) { gifSpeed = max(0.25, min(4, gifSpeed * factor)) }
}
final class PinWindow: NSWindow { override var canBecomeKey: Bool { true }; override var canBecomeMain: Bool { true } }

final class PinView: NSView, NSDraggingSource {
    weak var controller: PinWindowController?
    private var resizeOrigin: (point: CGPoint, frame: CGRect)?
    override init(frame: CGRect) {
        super.init(frame: frame); registerForDraggedTypes([.fileURL, .png, .tiff, .URL]); setAccessibilityElement(true); setAccessibilityRole(.image)
        setAccessibilityLabel("贴图：空格编辑，滚轮缩放，右键更多操作")
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("not used") }
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let mode = controller?.record.background ?? 0
        if mode == 0 {
            NSColor.windowBackgroundColor.setFill(); bounds.fill()
            NSColor.separatorColor.setFill()
            for y in stride(from: 0, to: Int(bounds.height), by: 16) { for x in stride(from: 0, to: Int(bounds.width), by: 16) where (x / 16 + y / 16) % 2 == 0 { CGRect(x: x, y: y, width: 16, height: 16).fill() } }
        } else if mode == 4 {
            NSColor(white: 0.2, alpha: 1).setFill(); bounds.fill(); NSColor(white: 0.3, alpha: 1).setFill()
            for y in stride(from: 0, to: Int(bounds.height), by: 16) { for x in stride(from: 0, to: Int(bounds.width), by: 16) where (x / 16 + y / 16) % 2 == 0 { CGRect(x: x, y: y, width: 16, height: 16).fill() } }
        } else if mode != 3 { (mode == 1 ? NSColor.white : .black).setFill(); bounds.fill() }
        controller?.currentImage?.draw(in: bounds)
        NSColor.white.withAlphaComponent(0.85).setStroke()
        let grip = NSBezierPath(); grip.move(to: CGPoint(x: bounds.maxX - 12, y: 3)); grip.line(to: CGPoint(x: bounds.maxX - 3, y: 12)); grip.lineWidth = 2; grip.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        if point.x > bounds.maxX - 16 && point.y < 16, let frame = window?.frame { resizeOrigin = (NSEvent.mouseLocation, frame); return }
        if event.clickCount == 2 { event.modifierFlags.contains(.shift) ? controller?.thumbnail() : controller?.setHidden(true); return }
        if event.modifierFlags.contains(.command), let image = controller?.currentImage {
            let item = NSDraggingItem(pasteboardWriter: image); item.setDraggingFrame(bounds, contents: image)
            beginDraggingSession(with: [item], event: event, source: self)
        } else { window?.performDrag(with: event) }
    }
    override func resetCursorRects() { addCursorRect(CGRect(x: bounds.maxX - 16, y: 0, width: 16, height: 16), cursor: .crosshair) }
    override func mouseDragged(with event: NSEvent) {
        guard let initial = resizeOrigin else { return }
        let ratio = initial.frame.width / max(1, initial.frame.height)
        let width = min(6000, 6000 * ratio, max(40, initial.frame.width + NSEvent.mouseLocation.x - initial.point.x))
        let height = width * initial.frame.height / max(1, initial.frame.width)
        window?.setFrame(CGRect(x: initial.frame.minX, y: initial.frame.maxY - height, width: width, height: height), display: true)
    }
    override func mouseUp(with event: NSEvent) { resizeOrigin = nil }
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { controller?.opacity((controller?.record.opacity ?? 1) + event.scrollingDeltaY * 0.01) }
        else if event.modifierFlags.contains(.option) { controller?.adjustGIFSpeed(event.scrollingDeltaY > 0 ? 1.1 : 0.9) }
        else { controller?.zoom(1 + event.scrollingDeltaY * 0.006) }
    }
    override func magnify(with event: NSEvent) { controller?.zoom(1 + event.magnification) }
    override func rotate(with event: NSEvent) { if abs(event.rotation) > 15 { controller?.rotate(event.rotation > 0 ? -1 : 1) } }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return super.performKeyEquivalent(with: event) }
        if event.keyCode == 8 { controller?.action("copy"); return true }
        if event.keyCode == 1 { controller?.action("save"); return true }
        return super.performKeyEquivalent(with: event)
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: controller?.setHidden(true)
        case 49: controller?.edit()
        case 18: controller?.rotate(-1)
        case 19: controller?.rotate(1)
        case 20: controller?.flip(horizontal: true)
        case 21: controller?.flip(horizontal: false)
        case 24: controller?.zoom(1.1)
        case 27: controller?.zoom(1 / 1.1)
        case 123: controller?.stepGIF(-1)
        case 124: controller?.stepGIF(1)
        default: super.keyDown(with: event)
        }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        func add(_ title: String, _ action: String, to destination: NSMenu) {
            let item = destination.addItem(withTitle: title, action: #selector(runAction(_:)), keyEquivalent: ""); item.target = self; item.representedObject = action
            if action == "gray" { item.state = controller?.record.grayscale == true ? .on : .off }
            if action == "invert" { item.state = controller?.record.inverted == true ? .on : .off }
            if action == "top" { item.state = controller?.record.topmost == true ? .on : .off }
        }
        func group(_ title: String, _ actions: [(String, String)]) {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: ""), sub = NSMenu()
            for (label, action) in actions { add(label, action, to: sub) }
            item.submenu = sub; menu.addItem(item)
        }
        add("复制", "copy", to: menu); add("保存…", "save", to: menu); add("编辑 / 裁剪（空格）", "edit", to: menu)
        if controller?.record.sourceText != nil || controller?.record.sourceHTML != nil { add("编辑文字或色卡…", "source", to: menu) }
        group("输出", [("复制为文件", "file"), ("快速保存", "quick"), ("分享…", "share"), ("文字识别", "ocr"), ("识别条码", "barcode")])
        group("图像变换", [("逆时针旋转（1）", "left"), ("顺时针旋转（2）", "right"), ("水平翻转（3）", "horizontal"), ("垂直翻转（4）", "vertical"), ("灰度", "gray"), ("反色", "invert"), ("切换透明背景", "background")])
        group("显示", [("缩略图（Shift 双击）", "thumbnail"), ("精确显示尺寸…", "size"), ("置顶", "top"), ("鼠标穿透（从菜单栏恢复）", "through"), ("只显示这张", "solo")])
        group("GIF", [("暂停 / 播放", "gif"), ("上一帧", "previous"), ("下一帧", "next")])
        add("名称和分组…", "name", to: menu); add("隐藏（双击 / Esc）", "hide", to: menu)
        let opacity = NSMenuItem(title: "不透明度", action: nil, keyEquivalent: ""), submenu = NSMenu()
        for percent in [100, 80, 60, 40, 20] {
            let item = submenu.addItem(withTitle: "\(percent)%", action: #selector(setOpacity(_:)), keyEquivalent: ""); item.target = self; item.tag = percent
            item.state = abs((controller?.record.opacity ?? 1) * 100 - Double(percent)) < 1 ? .on : .off
        }
        opacity.submenu = submenu; menu.addItem(opacity); return menu
    }
    @objc private func runAction(_ sender: NSMenuItem) { if let action = sender.representedObject as? String { controller?.action(action) } }
    @objc private func setOpacity(_ sender: NSMenuItem) { controller?.opacity(Double(sender.tag) / 100) }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            do { for url in urls { let data = try Data(contentsOf: url); PinManager.shared.add(try ImageInputs.decode(data), originalData: data) }; return true }
            catch { AppDialogs.error(error.localizedDescription); return false }
        }
        if let image = NSImage(pasteboard: pb) { PinManager.shared.add(image); return true }
        if let text = pb.string(forType: .URL), let url = URL(string: text) { WebImageImporter.offer(url); return true }
        return false
    }
}
