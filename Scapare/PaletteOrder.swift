import AppKit

final class PaletteOrder: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    private let type = NSPasteboard.PasteboardType("com.gaoyiming.Scapare.palette-row")
    private var colors: [String]
    private let table = NSTableView()
    init(_ colors: [String]) { self.colors = colors; super.init() }
    static func edit(_ colors: [String]) -> [String]? {
        let controller = PaletteOrder(colors)
        let alert = NSAlert(); alert.messageText = "拖动排列调色板"; alert.informativeText = "拖动一行调整顺序。也可以在外观设置的色值列表中编辑顺序。"
        let column = NSTableColumn(identifier: .init("color")); column.title = "颜色"; column.width = 280; controller.table.addTableColumn(column)
        controller.table.dataSource = controller; controller.table.delegate = controller; controller.table.registerForDraggedTypes([controller.type]); controller.table.setDraggingSourceOperationMask(.move, forLocal: true)
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 240)); scroll.documentView = controller.table; scroll.hasVerticalScroller = true
        alert.accessoryView = scroll; alert.addButton(withTitle: "应用顺序"); alert.addButton(withTitle: "取消")
        return withExtendedLifetime(controller) { alert.runModal() == .alertFirstButtonReturn ? controller.colors : nil }
    }
    func numberOfRows(in tableView: NSTableView) -> Int { colors.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let text = NSTextField(labelWithString: "  #" + colors[row].uppercased())
        text.drawsBackground = true; text.backgroundColor = NSColor(hex: colors[row])
        let color = text.backgroundColor?.usingColorSpace(.sRGB) ?? .white
        text.textColor = color.redComponent * 0.3 + color.greenComponent * 0.59 + color.blueComponent * 0.11 < 0.5 ? .white : .black
        return text
    }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem(); item.setString(String(row), forType: type); return item
    }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        guard info.draggingSource as? NSTableView === tableView else { return [] }
        tableView.setDropRow(row, dropOperation: .above); return .move
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard info.draggingSource as? NSTableView === tableView, let value = info.draggingPasteboard.string(forType: type), let source = Int(value), colors.indices.contains(source), (0...colors.count).contains(row) else { return false }
        let color = colors.remove(at: source), destination = row > source ? row - 1 : row
        colors.insert(color, at: destination); tableView.reloadData(); tableView.selectRowIndexes(IndexSet(integer: destination), byExtendingSelection: false); return true
    }
}
