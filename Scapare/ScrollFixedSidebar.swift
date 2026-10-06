import CoreGraphics

/// A pane has its own captured content, independent of document displacement.
/// Keep that content once at its page's start and extend its plain background.
nonisolated struct ScrollFixedSidebar: Sendable {
    let columns: Range<Int>
    let pixels: PixelRaster
    let background: PixelRaster
    init(columns: Range<Int>, pixels: PixelRaster, background: PixelRaster) {
        self.columns = columns; self.pixels = pixels; self.background = background
    }

    struct Detection {
        let ranges: [Range<Int>]
        let panes: [Range<Int>]
        let moving: [Bool]
    }

    /// Compare both hypotheses: a pane stays at screen coordinates; document
    /// pixels follow the already-verified displacement. Local hover/loading
    /// changes cannot veto all the remaining stationary text in a column.
    static func detect(_ first: PixelRaster, _ next: PixelRaster, top: Int, bottom: Int, shift: Int) -> Detection {
        let lower = top, upper = first.height - bottom, width = first.width
        guard upper - lower >= 96, shift != 0 else {
            return Detection(ranges: [], panes: [], moving: [Bool](repeating: false, count: width))
        }
        let step = max(1, (upper - lower) / 480)
        let rows = Array(stride(from: lower, to: upper, by: step))
        var stable = [Bool](repeating: false, count: width)
        var evidence = [Int](repeating: 0, count: width)
        var nonflat = [Bool](repeating: false, count: width)
        var stationary = [Bool](repeating: false, count: width)
        var comparableCounts = [Int](repeating: 0, count: width)
        var stationaryCounts = comparableCounts, shiftedCounts = comparableCounts
        var moving = [Bool](repeating: false, count: width)
        first.bytes.withUnsafeBufferPointer { a in
            next.bytes.withUnsafeBufferPointer { b in
                for x in 0..<width {
                    var changes = 0, faintEdges = 0
                    var comparable = 0, shiftedMatches = 0, stationaryMatches = 0
                    for sampleY in rows {
                        // Cover each block's strongest physical edge rather
                        // than skipping one-pixel rules between sample rows.
                        var y = sampleY, edge = 0
                        for candidate in sampleY..<min(upper, sampleY+step) where candidate > lower {
                            let i = (candidate * width + x) * 4
                            var gradient = 0
                            for c in 0..<3 { gradient = max(gradient, abs(Int(a[i+c]) - Int(a[i-width*4+c]))) }
                            if gradient > edge { edge = gradient; y = candidate }
                        }
                        let i = (y * width + x) * 4
                        var change = 0
                        for c in 0..<3 {
                            change = max(change, abs(Int(a[i+c]) - Int(b[i+c])))
                        }
                        if change > 2 { changes += 1 }
                        if edge > 2 { faintEdges += 1 }
                        if edge > 8 {
                            let shiftedY = y - shift
                            if shiftedY >= lower, shiftedY < upper {
                                comparable += 1
                                let j = (shiftedY * width + x) * 4
                                var shifted = 0, stationaryChange = change
                                for c in 0..<3 {
                                    shifted = max(shifted, abs(Int(a[i+c]) - Int(b[j+c])))
                                    // The neighboring pixel generated the edge
                                    // too. Comparing only its white side would
                                    // falsely classify faint body text as fixed.
                                    if y > lower, shiftedY > lower {
                                        shifted = max(shifted, abs(Int(a[i-width*4+c]) - Int(b[j-width*4+c])))
                                        stationaryChange = max(stationaryChange, abs(Int(a[i-width*4+c]) - Int(b[i-width*4+c])))
                                    }
                                }
                                if shifted <= 8 { shiftedMatches += 1 }
                                if stationaryChange <= 8 { stationaryMatches += 1 }
                                if stationaryChange <= 8, shifted > 8 { evidence[x] += 1 }
                            }
                        }
                    }
                    // Flat margins can join proven ink, but cannot prove a pane
                    // themselves. A local highlight must not split one pane
                    // into narrow glyph fragments. The shifted-motion veto and
                    // stationary texture evidence below decide its identity.
                    stable[x] = changes <= max(1, rows.count / 8)
                    nonflat[x] = faintEdges >= 1
                    comparableCounts[x] = comparable
                    stationaryCounts[x] = stationaryMatches; shiftedCounts[x] = shiftedMatches
                }
            }
        }
        // A glyph's faint edge can occupy only one sampled row in a column.
        // Decide motion with a small horizontal neighborhood so that column
        // cannot veto a whole pane or join a body gutter on its own.
        let radius = max(2, width / 500)
        for x in 0..<width {
            let neighbors = max(0, x-radius)..<min(width, x+radius+1)
            let comparable = neighbors.reduce(0) { $0 + comparableCounts[$1] }
            let still = neighbors.reduce(0) { $0 + stationaryCounts[$1] }
            let shifted = neighbors.reduce(0) { $0 + shiftedCounts[$1] }
            let proof = neighbors.reduce(0) { $0 + evidence[$1] }
            if comparable >= 2, still * 4 >= comparable * 3, proof >= 2 { stationary[x] = true }
            // Repainting remains reversible: raw body strips stay underneath.
            moving[x] = comparable >= 8 && shifted * 10 >= comparable * 8 && still * 10 < comparable * 7
        }
        var ranges: [Range<Int>] = [], panes: [Range<Int>] = []
        var start = 0
        while start < width {
            guard stable[start], !moving[start] else { start += 1; continue }
            var end = start + 1
            while end < width, stable[end], !moving[end] { end += 1 }
            let ink = (start..<end).filter { nonflat[$0] && stationary[$0] }
            if let left = ink.first, let right = ink.last {
                // Small bearings can first appear in another menu item. Stay
                // inside the proven stationary run, never across moving ink.
                let paddedLeft = max(start, left-2)
                let paddedRight = min(end, right+3)
                let pane = paddedLeft..<paddedRight
                let supported = pane.filter { evidence[$0] >= 2 }.count
                // No three-band requirement: a short navigation menu is a
                // legitimate pane too. Repeated table labels have no evidence
                // because they also agree at the document displacement.
                if pane.count >= max(24, width / 80), pane.count < width * 3 / 4,
                   supported >= max(4, width / 400),
                   pane.reduce(0, { $0 + evidence[$1] }) >= max(24, width / 40) {
                    ranges.append(pane); panes.append(start..<end)
                }
            }
            start = end
        }
        return Detection(ranges: ranges, panes: panes, moving: moving)
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

/// Each page owns its own tracker. Only validated scrolling frames can teach
/// it geometry; a failed match or a page switch never contaminates another page.
nonisolated struct ScrollSidebarTracker: Sendable {
    private let source: PixelRaster
    private var reference: PixelRaster
    private var position = 0.0
    private var didObserve = false
    private var fixed: [Bool]
    private var document: [Bool]
    private(set) var exclusions: [Range<Int>] = []
    private var cached: [ScrollFixedSidebar] = []
    private var cachedTop = -1
    private var cachedBottom = -1
    private var needsRender = true
    private var candidates: [Range<Int>] = []
    private var tracked: [ScrollTrackedSidebar] = []
    private(set) var revision = 0

    init(first: PixelRaster) {
        source = first; reference = first
        fixed = [Bool](repeating: false, count: first.width)
        document = fixed
    }
    mutating func observe(_ next: PixelRaster, position nextPosition: Double, top: Int, bottom: Int) {
        let distance = nextPosition - position
        // Detection keeps working during motion. Limit its cadence by distance,
        // not by waiting for a pause or processing every fractional pixel frame.
        guard didObserve ? abs(distance) >= Double(max(8, min(24, next.height / 40))) : Int(distance.rounded()) != 0 else { return }
        let detection = ScrollFixedSidebar.detect(reference, next, top: top, bottom: bottom, shift: Int(distance.rounded()))
        for x in document.indices where detection.moving[x] {
            document[x] = true
            if fixed[x] { fixed[x] = false; needsRender = true; revision += 1 }
        }
        for range in detection.ranges {
            for x in range where !document[x] && !fixed[x] { fixed[x] = true; needsRender = true; revision += 1 }
        }
        tracked = tracked.map { pane in
            let advanced = pane.advanced(next)
            if advanced.changed { revision += 1 }
            return advanced.pane
        }
        candidates = detection.ranges
        exclusions = detection.panes
        reference = next; position = nextPosition; didObserve = true
    }
    var ranges: [Range<Int>] {
        var result: [Range<Int>] = [], start = 0
        while start < fixed.count {
            guard fixed[start] else { start += 1; continue }
            var end = start + 1
            while end < fixed.count, fixed[end] { end += 1 }
            result.append(start..<end); start = end
        }
        return result
    }
    mutating func overlays(top: Int, bottom: Int, maximumHeight: Int) -> [ScrollFixedSidebar] {
        for columns in candidates where columns.count >= 32 {
            if let index = tracked.firstIndex(where: { $0.sidebar.columns.overlaps(columns) }) {
                let old = tracked[index].sidebar.columns
                let expanded = min(old.lowerBound, columns.lowerBound)..<max(old.upperBound, columns.upperBound)
                if expanded != old, let pane = tracked[index].expanded(to: expanded), pane.sidebar.pixels.height <= maximumHeight {
                    tracked[index] = pane; needsRender = true; revision += 1
                }
                continue
            }
            guard let pane = ScrollTrackedSidebar(first: source, current: reference, columns: columns, top: top, bottom: bottom),
                  pane.sidebar.pixels.height <= maximumHeight else { continue }
            tracked.append(pane); needsRender = true; revision += 1
        }
        if needsRender || top != cachedTop || bottom != cachedBottom {
            cached = ranges.filter { range in !tracked.contains { $0.sidebar.columns.overlaps(range) } }
                .map { ScrollFixedSidebar(source: source, columns: $0, top: top, bottom: bottom) }
            cachedTop = top; cachedBottom = bottom; needsRender = false
        }
        return cached + tracked.filter { $0.sidebar.pixels.height <= maximumHeight }.map(\.sidebar)
    }
}

/// A sidebar may scroll with the document before sticking, or become unstuck
/// on reversal. Give it its own verified coordinate system. Immutable wrappers
/// preserve transactionality when the parent later rejects a frame or limit.
nonisolated final class ScrollTrackedSidebar: Sendable {
    let sidebar: ScrollFixedSidebar
    private let state: ScrollStitcher
    private let top: Int
    private let bottom: Int
    private let minimumFrame: PixelRaster
    private let maximumFrame: PixelRaster

    init?(first: PixelRaster, current: PixelRaster, columns: Range<Int>, top: Int, bottom: Int) {
        let original = Self.crop(first, columns: columns, top: top, bottom: bottom)
        var state = ScrollStitcher(first: original, tracksSidebars: false)
        do { _ = try state.append(Self.crop(current, columns: columns, top: top, bottom: bottom)) }
        catch { return nil }
        let pixels = Self.pixels(state)
        let base = ScrollFixedSidebar(source: original, columns: 0..<original.width, top: 0, bottom: 0)
        sidebar = ScrollFixedSidebar(columns: columns, pixels: pixels, background: base.background)
        self.state = state; self.top = top; self.bottom = bottom
        minimumFrame = state.capturedPositions.minimum < 0 ? current : first
        maximumFrame = state.capturedPositions.maximum > 0 ? current : first
    }
    private init(state: ScrollStitcher, sidebar: ScrollFixedSidebar, top: Int, bottom: Int, minimumFrame: PixelRaster, maximumFrame: PixelRaster) {
        self.state = state; self.sidebar = sidebar; self.top = top; self.bottom = bottom
        self.minimumFrame = minimumFrame; self.maximumFrame = maximumFrame
    }
    func advanced(_ raster: PixelRaster) -> (pane: ScrollTrackedSidebar, changed: Bool) {
        let viewport = Self.crop(raster, columns: sidebar.columns, top: top, bottom: bottom)
        if ScrollMatcher.isUnchanged(state.previous, viewport) { return (self, false) }
        var next = state
        do {
            let changed = try next.append(viewport)
            let output = changed ? ScrollFixedSidebar(columns: sidebar.columns, pixels: Self.pixels(next), background: sidebar.background) : sidebar
            return (Self(state: next, sidebar: output, top: top, bottom: bottom,
                minimumFrame: next.capturedPositions.minimum < state.capturedPositions.minimum ? raster : minimumFrame,
                maximumFrame: next.capturedPositions.maximum > state.capturedPositions.maximum ? raster : maximumFrame), changed)
        } catch { return (self, false) }
    }
    func expanded(to columns: Range<Int>) -> ScrollTrackedSidebar? {
        // Preserve both captured endpoints, including labels found before a
        // reversal; never replace a long pane with only the latest viewport.
        Self(first: minimumFrame, current: maximumFrame, columns: columns, top: top, bottom: bottom)
    }
    private static func pixels(_ state: ScrollStitcher) -> PixelRaster {
        let pieces = state.result
        return PixelRaster(width: pieces.width, height: pieces.height, bytes: pieces.strips.flatMap(\.bytes))
    }
    private static func crop(_ raster: PixelRaster, columns: Range<Int>, top: Int, bottom: Int) -> PixelRaster {
        var bytes: [UInt8] = []; bytes.reserveCapacity(columns.count * (raster.height-top-bottom) * 4)
        for y in top..<(raster.height-bottom) {
            bytes.append(contentsOf: raster.bytes[((y*raster.width+columns.lowerBound)*4)..<((y*raster.width+columns.upperBound)*4)])
        }
        return PixelRaster(width: columns.count, height: raster.height-top-bottom, bytes: bytes)
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
