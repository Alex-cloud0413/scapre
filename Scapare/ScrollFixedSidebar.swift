import CoreGraphics

/// A stationary textured pane is screen content, not another document strip.
/// Keep it once at the start of its page and extend only its plain background.
nonisolated struct ScrollFixedSidebar: Sendable {
    let columns: Range<Int>
    let pixels: PixelRaster
    let background: PixelRaster

    static func detect(_ first: PixelRaster, _ next: PixelRaster, top: Int, bottom: Int, shift: Int) -> [Range<Int>] {
        let lower = top, upper = first.height - bottom
        guard upper - lower >= 96, shift != 0 else { return [] }
        let step = max(1, (upper - lower) / 600)
        let rows = Array(stride(from: lower, to: upper, by: step))
        var stable = [Bool](repeating: false, count: first.width)
        var textured = [Bool](repeating: false, count: first.width)
        var nonflat = [Bool](repeating: false, count: first.width)
        for x in 0..<first.width {
            var changes = 0, edges = 0, faintEdges = 0, bands = Set<Int>()
            for y in rows {
                let i = (y * first.width + x) * 4
                var change = 0, edge = 0
                for c in 0..<3 {
                    change = max(change, abs(Int(first.bytes[i+c]) - Int(next.bytes[i+c])))
                    if y > lower { edge = max(edge, abs(Int(first.bytes[i+c]) - Int(first.bytes[i - first.width * 4+c]))) }
                }
                if change > 2 { changes += 1 }
                if edge > 2 { faintEdges += 1 }
                if edge > 8 { edges += 1; bands.insert(min(3, (y - lower) * 4 / (upper - lower))) }
            }
            stable[x] = changes <= max(1, rows.count / 200)
            textured[x] = edges >= max(8, rows.count / 60) && bands.count >= 3
            nonflat[x] = faintEdges >= 2
        }
        var ranges: [Range<Int>] = []
        var start = 0
        while start < first.width {
            guard stable[start] else { start += 1; continue }
            var end = start + 1
            while end < first.width, stable[end] { end += 1 }
            let range = start..<end
            // Flat margins and small stationary icons cannot erase future body
            // content. A pane needs coherent, vertically distributed texture.
            if range.count >= max(24, first.width / 40),
               range.count < first.width * 3 / 4,
               range.filter({ textured[$0] }).count >= max(4, first.width / 160) {
                // Blank gutters can later contain a longer line of document
                // text. Only paint the stationary ink/decoration envelope;
                // uniform pane margins already extend without any artifacts.
                let ink = range.filter { nonflat[$0] }
                if let left = ink.first, let right = ink.last {
                    let pane = left..<(right + 1)
                    // Repeated table labels can look stationary when a scroll
                    // moves exactly one row. If the same pixels also agree at
                    // the verified document displacement, retain them as body.
                    var differences = 0, bands = Set<Int>()
                    let start = max(lower, lower + shift), finish = min(upper, upper + shift)
                    for y in stride(from: start, to: finish, by: max(1, (finish - start) / 180)) {
                        for x in stride(from: pane.lowerBound, to: pane.upperBound, by: max(1, pane.count / 80)) {
                            let i = (y * first.width + x) * 4, j = ((y - shift) * next.width + x) * 4
                            if (0..<3).contains(where: { abs(Int(first.bytes[i+$0]) - Int(next.bytes[j+$0])) > 8 }) {
                                differences += 1; bands.insert(min(3, (y - start) * 4 / max(1, finish - start)))
                            }
                        }
                    }
                    if differences >= 24, bands.count >= 2 { ranges.append(pane) }
                }
            }
            start = end
        }
        return ranges
    }

    init(source: PixelRaster, columns: Range<Int>, top: Int, bottom: Int) {
        self.columns = columns
        let rows = top..<(source.height - bottom)
        var bytes = [UInt8](); bytes.reserveCapacity(columns.count * rows.count * 4)
        for y in rows {
            bytes.append(contentsOf: source.bytes[((y * source.width + columns.lowerBound) * 4)..<((y * source.width + columns.upperBound) * 4)])
        }
        pixels = PixelRaster(width: columns.count, height: rows.count, bytes: bytes)
        var colors = [UInt8](); colors.reserveCapacity(columns.count * 4)
        for x in 0..<columns.count {
            var counts: [UInt32: Int] = [:]
            for y in 0..<rows.count {
                let i = (y * columns.count + x) * 4
                let color = UInt32(bytes[i]) << 24 | UInt32(bytes[i+1]) << 16 | UInt32(bytes[i+2]) << 8 | UInt32(bytes[i+3])
                counts[color, default: 0] += 1
            }
            // Deterministic ties; no glyph stretching or repeated last text row.
            let color = counts.keys.max { a, b in counts[a]! == counts[b]! ? a < b : counts[a]! < counts[b]! }!
            colors += [UInt8(color >> 24), UInt8((color >> 16) & 255), UInt8((color >> 8) & 255), UInt8(color & 255)]
        }
        background = PixelRaster(width: columns.count, height: 1, bytes: colors)
    }
}

nonisolated struct ScrollSidebarOverlay: Sendable {
    let sidebar: ScrollFixedSidebar
    let top: Int
    let height: Int
    func offset(by rows: Int) -> Self { Self(sidebar: sidebar, top: top + rows, height: height) }
    func apply(to bytes: inout [UInt8], width: Int) {
        for row in 0..<height {
            let start = ((top + row) * width + sidebar.columns.lowerBound) * 4
            let source = row < sidebar.pixels.height ? sidebar.pixels : sidebar.background
            let sourceStart = row < sidebar.pixels.height ? row * source.width * 4 : 0
            bytes.replaceSubrange(start..<(start + source.width * 4),
                with: source.bytes[sourceStart..<(sourceStart + source.width * 4)])
        }
    }
    func draw(in context: CGContext, outputHeight: Int, xScale: CGFloat, yScale: CGFloat) {
        let x = CGFloat(sidebar.columns.lowerBound) * xScale, width = CGFloat(sidebar.columns.count) * xScale
        if let background = sidebar.background.image() {
            context.draw(background, in: CGRect(x: x, y: CGFloat(outputHeight - top - height) * yScale,
                width: width, height: CGFloat(height) * yScale))
        }
        if let image = sidebar.pixels.image() {
            context.draw(image, in: CGRect(x: x, y: CGFloat(outputHeight - top - sidebar.pixels.height) * yScale,
                width: width, height: CGFloat(sidebar.pixels.height) * yScale))
        }
    }
}
