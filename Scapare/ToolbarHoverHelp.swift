import AppKit

/// Native tooltips can sit behind the shielding-level capture window. Keep help
/// inside the same window, outside the toolbar's clipping scroll view.
@MainActor
final class ToolbarHoverHelp {
    let bubble = ToolbarHelpBubble()

    func show(_ text: String, for control: NSView, in host: NSView) {
        bubble.label.stringValue = text
        bubble.label.sizeToFit()
        let width = min(host.bounds.width - 16, ceil(bubble.label.frame.width) + 28)
        let size = CGSize(width: max(1, width), height: 30)
        let anchor = control.convert(control.bounds, to: host)
        var y = anchor.minY - size.height - 8
        if y < host.bounds.minY + 8 { y = anchor.maxY + 8 }
        let x = max(host.bounds.minX + 8, min(anchor.midX - size.width / 2, host.bounds.maxX - size.width - 8))
        y = max(host.bounds.minY + 8, min(y, host.bounds.maxY - size.height - 8))
        bubble.frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        bubble.label.frame = bubble.bounds.insetBy(dx: 10, dy: 6)
        if bubble.superview !== host { bubble.removeFromSuperview(); host.addSubview(bubble, positioned: .above, relativeTo: nil) }
    }

    func hide() { bubble.removeFromSuperview() }
}

final class ToolbarHelpBubble: NSView {
    let label = NSTextField(labelWithString: "")
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.97).cgColor
        label.font = .systemFont(ofSize: 12)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError("not used") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
