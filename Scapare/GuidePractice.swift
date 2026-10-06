import AppKit
import CoreImage

nonisolated enum GuidePracticeStep: Equatable {
    case captureShortcut, color, selection, annotation, undo, redo, copy, pin, movePin, zoomPin, copyPin
    case startScroll, scroll, copyLong, ocr, copyText, barcode, copyBarcode, recordShortcut, theme, testShortcut

    var title: String {
        switch self {
        case .captureShortcut: return "按快捷键开始框选"
        case .color: return "复制一个颜色"
        case .selection: return "拖动框选练习卡片"
        case .annotation: return "画一支箭头"
        case .undo: return "撤销刚才的箭头"
        case .redo: return "恢复刚才的箭头"
        case .copy: return "复制截图"
        case .pin: return "把截图钉到桌面"
        case .movePin: return "移动练习贴图"
        case .zoomPin: return "缩放练习贴图"
        case .copyPin: return "复制练习贴图"
        case .startScroll: return "点击长截图工具"
        case .scroll: return "上下滚动练习页"
        case .copyLong: return "完成并复制长图"
        case .ocr: return "识别卡片里的文字"
        case .copyText: return "检查并复制识别结果"
        case .barcode: return "识别练习二维码"
        case .copyBarcode: return "复制二维码内容"
        case .recordShortcut: return "录制一个练习快捷键"
        case .theme: return "切换练习区主题"
        case .testShortcut: return "试用刚才录制的快捷键"
        }
    }
}

nonisolated enum GuidePracticeEvent {
    case captureOpened, colorCopied, selected, annotated, undone, redone, copied, pinned, pinMoved, pinZoomed, pinCopied
    case scrollStarted, scrollAppended, longCopied, recognized, textCopied, barcodeRecognized, barcodeCopied
    case shortcutRecorded, themeChanged, shortcutTested
}

/// Progress reflects actual successful actions. A click on Next cannot pass an unfinished step.
nonisolated struct GuidePracticeProgress {
    let steps: [GuidePracticeStep]
    private(set) var index = 0
    private(set) var stepCompleted = false
    var finished: Bool { index == steps.count }
    var current: GuidePracticeStep? { finished ? nil : steps[index] }
    init(topic: FeatureGuideTopic) {
        switch topic {
        case .start: steps = [.captureShortcut, .selection, .annotation, .copy, .pin, .movePin]
        case .capture: steps = [.color, .selection, .copy]
        case .annotation: steps = [.annotation, .undo, .redo, .copy]
        case .pins: steps = [.pin, .movePin, .zoomPin, .copyPin]
        case .scrolling: steps = [.startScroll, .scroll, .copyLong]
        case .recognition: steps = [.ocr, .copyText, .barcode, .copyBarcode]
        case .advanced: steps = [.recordShortcut, .theme, .testShortcut]
        }
    }
    @discardableResult mutating func accept(_ event: GuidePracticeEvent) -> Bool {
        let expected: GuidePracticeStep
        switch event {
        case .captureOpened: expected = .captureShortcut
        case .colorCopied: expected = .color
        case .selected: expected = .selection
        case .annotated: expected = .annotation
        case .undone: expected = .undo
        case .redone: expected = .redo
        case .copied: expected = .copy
        case .pinned: expected = .pin
        case .pinMoved: expected = .movePin
        case .pinZoomed: expected = .zoomPin
        case .pinCopied: expected = .copyPin
        case .scrollStarted: expected = .startScroll
        case .scrollAppended: expected = .scroll
        case .longCopied: expected = .copyLong
        case .recognized: expected = .ocr
        case .textCopied: expected = .copyText
        case .barcodeRecognized: expected = .barcode
        case .barcodeCopied: expected = .copyBarcode
        case .shortcutRecorded: expected = .recordShortcut
        case .themeChanged: expected = .theme
        case .shortcutTested: expected = .testShortcut
        }
        guard current == expected, !stepCompleted else { return false }
        stepCompleted = true
        return true
    }
    @discardableResult mutating func advance() -> Bool {
        guard stepCompleted, !finished else { return false }
        index += 1; stepCompleted = false
        return true
    }
}

