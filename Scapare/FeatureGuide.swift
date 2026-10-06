import AppKit

nonisolated enum FeatureGuideTopic: Int, CaseIterable {
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

}

private final class FeatureGuideWindow: NSWindow {
    var practiceShortcut: ((NSEvent) -> Bool)?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if practiceShortcut?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }
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
    private let practicePasteboard: NSPasteboard
    private let topics = NSTableView()
    private let detail = NSStackView()
    private let detailScroll = NSScrollView()
    private let shortcut = NSTextField(labelWithString: "")
    private(set) var practice: GuidePracticeView?
    let doneButton: NSButton

    static func show(firstRun: Bool = false) {
        let controller = current ?? FeatureGuideController(isFirstRun: firstRun)
        current = controller
        controller.refreshShortcut()
        NSApp.activate(ignoringOtherApps: true)
        if !controller.window.isVisible { controller.window.center() }
        controller.window.makeKeyAndOrderFront(nil)
    }

    init(isFirstRun: Bool, defaults: UserDefaults = .standard, pasteboard: NSPasteboard = .general) {
        self.isFirstRun = isFirstRun
        self.defaults = defaults
        practicePasteboard = pasteboard
        window = FeatureGuideWindow(contentRect: CGRect(x: 0, y: 0, width: 1080, height: 740),
                                    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        doneButton = NSButton(title: isFirstRun ? "开始使用" : "完成", target: nil, action: nil)
        super.init()
        window.title = isFirstRun ? "欢迎使用 Scapare" : "功能引导 · Scapare"
        window.isReleasedWhenClosed = false
        window.delegate = self
        (window as? FeatureGuideWindow)?.practiceShortcut = { [weak self] in self?.practice?.consumeShortcut($0) ?? false }
        buildContent()
        selectTopic(.start)
        refreshShortcut()
        window.contentMinSize = CGSize(width: 1000, height: 700)
        window.setContentSize(CGSize(width: 1080, height: 740))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func buildContent() {
        let content = FeatureGuideContent(frame: CGRect(origin: .zero, size: window.contentLayoutRect.size))
        window.contentView = content
        let title = NSTextField(labelWithString: isFirstRun ? "欢迎使用 Scapare" : "Scapare 功能引导")
        title.font = .systemFont(ofSize: 23, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "选一个功能，跟着步骤动手练习。")
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
        doneButton.bezelStyle = .rounded; doneButton.keyEquivalent = ""
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
        if practice?.topic != topic { showTopic(topic) }
    }
    private func showTopic(_ topic: FeatureGuideTopic) {
        practice?.dispose()
        for view in detail.arrangedSubviews { detail.removeArrangedSubview(view); view.removeFromSuperview() }
        let exercise = GuidePracticeView(topic: topic, pasteboard: practicePasteboard)
        practice = exercise
        detail.addArrangedSubview(exercise)
        exercise.widthAnchor.constraint(equalTo: detail.widthAnchor).isActive = true
        window.contentView?.layoutSubtreeIfNeeded()
        detailScroll.contentView.scroll(to: .zero)
        detailScroll.reflectScrolledClipView(detailScroll.contentView)
    }
    static func consumePracticeShortcut(_ event: NSEvent) -> Bool {
        guard let controller = current, controller.window.isKeyWindow else { return false }
        return controller.practice?.consumeShortcut(event) ?? false
    }
    private func refreshShortcut() { shortcut.stringValue = "截图快捷键：\(SettingsManager.currentShortcutString)" }
    func windowDidBecomeKey(_ notification: Notification) { refreshShortcut() }
    @objc private func openSettings() { SetupWindowController.showSettings() }
    @objc private func finish() { window.close() }
    func windowWillClose(_ notification: Notification) {
        practice?.dispose()
        if isFirstRun { SettingsManager.completeSetup(in: defaults) }
        if Self.current === self { Self.current = nil }
    }
}
