//
//  Annotation.swift
//  SnapTool
//
//  「标注」的数据模型与绘制逻辑。
//  支持五种标注：矩形、椭圆、箭头、画笔(自由涂画)、文字。
//  绘制时假定当前坐标系是「视图坐标」(左下角为原点)，
//  这样屏幕上预览和最终导出图片可以共用同一套绘制代码。
//

import AppKit

enum AnnotationTool: Equatable {
    case rectangle
    case ellipse
    case arrow
    case pen
    case text
}

struct Annotation {
    var tool: AnnotationTool
    var color: NSColor
    var lineWidth: CGFloat

    // 矩形/椭圆/箭头：用起点和终点描述。
    var start: CGPoint = .zero
    var end: CGPoint = .zero

    // 画笔：一连串经过的点。
    var points: [CGPoint] = []

    // 文字：内容、位置、字号、字重、最大宽度（用于多行换行）。
    var text: String = ""
    var fontSize: CGFloat = 14
    var fontWeight: CGFloat = 0          // NSFont.Weight.regular 的 rawValue
    var textMaxWidth: CGFloat?           // nil = 单行不换行

    // 把这个标注画到当前的绘图上下文里。
    func draw() {
        color.set()

        switch tool {
        case .rectangle:
            let path = NSBezierPath(rect: normalizedRect)
            path.lineWidth = lineWidth
            path.stroke()

        case .ellipse:
            let path = NSBezierPath(ovalIn: normalizedRect)
            path.lineWidth = lineWidth
            path.stroke()

        case .arrow:
            drawArrow(from: start, to: end)

        case .pen:
            guard points.count > 1 else { return }
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: points[0])
            for p in points.dropFirst() { path.line(to: p) }
            path.stroke()

        case .text:
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: NSFont.Weight(fontWeight)),
                .foregroundColor: color
            ]
            if let maxW = textMaxWidth {
                let size = (text as NSString).boundingRect(
                    with: NSSize(width: maxW, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs
                ).size
                let drawingRect = CGRect(x: start.x, y: start.y, width: maxW, height: size.height)
                (text as NSString).draw(with: drawingRect,
                                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                                        attributes: attrs)
            } else {
                (text as NSString).draw(at: start, withAttributes: attrs)
            }
        }
    }

    // 起点终点可能任意方向，统一成一个正的矩形。
    var normalizedRect: CGRect {
        CGRect(x: min(start.x, end.x),
               y: min(start.y, end.y),
               width: abs(end.x - start.x),
               height: abs(end.y - start.y))
    }

    /// 文字的包围矩形（视图坐标），用于碰撞检测和把手定位。
    func textBoundingRect() -> CGRect {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: NSFont.Weight(fontWeight)),
            .foregroundColor: color
        ]
        let maxW = textMaxWidth ?? .greatestFiniteMagnitude
        let size = (text as NSString).boundingRect(
            with: NSSize(width: maxW, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs
        ).size
        return CGRect(x: start.x, y: start.y, width: size.width, height: size.height)
    }

    private func drawArrow(from: CGPoint, to: CGPoint) {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = max(1, hypot(dx, dy))
        let angle = atan2(dy, dx)

        // 箭头头部的大小随线宽放大。
        let headLength = min(length, 12 + lineWidth * 3)
        let headAngle = CGFloat.pi / 7

        let line = NSBezierPath()
        line.lineWidth = lineWidth
        line.lineCapStyle = .round
        line.move(to: from)
        line.line(to: to)
        line.stroke()

        // 两条斜线组成箭头。
        let p1 = CGPoint(x: to.x - headLength * cos(angle - headAngle),
                         y: to.y - headLength * sin(angle - headAngle))
        let p2 = CGPoint(x: to.x - headLength * cos(angle + headAngle),
                         y: to.y - headLength * sin(angle + headAngle))
        let head = NSBezierPath()
        head.lineWidth = lineWidth
        head.lineCapStyle = .round
        head.lineJoinStyle = .round
        head.move(to: p1)
        head.line(to: to)
        head.line(to: p2)
        head.stroke()
    }
}