@MainActor
final class GuidePracticeView: NSStackView {
    static let canvasSize = CGSize(width: 720, height: 320)
    let topic: FeatureGuideTopic
    private(set) var progress: GuidePracticeProgress
    private(set) var editor: EditorView?
    private(set) var practicePin: PinWindowController?
    private(set) var scrolling: ScrollingCaptureController?
    private let pasteboard: NSPasteboard
    private weak var highlightedButton: NSButton?
    private let titleLabel = NSTextField(labelWithString: "")
    let instruction = NSTextField(wrappingLabelWithString: "")
    let feedback = NSTextField(wrappingLabelWithString: "")
    private let counter = NSTextField(labelWithString: "")
    let nextButton = NSButton(title: "下一步", target: nil, action: nil)
    let startButton = NSButton(title: "开始练习", target: nil, action: nil)
    private let restartButton = NSButton(title: "重新练习", target: nil, action: nil)
    private let actionButton = NSButton(title: "", target: nil, action: nil)
    private let canvas = NSView()
    private let toolsScroll = NSScrollView()
    private var toolbar: EditorToolbar?
    private var scrollPage: NSScrollView?
    private var resultText: NSTextView?
    private var recognitionTask: Task<Void, Never>?
    private var revision = UUID()
    private var lastAnnotationCount = 0
    private var pinOrigin: CGRect = .zero
    private var lastLongImage: NSImage?
    private var scrollSelection: CGRect = .zero
    private var practiceShortcut = CaptureShortcut(keyCode: SettingsManager.keyCode, modifiers: SettingsManager.modifiers)
    private var running = false
    private(set) var disposed = false

