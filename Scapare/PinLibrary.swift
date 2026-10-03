import AppKit

final class PinLibrary: NSObject, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private static var current: PinLibrary?
    private let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 980, height: 450), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    private let table = NSTableView()
    private let groupFilter = NSPopUpButton()
    private var activeGroup: String?
    private let status = NSTextField(labelWithString: "")
    private var rows: [PinWindowController] { PinManager.shared.controllers.filter { activeGroup == nil || $0.record.group == activeGroup } }
    static func show() {
        if let current { current.window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let instance = PinLibrary(); current = instance; instance.window.center(); instance.window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    private override init() {
        super.init()
        window.title = "贴图库 · Scapare"; window.minSize = NSSize(width: 920, height: 350); window.isReleasedWhenClosed = false; window.delegate = self
        for (id, title, width) in [("title", "名称", 260.0), ("group", "分组", 180.0), ("state", "状态", 260.0)] {
            let column = NSTableColumn(identifier: .init(id)); column.title = title; column.width = width; table.addTableColumn(column)
        }
        table.dataSource = self; table.delegate = self; table.allowsMultipleSelection = true; table.usesAlternatingRowBackgroundColors = true
        table.target = self; table.doubleAction = #selector(editSelected)
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.translatesAutoresizingMaskIntoConstraints = false
        let actions = [("显示", #selector(showSelected)), ("隐藏", #selector(hideSelected)), ("编辑", #selector(editSelected)), ("分组…", #selector(groupSelected)), ("移动…", #selector(moveSelected)), ("移除", #selector(removeSelected)), ("导出…", #selector(exportSelected)), ("导入…", #selector(importPins))]
        let buttons = NSStackView(views: actions.map { NSButton(title: $0.0, target: self, action: $0.1) }); buttons.spacing = 8; buttons.translatesAutoresizingMaskIntoConstraints = false
        let transformations = NSPopUpButton(frame: .zero, pullsDown: true); transformations.addItem(withTitle: "变换所选")
        for (title, action) in [("旋转 90°", "right"), ("水平翻转", "horizontal"), ("垂直翻转", "vertical"), ("灰度", "gray"), ("反色", "invert"), ("缩略图", "thumbnail")] {
            let item = NSMenuItem(title: title, action: #selector(transformSelected(_:)), keyEquivalent: ""); item.target = self; item.representedObject = action; transformations.menu?.addItem(item)
        }
        buttons.addArrangedSubview(transformations)
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor; status.translatesAutoresizingMaskIntoConstraints = false
        groupFilter.target = self; groupFilter.action = #selector(filterChanged); groupFilter.setAccessibilityLabel("贴图分组")
        groupFilter.translatesAutoresizingMaskIntoConstraints = false
        let showGroup = NSButton(title: "只显示本组贴图", target: self, action: #selector(showGroupOnly)); showGroup.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView(); [groupFilter, showGroup, scroll, buttons, status].forEach { content.addSubview($0) }; window.contentView = content
        NSLayoutConstraint.activate([groupFilter.topAnchor.constraint(equalTo: content.topAnchor, constant: 12), groupFilter.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12), showGroup.leadingAnchor.constraint(equalTo: groupFilter.trailingAnchor, constant: 12), showGroup.centerYAnchor.constraint(equalTo: groupFilter.centerYAnchor), scroll.topAnchor.constraint(equalTo: groupFilter.bottomAnchor, constant: 12), scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12), scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12), scroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -12), buttons.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12), buttons.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -12), status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12), status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)])
        PinManager.shared.onChange = { [weak self] in self?.reload() }; reload()
    }
    private var selected: [PinWindowController] { table.selectedRowIndexes.compactMap { rows.indices.contains($0) ? rows[$0] : nil } }
    private func reload() {
        let ids = Set(selected.map { $0.record.id })
        let groups = Set(PinManager.shared.controllers.map { $0.record.group }).sorted()
        groupFilter.removeAllItems(); groupFilter.addItem(withTitle: "全部分组"); groupFilter.addItems(withTitles: groups)
        if let activeGroup, groups.contains(activeGroup) { groupFilter.selectItem(withTitle: activeGroup) } else { activeGroup = nil }
        table.reloadData()
        table.selectRowIndexes(IndexSet(rows.indices.filter { ids.contains(rows[$0].record.id) }), byExtendingSelection: false)
        status.stringValue = PinManager.shared.lastSaveError.map { "自动备份失败：" + $0 } ?? "\(rows.count) 张贴图 · 按住 ⌘ / Shift 多选 · 双击编辑 · 隐藏的贴图可重新显示"
    }
    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }
    func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        let record = rows[row].record
        let text: String
        switch column?.identifier.rawValue {
        case "group": text = record.group
        case "state": text = (record.hidden ? "隐藏" : "显示") + " · \(Int(record.opacity * 100))%" + (rows[row].window.ignoresMouseEvents ? " · 鼠标穿透" : "")
        default: text = record.title
        }
        return NSTextField(labelWithString: text)
    }
    @objc private func transformSelected(_ item: NSMenuItem) {
        guard let action = item.representedObject as? String else { return }; let targets = selected; targets.forEach { $0.action(action) }
    }
    @objc private func filterChanged() { activeGroup = groupFilter.indexOfSelectedItem == 0 ? nil : groupFilter.titleOfSelectedItem; reload() }
    @objc private func showGroupOnly() {
        for controller in PinManager.shared.controllers { controller.setHidden(activeGroup != nil && controller.record.group != activeGroup) }
    }
    @objc private func showSelected() { selected.forEach { $0.setHidden(false) } }
    @objc private func hideSelected() { selected.forEach { $0.setHidden(true) } }
    @objc private func editSelected() { selected.first?.edit() }
    @objc private func groupSelected() {
        let targets = selected; guard !targets.isEmpty, let v = AppDialogs.fields(title: "移动到分组", labels: ["分组名"], values: [targets.first?.record.group ?? "默认"]) else { return }
        targets.forEach { $0.setGroup(v[0].isEmpty ? "默认" : v[0]) }
    }
    @objc private func moveSelected() {
        let targets = selected; guard !targets.isEmpty, let v = AppDialogs.fields(title: "整体移动（点）", labels: ["水平偏移", "垂直偏移"], values: ["0", "0"]), let x = Double(v[0]), let y = Double(v[1]), x.isFinite, y.isFinite, abs(x) <= 20_000, abs(y) <= 20_000 else { return }
        for target in targets { target.window.setFrameOrigin(CGPoint(x: target.window.frame.minX + x, y: target.window.frame.minY + y)) }
    }
    @objc private func removeSelected() {
        let ids = Set(selected.map { $0.record.id }); guard !ids.isEmpty else { return }
        let alert = NSAlert(); alert.messageText = "移除 \(ids.count) 张贴图？"; alert.informativeText = "只想暂时收起时，请使用「隐藏」。需要留档可以先导出贴图备份。"
        alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "移除")
        if alert.runModal() == .alertSecondButtonReturn { PinManager.shared.remove(ids) }
    }
    @objc private func exportSelected() { PinManager.shared.exportPins(selected.isEmpty ? nil : selected.map(\.record)) }
    @objc private func importPins() { PinManager.shared.importPins() }
    func windowWillClose(_ notification: Notification) { PinManager.shared.onChange = nil; Self.current = nil }
}
