import AppKit

enum FeatureGuideTopic: Int, CaseIterable {
    case start, capture, scrolling, annotation, pins, recognition, advanced

    var title: String {
        switch self {
        case .start: return "快速开始"
        case .capture: return "截图与取色"
        case .scrolling: return "滚动长截图"
        case .annotation: return "标注与保存"
        case .pins: return "桌面贴图"
        case .recognition: return "文字与条码识别"
        case .advanced: return "更多功能"
        }
    }
    var symbol: String {
        switch self {
        case .start: return "sparkles"
        case .capture: return "viewfinder"
        case .scrolling: return "arrow.down.to.line"
        case .annotation: return "pencil.tip"
        case .pins: return "pin"
        case .recognition: return "text.viewfinder"
        case .advanced: return "slider.horizontal.3"
        }
    }
    var introduction: String {
        switch self {
        case .start: return "Scapare 常驻屏幕顶部菜单栏。截图、标注、长图和贴图，都可以从这里开始。"
        case .capture: return "截取区域、窗口或屏幕，也可以查看并复制屏幕上的颜色。"
        case .scrolling: return "把网页、聊天记录等连续滚动的内容拼成一张长图。"
        case .annotation: return "在截图上标重点、添加说明或遮住敏感信息，然后复制、保存或贴到桌面。"
        case .pins: return "把图片浮在桌面上，边看边工作。可见贴图也可以被再次截入新截图。"
        case .recognition: return "从图片中提取中英文文字，或读取条码、二维码的内容。识别在本机完成。"
        case .advanced: return "按自己的习惯设置快捷键、外观和高级操作。高级功能默认关闭，可按需启用。"
        }
    }
    var steps: [(title: String, detail: String)] {
        switch self {
        case .start: return [
            ("找到菜单栏图标", "点按屏幕顶部的长卷图标打开菜单。无论如何设置左键操作，右键都能打开菜单。"),
            ("按快捷键，拖动框选", "按下方显示的截图快捷键，拖动鼠标选择区域，再使用工具条。Esc 可以取消截图。"),
            ("随时回来查看", "菜单栏的「功能引导…」或设置中的「查看功能引导…」都能重新打开这里。左侧可直接切换功能。")]
        case .capture: return [
            ("框选或选择窗口", "用快捷键或菜单栏「截图」开始，拖动选择区域；悬停窗口后点按，也可以选择窗口。"),
            ("选择其他截图方式", "菜单栏「更多截图」提供当前屏幕、所有屏幕、活动窗口、重复上次选区和延时截图。"),
            ("查看颜色与工具提示", "框选前将鼠标移到目标像素，按 C 复制颜色。框选后，把鼠标放到工具条按钮上可查看功能提示。")]
        case .scrolling: return [
            ("选中滚动内容", "从菜单栏「滚动长截图…」开始，框选要截取的内容，再点工具条上的长截图按钮。"),
            ("在原窗口连续向下滚动", "保持原窗口和选区位置不变，自然向下滚动，Scapare 会连续拼接。无需每滑一下就停下来。"),
            ("完成并复制，或继续编辑", "点「完成并复制」可直接粘贴长图；点「完成并编辑」可以继续标注或保存。")]
        case .annotation: return [
            ("选择标注工具", "工具条提供矩形、椭圆、箭头、画笔和文字；「更多标注工具与样式」里还有高亮、马赛克等工具。"),
            ("调整样式，撤销修改", "在工具条调整颜色和粗细，文字工具可调整文字样式。⌘Z 撤销，⌘⇧Z 重做。"),
            ("选择输出方式", "⌘C 复制图片，⌘S 选择位置和格式保存，⌘⇧P 贴到桌面；也可以点工具条上的对应按钮。")]
        case .pins: return [
            ("从截图或剪贴板贴图", "截图后点工具条的贴图按钮，或选择菜单栏「贴出剪贴板」。也可以从文件导入图片。"),
            ("拖动、缩放和重新编辑", "拖动贴图调整位置，滚轮或触控板缩放。右键菜单可以重新编辑、调整不透明度和复制图片。"),
            ("管理多张贴图", "在「贴图库与分组…」中管理贴图和分组。菜单栏「贴图操作」可以显示或隐藏所有贴图。")]
        case .recognition: return [
            ("识别截图里的文字", "框选后点工具条「文字识别(OCR)」，或使用 ⌘⇧O，打开识别结果。"),
            ("编辑和复制识别结果", "检查或修改结果中的文字，再复制到其他应用。处理过程不需要上传图片。"),
            ("识别条码或二维码", "在截图编辑区右键，选择「识别条码 / 二维码」。桌面贴图的右键「输出」菜单也有识别功能。")]
        case .advanced: return [
            ("设置截图快捷键", "「设置…」可修改截图快捷键和登录启动；「更多设置…」可选择快速保存文件夹、配置更多全局快捷键。"),
            ("调整外观和操作习惯", "在「更多设置… → 外观与调色板…」中调整主题、工具外观和菜单栏点击操作。"),
            ("按需启用高级功能", "「高级功能…」提供修饰键截图手势、屏幕触发角和本机命令行批处理；菜单栏还提供白板和图片文件编辑。")]
        }
    }
    var tip: String {
        switch self {
        case .start: return "首次截图需要按 macOS 提示允许屏幕录制；如系统要求，请退出并重新打开 Scapare。"
        case .capture: return "像素放大镜默认关闭，可从截图编辑区的右键菜单按需开启。"
        case .scrolling: return "尽量框选滚动正文。若提示没有可靠衔接，可稍向上回滚恢复重叠，已拼接内容会保留。"
        case .annotation: return "马赛克会混合原有像素；需要完全遮住敏感信息时，使用不透明的实心遮盖。"
        case .pins: return "隐藏的贴图不会出现在截图中；开启鼠标穿透后，可从「贴图操作」恢复鼠标交互。"
        case .recognition: return "文字识别可能有误，复制前检查姓名、数字等重要内容。"
        case .advanced: return "全局快捷键、手势和触发角在 Scapare 内编辑或录制快捷键时暂停，避免打断输入。"
        }
    }
}