    init(topic: FeatureGuideTopic, pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.topic = topic; progress = GuidePracticeProgress(topic: topic)
        super.init(frame: .zero)
        orientation = .vertical; alignment = .leading; spacing = 8
        titleLabel.stringValue = topic.title
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
        counter.font = .systemFont(ofSize: 12, weight: .medium); counter.textColor = .secondaryLabelColor
        instruction.font = .systemFont(ofSize: 13)
        feedback.font = .systemFont(ofSize: 12); feedback.textColor = .secondaryLabelColor
        canvas.wantsLayer = true
        canvas.layer?.borderWidth = 1; canvas.layer?.borderColor = NSColor.separatorColor.cgColor
        canvas.setAccessibilityLabel("功能引导练习区")
        toolsScroll.hasHorizontalScroller = true; toolsScroll.autohidesScrollers = true; toolsScroll.drawsBackground = false
        for button in [nextButton, startButton, restartButton, actionButton] { button.bezelStyle = .rounded; button.target = self }
        nextButton.action = #selector(nextStep); startButton.action = #selector(startPractice)
        restartButton.action = #selector(restart); actionButton.action = #selector(performStepAction)
        let buttons = NSStackView(views: [startButton, actionButton, restartButton, nextButton]); buttons.spacing = 10
        for v in [titleLabel, counter, instruction, canvas, toolsScroll, feedback, buttons] { addArrangedSubview(v) }
        for v in [canvas, toolsScroll] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalToConstant: Self.canvasSize.width).isActive = true
        }
        canvas.heightAnchor.constraint(equalToConstant: Self.canvasSize.height).isActive = true
        toolsScroll.heightAnchor.constraint(equalToConstant: 56).isActive = true
        for field in [instruction, feedback] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalTo: canvas.widthAnchor).isActive = true
        }
        showOverview()
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { if !consumeShortcut(event) { super.keyDown(with: event) } }

    private func showOverview() {
        counter.stringValue = "\(progress.steps.count) 步实操 · 可随时退出或重来"
        instruction.stringValue = progress.steps.map(\.title).joined(separator: " → ")
        feedback.stringValue = "使用练习素材；复制和保存由你点击。退出引导会清理练习贴图。"
        startButton.isHidden = false; nextButton.isHidden = true; restartButton.isHidden = true; actionButton.isHidden = true
        toolsScroll.isHidden = true
        showImage(GuidePracticeMaterial.card())
    }
    @objc func startPractice() {
        guard !disposed else { return }
        running = true; startButton.isHidden = true; restartButton.isHidden = false; nextButton.isHidden = false
        prepareStep(); renderInstruction()
    }
    @objc private func restart() {
        cleanupRuntime(); disposed = false; revision = UUID(); running = false
        progress = GuidePracticeProgress(topic: topic); lastAnnotationCount = 0; lastLongImage = nil
        appearance = nil; showOverview(); startPractice()
    }
    @objc func nextStep() {
        guard progress.advance() else { return }
        if progress.finished {
            cleanupRuntime(); toolsScroll.isHidden = true; actionButton.isHidden = true; nextButton.isHidden = true
            counter.stringValue = "练习完成"
            instruction.stringValue = "已经完成\(topic.title)的实操。左侧可以继续练习其他功能。"
            feedback.stringValue = "日常使用时，从菜单栏或截图工具条开始。功能引导可以随时重新打开。"
            showImage(GuidePracticeMaterial.card()); return
        }
        prepareStep(); renderInstruction()
    }
    private func renderInstruction() {
        guard let step = progress.current else { return }
        counter.stringValue = "第 \(progress.index + 1) / \(progress.steps.count) 步 · \(step.title)"
        switch step {
        case .captureShortcut: instruction.stringValue = "按 \(SettingsManager.currentShortcutString)，或点「开始框选」。这次会进入下方的练习区。"
        case .color: instruction.stringValue = "将鼠标移到练习卡片的色块上，按 C。颜色值会复制到剪贴板。"
        case .selection: instruction.stringValue = "在下方按住鼠标，从卡片左上角拖到右下角。松开后会显示选区和工具条；也可按 ⌘A 全选练习区。"
        case .annotation: instruction.stringValue = "点工具条的箭头按钮，再在选区内拖动，画一支箭头。"
        case .undo: instruction.stringValue = "点撤销按钮或按 ⌘Z，让刚才画的箭头消失。"
        case .redo: instruction.stringValue = "点重做按钮或按 ⌘⇧Z，恢复刚才的箭头。"
        case .copy: instruction.stringValue = "点复制按钮或按 ⌘C，复制选区和标注。也可以点保存按钮，将练习截图保存为图片。"
        case .pin: instruction.stringValue = "点钉图按钮或按 ⌘⇧P，会出现一张可操作的练习贴图。"
        case .movePin: instruction.stringValue = "按住刚出现的练习贴图，拖动到另一个位置；这张贴图可以跨窗口移动。"
        case .zoomPin: instruction.stringValue = "把鼠标放到练习贴图上，用滚轮或触控板缩放；也可在贴图上按 + 或 −。"
        case .copyPin: instruction.stringValue = "右键点练习贴图，选择「复制」，或在贴图上按 ⌘C。"
        case .startScroll: instruction.stringValue = "选区已准备好。点工具条的长截图按钮，开始捕获练习页。"
        case .scroll: instruction.stringValue = "在下方练习页里上下滚动，直到至少拼接出第二屏的内容。也可点「切换页面」暂停，换页后点「继续追加」。"
        case .copyLong: instruction.stringValue = "在滚动截图面板点「完成并复制」，把拼接好的长图复制到剪贴板。"
        case .ocr: instruction.stringValue = "点文字识别按钮或按 ⌘⇧O，实际识别练习卡片里的文字。"
        case .copyText: instruction.stringValue = "在下方检查或修改识别结果，再点「复制识别文字」。"
        case .barcode: instruction.stringValue = "右键点下方选区，选择「识别条码 / 二维码」，也可点「识别练习二维码」。"
        case .copyBarcode: instruction.stringValue = "检查下方实际识别的二维码内容，再点「复制二维码内容」。"
        case .recordShortcut: instruction.stringValue = "点击下方快捷键框，按一个组合键或 F1–F12。这只是练习，不会覆盖日常截图快捷键。"
        case .theme: instruction.stringValue = "点下方浅色 / 深色选项，切换练习区主题。系统主题和日常设置会保留。"
        case .testShortcut: instruction.stringValue = "按刚才录制的 \(SettingsManager.shortcutDisplayString(keyCode: practiceShortcut.keyCode, modifiers: practiceShortcut.modifiers))，看看是否能开始框选练习区。"
        }
        feedback.stringValue = progress.stepCompleted ? "✓ 这一步已完成，可以继续。" : "完成这一步后，「下一步」会亮起。"
        nextButton.isEnabled = progress.stepCompleted
        nextButton.title = progress.index == progress.steps.count - 1 ? "完成练习" : "下一步"
        highlightTool(for: step)
        NSAccessibility.post(element: feedback, notification: .valueChanged)
    }
    @discardableResult private func record(_ event: GuidePracticeEvent) -> Bool {
        guard running, !disposed, progress.accept(event) else { return false }
        renderInstruction(); return true
    }
    private func prepareStep() {
        guard let step = progress.current else { return }
        actionButton.isHidden = true
        switch step {
        case .captureShortcut, .testShortcut:
            removeEditor(); toolsScroll.isHidden = true; showImage(GuidePracticeMaterial.card())
            if step == .captureShortcut { actionButton.title = "开始框选"; actionButton.isHidden = false }
            window?.makeFirstResponder(self)
        case .color, .selection:
            if editor == nil { installEditor(selected: false) }
            window?.makeFirstResponder(editor)
        case .annotation, .undo, .redo, .copy, .pin:
            if editor == nil { installEditor(selected: true) }
            window?.makeFirstResponder(editor)
        case .movePin, .zoomPin, .copyPin:
            toolsScroll.isHidden = true
            if step == .zoomPin, let pin = practicePin { pinOrigin = pin.window.frame }
        case .startScroll:
            installEditor(selected: true, image: GuidePracticeMaterial.longPage().cropping(to: CGRect(origin: .zero, size: Self.canvasSize)))
        case .scroll: break
        case .copyLong:
            if let image = lastLongImage {
                showImage(image); actionButton.title = "复制长图"; actionButton.isHidden = false
            }
        case .ocr: installEditor(selected: true)
        case .copyText:
            toolsScroll.isHidden = true; actionButton.title = "复制识别文字"; actionButton.isHidden = false
        case .barcode:
            installEditor(selected: true, image: GuidePracticeMaterial.qrCard())
            actionButton.title = "识别练习二维码"; actionButton.isHidden = false
        case .copyBarcode:
            toolsScroll.isHidden = true; actionButton.title = "复制二维码内容"; actionButton.isHidden = false
        case .recordShortcut:
            removeEditor(); toolsScroll.isHidden = true; clearCanvas()
            let recorder = ShortcutRecorder(keyCode: practiceShortcut.keyCode, modifiers: practiceShortcut.modifiers)
            recorder.frame = CGRect(x: 220, y: 138, width: 280, height: 44)
            recorder.onShortcutChanged = { [weak self] key, modifiers in
                self?.practiceShortcut = CaptureShortcut(keyCode: key, modifiers: modifiers); self?.record(.shortcutRecorded)
            }
            recorder.onError = { [weak self] error in if !error.isEmpty { self?.feedback.stringValue = error } }
            canvas.addSubview(recorder); window?.makeFirstResponder(recorder)
        case .theme:
            clearCanvas(); toolsScroll.isHidden = true
            let choice = NSSegmentedControl(labels: ["浅色", "深色"], trackingMode: .selectOne, target: self, action: #selector(changePracticeTheme(_:)))
            choice.frame = CGRect(x: 260, y: 144, width: 200, height: 32); choice.setAccessibilityLabel("练习区主题")
            canvas.addSubview(choice)
        }
    }
    func consumeShortcut(_ event: NSEvent) -> Bool {
        guard running, !disposed, !progress.stepCompleted,
              progress.current == .captureShortcut || progress.current == .testShortcut else { return false }
        let (code, modifiers) = SettingsManager.extract(from: event)
        let expected = progress.current == .testShortcut ? practiceShortcut : CaptureShortcut(keyCode: SettingsManager.keyCode, modifiers: SettingsManager.modifiers)
        guard CaptureShortcut(keyCode: code, modifiers: modifiers) == expected else { return false }
        openCapturePractice(); return true
    }
    private func openCapturePractice() {
        let testing = progress.current == .testShortcut
        installEditor(selected: false); actionButton.isHidden = true; window?.makeFirstResponder(editor)
        record(testing ? .shortcutTested : .captureOpened)
    }
    @objc private func performStepAction() {
        switch progress.current {
        case .captureShortcut: openCapturePractice()
        case .barcode: editor?.actionBarcode()
        case .copyText, .copyBarcode: copyRecognizedText()
        case .copyLong:
            if let image = lastLongImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) { _ = copyLongImage(image) }
        default: break
        }
    }
    @objc private func changePracticeTheme(_ sender: NSSegmentedControl) {
        appearance = NSAppearance(named: sender.selectedSegment == 0 ? .aqua : .darkAqua)
        record(.themeChanged)
    }
    private func installEditor(selected: Bool, image: CGImage? = nil) {
        removeEditor(); clearCanvas(); resultText = nil
        guard let screen = window?.screen ?? NSScreen.main else { return }
        let session = EditingSession()
        let view = EditorView(shot: DisplayShot(screen: screen, image: image ?? GuidePracticeMaterial.card()), controller: .shared,
                              session: session, canvasSize: Self.canvasSize, magnifierVisible: false)
        view.isLiveCapture = false; view.persistsPreferences = false
        if topic == .scrolling { view.onLongCapture = { [weak self] rect in self?.startScrolling(rect) } }
        view.copyColorOutput = { [weak self] text in
            guard let self, !self.disposed else { return false }; return Clipboard.copy(text: text, to: self.pasteboard)
        }
        view.onColorCopied = { [weak self] in self?.record(.colorCopied) }
        view.onSnapshotChange = { [weak self] snapshot in self?.snapshotChanged(snapshot) }
        view.onOutput = { [weak self] action, image in self?.output(action, image) }
        view.onCancel = { [weak self] in self?.restart() }
        editor = view; canvas.addSubview(view)
        let tools = EditorToolbar(editor: view); view.installExternalToolbar(tools)
        toolbar = tools; toolsScroll.documentView = tools; toolsScroll.isHidden = true
        lastAnnotationCount = 0
        if selected { view.setSelection(CGRect(x: 24, y: 24, width: 672, height: 272)); toolsScroll.isHidden = false }
    }
    private func snapshotChanged(_ snapshot: EditSnapshot) {
        if let rect = snapshot.selection, rect.width >= 64, rect.height >= 48 {
            toolsScroll.isHidden = false; record(.selected)
        }
        let count = snapshot.annotations.count
        if count > lastAnnotationCount {
            if progress.current == .redo { record(.redone) }
            else if snapshot.annotations.last?.tool == .arrow { record(.annotated) }
        }
        else if count < lastAnnotationCount { record(.undone) }
        lastAnnotationCount = count
    }
    private func output(_ action: EditorOutput, _ image: NSImage) {
        guard !disposed else { return }
        switch action {
        case .copy:
            if Clipboard.copy(image: image, to: pasteboard) { record(.copied) }
            else { feedback.stringValue = "复制失败，请再试一次；选区和标注仍保留。" }
        case .save:
            if case .saved = ImageFileSaver.save(image) { record(.copied) }
        case .pin: createPracticePin(image)
        case .ocr, .barcode: recognize(image, barcode: action == .barcode)
        case .share, .quickSave: feedback.stringValue = "这一步请使用工具条上的复制或保存按钮。"
        }
    }
    private func createPracticePin(_ image: NSImage) {
        guard progress.current == .pin, !progress.stepCompleted, let data = image.pngData, let host = window else { return }
        practicePin?.dispose()
        let frame = CGRect(x: host.frame.minX + 450, y: host.frame.minY + 140, width: 300, height: 300 * image.size.height / max(1, image.size.width))
        let pin = PinWindowController(record: PinRecord(imageData: data, frame: frame))
        pin.practiceAction = { [weak self, weak pin] action in
            guard let self, !self.disposed else { return }
            if action == "copy", let image = pin?.currentImage, Clipboard.copy(image: image, to: self.pasteboard) { self.record(.pinCopied) }
            else if action == "hide" { pin?.dispose(); self.feedback.stringValue = "练习贴图已关闭，点「重新练习」可以再次创建。" }
        }
        practicePin = pin; pinOrigin = frame
        pin.onChange = { [weak self, weak pin] in
            guard let self, let pin, !self.disposed else { return }
            let frame = pin.window.frame
            if hypot(frame.minX - self.pinOrigin.minX, frame.minY - self.pinOrigin.minY) > 12 { self.record(.pinMoved) }
            if abs(frame.width - self.pinOrigin.width) > 8 { self.record(.pinZoomed) }
        }
        pin.showIfVisible(); record(.pinned)
    }
    private func recognize(_ image: NSImage, barcode: Bool) {
        guard (progress.current == .ocr && !barcode) || (progress.current == .barcode && barcode), let data = image.pngData else { return }
        recognitionTask?.cancel(); let token = revision
        feedback.stringValue = barcode ? "正在识别二维码…" : "正在识别文字…"
        recognitionTask = Task { [weak self] in
            do {
                let text: String
                if barcode { text = try await OCRService.barcodes(pngData: data) }
                else { text = try await OCRService.recognize(pngData: data) }
                guard let self, !Task.isCancelled, !self.disposed, self.revision == token else { return }
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { self.feedback.stringValue = "没有识别到内容，请重试。"; return }
                self.showRecognizedText(text)
                self.record(barcode ? .barcodeRecognized : .recognized)
            } catch {
                guard let self, !Task.isCancelled, !self.disposed, self.revision == token else { return }
                self.feedback.stringValue = "识别失败，可再次点识别重试：" + error.localizedDescription
            }
        }
    }
    private func showRecognizedText(_ text: String) {
        removeEditor(); clearCanvas(); toolsScroll.isHidden = true
        let field = NSTextView(); field.string = text; field.isRichText = false; field.font = .systemFont(ofSize: 18)
        field.textContainerInset = CGSize(width: 16, height: 16); field.autoresizingMask = [.width]
        field.textContainer?.widthTracksTextView = true; field.setAccessibilityLabel("练习识别结果，可编辑")
        let scroll = NSScrollView(frame: CGRect(origin: .zero, size: Self.canvasSize)); scroll.hasVerticalScroller = true
        scroll.documentView = field; canvas.addSubview(scroll); resultText = field
    }
    private func copyRecognizedText() {
        guard let text = resultText?.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard Clipboard.copy(text: text, to: pasteboard) else { feedback.stringValue = "复制失败，请再试一次。"; return }
        record(progress.current == .copyBarcode ? .barcodeCopied : .textCopied)
    }
    private func startScrolling(_ rect: CGRect) {
        guard progress.current == .startScroll, !progress.stepCompleted, let host = window, let screen = host.screen ?? NSScreen.main else { return }
        scrollSelection = rect; removeEditor(); clearCanvas(); toolsScroll.isHidden = true
        let pageImage = GuidePracticeMaterial.longPage()
        let page = NSScrollView(frame: CGRect(origin: .zero, size: Self.canvasSize)); page.hasVerticalScroller = true
        let document = NSImageView(frame: CGRect(x: 0, y: 0, width: pageImage.width, height: pageImage.height))
        document.image = NSImage(cgImage: pageImage, size: document.frame.size); document.imageScaling = .scaleAxesIndependently
        page.documentView = document; canvas.addSubview(page); scrollPage = page
        page.contentView.scroll(to: CGPoint(x: 0, y: max(0, CGFloat(pageImage.height) - page.contentSize.height))); page.reflectScrolledClipView(page.contentView)
        let global = host.convertToScreen(canvas.convert(rect, to: nil))
        let capture = ScrollingCaptureController(screen: screen, selection: global.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY),
            onClose: { [weak self] in
                guard let self, !self.disposed else { return }
                self.scrolling = nil
                if self.lastLongImage == nil { self.feedback.stringValue = "滚动练习已结束；点「重新练习」可以再试。" }
            },
            makeSource: { GuideScrollSource(image: pageImage, scroll: page, selection: rect, viewportHeight: Self.canvasSize.height) },
            onCopy: { [weak self] image in self?.copyLongImage(image) ?? false },
            onFinish: { [weak self] image in
                guard let self, !self.disposed else { return }
                self.lastLongImage = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height)); self.showImage(self.lastLongImage!)
                self.actionButton.title = "复制长图"; self.actionButton.isHidden = false
            })
        capture.onProgress = { [weak self] update in
            guard let self, !self.disposed else { return }
            if update.frameCount > 1, CGFloat(update.height) > rect.height + 80 { self.record(.scrollAppended) }
        }
        scrolling = capture; capture.present()
        if record(.scrollStarted) { nextStep() }
    }
    private func copyLongImage(_ image: CGImage) -> Bool {
        guard !disposed, CGFloat(image.height) > scrollSelection.height + 80 else {
            feedback.stringValue = "仍只有一屏内容；请重新练习并向下滚动更多。"; return false
        }
        let result = NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))
        guard Clipboard.copy(image: result, to: pasteboard) else { return false }
        lastLongImage = result
        if progress.current == .scroll, progress.stepCompleted { progress.advance() }
        record(.longCopied); showImage(result); return true
    }
    private func highlightTool(for step: GuidePracticeStep) {
        let hint: String?
        switch step {
        case .annotation: hint = "箭头"
        case .undo: hint = "撤销"
        case .redo: hint = "重做"
        case .copy: hint = "复制到剪贴板"
        case .pin: hint = "钉在屏幕"
        case .startScroll: hint = "滚动截图"
        case .ocr: hint = "文字识别"
        default: hint = nil
        }
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        guard let toolbar else { return }
        highlightedButton?.layer?.borderWidth = 0; highlightedButton = nil
        toolbar.refreshToolSelection()
        for button in descendants(toolbar).compactMap({ $0 as? NSButton }) {
            let target = hint.map { button.toolTip?.contains($0) == true } ?? false
            if target {
                button.layer?.borderColor = NSColor.controlAccentColor.cgColor; button.layer?.borderWidth = 2
                highlightedButton = button
                button.scrollToVisible(button.bounds.insetBy(dx: -8, dy: -4))
            }
        }
    }
    private func showImage(_ image: CGImage) { showImage(NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height))) }
    private func showImage(_ image: NSImage) {
        clearCanvas()
        let view = NSImageView(frame: CGRect(origin: .zero, size: Self.canvasSize)); view.image = image; view.imageScaling = .scaleProportionallyUpOrDown
        canvas.addSubview(view)
    }
    private func clearCanvas() { canvas.subviews.forEach { $0.removeFromSuperview() } }
    private func removeEditor() { editor?.onSnapshotChange = nil; editor?.detachSession(); editor?.removeFromSuperview(); editor = nil; toolbar = nil; toolsScroll.documentView = nil }
    private func cleanupRuntime() {
        revision = UUID(); recognitionTask?.cancel(); recognitionTask = nil
        let capture = scrolling; scrolling = nil; capture?.close()
        practicePin?.onChange = nil; practicePin?.dispose(); practicePin = nil
        removeEditor(); scrollPage = nil; resultText = nil
    }
    func dispose() { disposed = true; running = false; cleanupRuntime() }
}

@MainActor
private final class GuideScrollSource: ScrollingCaptureSource {
    private let image: CGImage
    private weak var scroll: NSScrollView?
    private let selection: CGRect
    private let viewportHeight: CGFloat
    private var observer: NSObjectProtocol?
    private var continuation: AsyncThrowingStream<PixelRaster, Error>.Continuation?
    private var stopped = false
    init(image: CGImage, scroll: NSScrollView, selection: CGRect, viewportHeight: CGFloat) {
        self.image = image; self.scroll = scroll; self.selection = selection; self.viewportHeight = viewportHeight
    }
    func frames() async throws -> AsyncThrowingStream<PixelRaster, Error> {
        let stream = AsyncThrowingStream<PixelRaster, Error>(bufferingPolicy: .bufferingNewest(8)) { continuation = $0 }
        guard let clip = scroll?.contentView else { throw ImageError.decode }
        clip.postsBoundsChangedNotifications = true
        observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.emit() }
        }
        emit(); return stream
    }
    private func emit() {
        guard !stopped, let scroll else { return }
        let top = CGFloat(image.height) - scroll.contentView.bounds.maxY
        let rect = CGRect(x: selection.minX, y: top + viewportHeight - selection.maxY, width: selection.width, height: selection.height).integral
        guard let crop = image.cropping(to: rect), let raster = try? PixelRaster(crop) else { return }
        continuation?.yield(raster)
    }
    func stop() async {
        stopped = true
        if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil
        continuation?.finish(); continuation = nil
    }
}