private final class FeatureGuideWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

private final class FeatureGuideDocument: NSView {
    override var isFlipped: Bool { true }
}

private final class FeatureGuideContent: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

/// Shared by first launch, the menu bar and Settings. Browsing the guide never
/// resets shortcuts or enables permissions, login items or advanced features.
@MainActor
final class FeatureGuideController: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private static var current: FeatureGuideController?
    let window: NSWindow
    private let isFirstRun: Bool
    private let defaults: UserDefaults
    private let topics = NSTableView()
    private let detail = NSStackView()
    private let detailScroll = NSScrollView()
    private let shortcut = NSTextField(labelWithString: "")
    private var textWidthConstraints: [NSLayoutConstraint] = []
    let doneButton: NSButton

    static func show(firstRun: Bool = false) {
        let controller = current ?? FeatureGuideController(isFirstRun: firstRun)
        current = controller
        controller.refreshShortcut()
        NSApp.activate(ignoringOtherApps: true)
        if !controller.window.isVisible { controller.window.center() }
        controller.window.makeKeyAndOrderFront(nil)
    }

    init(isFirstRun: Bool, defaults: UserDefaults = .standard) {
        self.isFirstRun = isFirstRun
        self.defaults = defaults
        window = FeatureGuideWindow(contentRect: CGRect(x: 0, y: 0, width: 760, height: 560),
                                    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        doneButton = NSButton(title: isFirstRun ? "开始使用" : "完成", target: nil, action: nil)
        super.init()
        window.title = isFirstRun ? "欢迎使用 Scapare" : "功能引导 · Scapare"
        window.isReleasedWhenClosed = false
        window.delegate = self
        buildContent()
        selectTopic(.start)
        refreshShortcut()
        window.contentMinSize = CGSize(width: 700, height: 500)
        window.setContentSize(CGSize(width: 760, height: 560))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func buildContent() {
        let content = FeatureGuideContent(frame: CGRect(origin: .zero, size: window.contentLayoutRect.size))
        window.contentView = content
        let title = NSTextField(labelWithString: isFirstRun ? "欢迎使用 Scapare" : "Scapare 功能引导")
        title.font = .systemFont(ofSize: 23, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "选一个功能，看看从哪里开始。")
        subtitle.textColor = .secondaryLabelColor
        let heading = NSStackView(views: [title, subtitle])
        heading.orientation = .vertical; heading.alignment = .leading; heading.spacing = 6
        let icon = NSImageView()
        icon.image = NSImage(named: NSImage.Name("AppIcon"))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityElement(false)
        let header = NSStackView(views: [icon, heading])
        header.spacing = 16; header.alignment = .centerY

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("guide-topic"))
        column.width = 170
        topics.addTableColumn(column); topics.headerView = nil
        topics.dataSource = self; topics.delegate = self
        topics.rowHeight = 42; topics.style = .sourceList
        topics.allowsEmptySelection = false
        topics.setAccessibilityLabel("功能列表")
        let sidebar = NSScrollView()
        sidebar.documentView = topics; sidebar.hasVerticalScroller = true
        sidebar.drawsBackground = false

        detail.orientation = .vertical; detail.alignment = .leading; detail.spacing = 18
        detail.translatesAutoresizingMaskIntoConstraints = false
        let document = FeatureGuideDocument()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(detail)
        detailScroll.documentView = document
        detailScroll.hasVerticalScroller = true; detailScroll.drawsBackground = false
        detailScroll.setAccessibilityLabel("功能操作说明")
        let separator = NSBox(); separator.boxType = .separator
        let settings = NSButton(title: "截图设置…", target: self, action: #selector(openSettings))
        settings.bezelStyle = .rounded
        shortcut.font = .systemFont(ofSize: 12); shortcut.textColor = .secondaryLabelColor
        doneButton.target = self; doneButton.action = #selector(finish)
        doneButton.bezelStyle = .rounded; doneButton.keyEquivalent = "\r"
        for view in [header, sidebar, separator, detailScroll, settings, shortcut, doneButton] {
            view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 48), icon.heightAnchor.constraint(equalToConstant: 48),
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            header.heightAnchor.constraint(equalToConstant: 56),
            header.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
            sidebar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            sidebar.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 24),
            sidebar.widthAnchor.constraint(equalToConstant: 180),
            sidebar.heightAnchor.constraint(greaterThanOrEqualToConstant: 300),
            sidebar.bottomAnchor.constraint(equalTo: settings.topAnchor, constant: -20),
            separator.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 12),
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.topAnchor.constraint(equalTo: sidebar.topAnchor),
            separator.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
            detailScroll.leadingAnchor.constraint(equalTo: separator.trailingAnchor, constant: 22),
            detailScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            detailScroll.topAnchor.constraint(equalTo: sidebar.topAnchor),
            detailScroll.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
            document.widthAnchor.constraint(equalTo: detailScroll.contentView.widthAnchor),
            detail.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            detail.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -8),
            detail.topAnchor.constraint(equalTo: document.topAnchor, constant: 8),
            detail.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -16),
            settings.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            settings.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            shortcut.leadingAnchor.constraint(equalTo: settings.trailingAnchor, constant: 14),
            shortcut.centerYAnchor.constraint(equalTo: settings.centerYAnchor),
            shortcut.trailingAnchor.constraint(lessThanOrEqualTo: doneButton.leadingAnchor, constant: -16),
            doneButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            doneButton.centerYAnchor.constraint(equalTo: settings.centerYAnchor)
        ])
    }

    func numberOfRows(in tableView: NSTableView) -> Int { FeatureGuideTopic.allCases.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let topic = FeatureGuideTopic(rawValue: row) else { return nil }
        let cell = NSTableCellView()
        let image = NSImageView()
        image.image = NSImage(systemSymbolName: topic.symbol, accessibilityDescription: nil)
        image.contentTintColor = .secondaryLabelColor
        let text = NSTextField(labelWithString: topic.title)
        text.font = .systemFont(ofSize: 13)
        cell.imageView = image; cell.textField = text
        for view in [image, text] { view.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(view) }
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            image.widthAnchor.constraint(equalToConstant: 18), image.heightAnchor.constraint(equalToConstant: 18),
            image.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 8),
            text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4)
        ])
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        if let topic = FeatureGuideTopic(rawValue: topics.selectedRow) { showTopic(topic) }
    }
    func selectTopic(_ topic: FeatureGuideTopic) {
        topics.selectRowIndexes(IndexSet(integer: topic.rawValue), byExtendingSelection: false)
        showTopic(topic)
    }
    private func showTopic(_ topic: FeatureGuideTopic) {
        NSLayoutConstraint.deactivate(textWidthConstraints)
        textWidthConstraints.removeAll()
        for view in detail.arrangedSubviews { detail.removeArrangedSubview(view); view.removeFromSuperview() }
        func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
                   color: NSColor = .labelColor) -> NSTextField {
            let field = NSTextField(wrappingLabelWithString: text)
            field.font = .systemFont(ofSize: size, weight: weight); field.textColor = color
            textWidthConstraints.append(field.widthAnchor.constraint(equalTo: detail.widthAnchor))
            return field
        }
        detail.addArrangedSubview(label(topic.title, size: 20, weight: .semibold))
        detail.addArrangedSubview(label(topic.introduction, color: .secondaryLabelColor))
        for (index, step) in topic.steps.enumerated() {
            let block = NSStackView(views: [label("\(index + 1). \(step.title)", size: 14, weight: .semibold), label(step.detail)])
            block.orientation = .vertical; block.alignment = .leading; block.spacing = 6
            detail.addArrangedSubview(block)
        }
        detail.addArrangedSubview(label(topic.tip, size: 12, color: .secondaryLabelColor))
        NSLayoutConstraint.activate(textWidthConstraints)
        window.contentView?.layoutSubtreeIfNeeded()
        detailScroll.contentView.scroll(to: .zero)
        detailScroll.reflectScrolledClipView(detailScroll.contentView)
    }
    private func refreshShortcut() { shortcut.stringValue = "截图快捷键：\(SettingsManager.currentShortcutString)" }
    func windowDidBecomeKey(_ notification: Notification) { refreshShortcut() }
    @objc private func openSettings() { SetupWindowController.showSettings() }
    @objc private func finish() { window.close() }
    func windowWillClose(_ notification: Notification) {
        if isFirstRun { SettingsManager.completeSetup(in: defaults) }
        if Self.current === self { Self.current = nil }
    }
}