@MainActor
enum GuidePracticeMaterial {
    private static func draw(width: Int = 720, height: Int = 320, scale: Int = 2, _ drawing: () -> Void) -> CGImage {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * scale, pixelsHigh: height * scale, bitsPerSample: 8, samplesPerPixel: 4,
                                  hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width * scale * 4, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        NSColor(srgbRed: 0.96, green: 0.97, blue: 0.99, alpha: 1).setFill(); CGRect(x: 0, y: 0, width: width, height: height).fill()
        drawing(); NSGraphicsContext.restoreGraphicsState(); return rep.cgImage!
    }
    private static func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, bold: Bool = false) {
        (value as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular), .foregroundColor: NSColor.black])
    }
    static func card() -> CGImage {
        draw {
            NSColor.white.setFill(); NSBezierPath(roundedRect: CGRect(x: 24, y: 24, width: 672, height: 272), xRadius: 12, yRadius: 12).fill()
            text("Scapare", x: 52, y: 230, size: 32, bold: true)
            text("Capture. Annotate. Pin.", x: 52, y: 185, size: 22)
            text("把想法标出来，把灵感留在眼前。", x: 52, y: 139, size: 22)
            text("练习卡片 2026", x: 52, y: 82, size: 16)
            for (i, color) in [NSColor.systemBlue, .systemOrange, .systemGreen].enumerated() {
                color.setFill(); NSBezierPath(roundedRect: CGRect(x: 524 + i * 48, y: 66, width: 36, height: 36), xRadius: 6, yRadius: 6).fill()
            }
        }
    }
    static func qrCard() -> CGImage {
        draw {
            text("练习二维码", x: 42, y: 225, size: 28, bold: true)
            text("右键选区 → 识别条码 / 二维码", x: 42, y: 174, size: 18)
            text("识别后可以检查和复制内容。", x: 42, y: 130, size: 18)
            let filter = CIFilter(name: "CIQRCodeGenerator")!
            filter.setValue(Data("Scapare practice 2026".utf8), forKey: "inputMessage")
            filter.setValue("M", forKey: "inputCorrectionLevel")
            if let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)), let cg = CIContext().createCGImage(output, from: output.extent) {
                NSColor.white.setFill(); CGRect(x: 442, y: 30, width: 256, height: 256).fill()
                NSGraphicsContext.current?.imageInterpolation = .none
                NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height)).draw(in: CGRect(x: 458, y: 46, width: 224, height: 224))
            }
        }
    }
    static func longPage() -> CGImage {
        draw(height: 2400, scale: 1) {
            for i in 0..<15 {
                let y = CGFloat(2400 - (i + 1) * 160)
                NSColor.white.setFill(); NSBezierPath(roundedRect: CGRect(x: 24, y: y + 12, width: 672, height: 136), xRadius: 8, yRadius: 8).fill()
                text("\(i + 1). 灵感记录 · Scapare 滚动练习", x: 48, y: y + 104, size: 22, bold: true)
                text(["截图留住细节，标注说明重点。", "连续向下滚动，让内容连接成一张长图。", "完成并复制，再把长图粘贴到需要的地方。"][i % 3], x: 48, y: y + 62, size: 18)
                text("记录 \(2026 + i) · 第 \(i + 1) 段 · 练习素材", x: 48, y: y + 29, size: 14)
                NSColor(srgbRed: CGFloat((i * 31) % 150 + 40) / 255, green: CGFloat((i * 47) % 130 + 60) / 255, blue: 0.8, alpha: 1).setFill()
                NSBezierPath(ovalIn: CGRect(x: CGFloat(584 - i % 3 * 12), y: y + 54, width: 46, height: 46)).fill()
            }
        }
    }
}
