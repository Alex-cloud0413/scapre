import Foundation

nonisolated enum ScrollMatch: Equatable { case unchanged, advance(Int) }

/// Row descriptors are calculated once per image. Search uses textured rows;
/// blank margins cannot vote for an arbitrary scroll distance.
nonisolated struct ScrollFeatures: Sendable {
    static let columns = 48
    let height: Int
    let values: [Int16]
    let smoothedValues: [Int16]
    let energy: [Int]
    init(_ raster: PixelRaster) {
        height = raster.height
        var values = [Int16](repeating: 0, count: height * Self.columns)
        var energy = [Int](repeating: 0, count: height)
        for y in 0..<height {
            for c in 0..<Self.columns {
                let x = min(raster.width - 2, max(1, raster.width / 16 + c * (raster.width * 7 / 8) / Self.columns))
                let value = (raster.luminance(x - 1, y) + 2 * raster.luminance(x, y) + raster.luminance(x + 1, y)) / 4
                values[y * Self.columns + c] = Int16(value)
                if c > 0 { energy[y] += abs(value - Int(values[y * Self.columns + c - 1])) }
                // Window borders and shadows are often uniform across a row.
                // Their vertical gradient is texture too; otherwise a stationary
                // gray footer is appended for every document movement.
                if y > 0 { energy[y] += abs(value - Int(values[(y - 1) * Self.columns + c])) }
            }
        }
        self.values = values
        self.energy = energy
        // Browser scrolling resamples glyphs at fractional physical pixels.
        // Blur only the search descriptors; captured/output pixels stay intact.
        smoothedValues = (0..<values.count).map { i in
            let y = i / Self.columns, c = i % Self.columns
            return Int16((Int(values[max(0, y - 1) * Self.columns + c]) + 2 * Int(values[i])
                + Int(values[min(raster.height - 1, y + 1) * Self.columns + c])) / 4)
        }
    }
    func distance(row: Int, to other: ScrollFeatures, row otherRow: Int, columns: [Int]? = nil) -> Double {
        var total = 0
        let a = row * Self.columns, b = otherRow * Self.columns
        if let columns {
            for c in columns { total += abs(Int(smoothedValues[a+c]) - Int(other.smoothedValues[b+c])) }
            return Double(total) / Double(columns.count)
        }
        for c in 0..<Self.columns { total += abs(Int(values[a+c]) - Int(other.values[b+c])) }
        return Double(total) / Double(Self.columns)
    }
    func texture(row: Int, columns: [Int]) -> Int {
        let start = row * Self.columns
        var result = 0
        for pair in zip(columns, columns.dropFirst()) where pair.1 == pair.0 + 1 {
            result += abs(Int(values[start + pair.0]) - Int(values[start + pair.1]))
        }
        return result
    }
}

nonisolated enum ScrollMatcher {
    static func isUnchanged(_ previous: PixelRaster, _ next: PixelRaster) -> Bool {
        guard previous.width == next.width, previous.height == next.height else { return false }
        // Include color and a dense grid: sparse white samples can miss entire text rows.
        var difference = 0, samples = 0
        for y in stride(from: 0, to: previous.height, by: max(1, previous.height / 180)) {
            for x in stride(from: 0, to: previous.width, by: max(1, previous.width / 96)) {
                let i = (y * previous.width + x) * 4
                for c in 0..<3 { difference += abs(Int(previous.bytes[i+c]) - Int(next.bytes[i+c])); samples += 1 }
            }
        }
        return samples > 0 && Double(difference) / Double(samples) < 0.15
    }

    static func match(_ previous: PixelRaster, _ next: PixelRaster) throws -> ScrollMatch {
        let shift = try displacement(previous, next)
        guard shift >= 0 else { throw ImageError.noOverlap }
        return shift == 0 ? .unchanged : .advance(shift)
    }

    static func displacement(_ previous: PixelRaster, _ next: PixelRaster,
                             previousFeatures: ScrollFeatures? = nil, nextFeatures: ScrollFeatures? = nil,
                             excludingTop top: Int = 0, bottom: Int = 0, allowRegistration: Bool = true) throws -> Int {
        let a = previousFeatures ?? ScrollFeatures(previous), b = nextFeatures ?? ScrollFeatures(next)
        do {
            return try descriptorDisplacement(previous, next, previousFeatures: a, nextFeatures: b,
                                              excludingTop: top, bottom: bottom)
        } catch ImageError.noOverlap where allowRegistration {
            return try registeredDisplacement(previous, next, previousFeatures: a, nextFeatures: b,
                                              excludingTop: top, bottom: bottom)
        }
    }

    static func descriptorDisplacement(_ previous: PixelRaster, _ next: PixelRaster,
                             previousFeatures: ScrollFeatures? = nil, nextFeatures: ScrollFeatures? = nil,
                             excludingTop top: Int = 0, bottom: Int = 0) throws -> Int {
        guard previous.width == next.width, previous.height == next.height,
              previous.width >= 32, previous.height >= 64 else { throw ImageError.incompatible }
        if isUnchanged(previous, next) { return 0 }
        let a = previousFeatures ?? ScrollFeatures(previous), b = nextFeatures ?? ScrollFeatures(next)
        let h = previous.height
        let margin = max(2, h / 100)
        let lower = max(top, margin), upper = h - max(bottom, margin)
        let minimumOverlap = max(40, (upper - lower) / 5)
        let maximumShift = upper - lower - minimumOverlap
        guard maximumShift > 0 else { throw ImageError.incompatible }
        // A stationary browser sidebar has plenty of edges but cannot vote on
        // document motion. Select columns with changes spread over several rows;
        // a blinking caret or a single changing badge is insufficient evidence.
        let columns = movingColumns(a, b, lower: lower, upper: upper)
        guard columns.count >= 3 else { throw ImageError.ambiguous }
        // Pick a textured anchor in each vertical band, preserving coverage across
        // the page. Cost is linear in height, not full-resolution pixels × offsets.
        let bands = 32
        let texture = (0..<h).map { a.texture(row: $0, columns: columns) }
        var anchors: [Int] = []
        for band in 0..<bands {
            let start = lower + (upper - lower) * band / bands
            let end = lower + (upper - lower) * (band + 1) / bands
            if let y = (start..<end).max(by: { texture[$0] < texture[$1] }), texture[y] > 80 { anchors.append(y) }
        }
        guard anchors.count >= 4 else { throw ImageError.ambiguous }
        var candidates: [(shift: Int, score: Double)] = []
        for shift in -maximumShift...maximumShift {
            var scores: [Double] = []
            for y in anchors where y - shift >= lower && y - shift < upper {
                scores.append(a.distance(row: y, to: b, row: y - shift, columns: columns))
            }
            if scores.count >= 4 {
                scores.sort()
                let reliable = scores.prefix(max(4, scores.count * 4 / 5))
                candidates.append((shift, reliable.reduce(0, +) / Double(reliable.count)))
            }
        }
        candidates.sort { $0.score < $1.score }
        // This stage only proposes positions. Fractionally resampled dark glyphs
        // can exceed the old cutoff; dense verification still decides acceptance.
        guard let best = candidates.first, best.score < 24 else { throw ImageError.noOverlap }
        // Blank space can make different text rows look equally good in the
        // coarse descriptors. Resolve those candidates using dense ink/edge checks.
        var distinct: [(shift: Int, score: Double)] = []
        for candidate in candidates where candidate.score < best.score + max(2, best.score * 0.5) {
            if distinct.allSatisfy({ abs($0.shift - candidate.shift) > 3 }) { distinct.append(candidate) }
            if distinct.count == 10 { break }
        }
        let verified = distinct.compactMap { candidate -> (shift: Int, score: Double)? in
            guard let score = try? verify(previous, next, shift: candidate.shift, top: lower, bottom: h - upper, columns: columns) else { return nil }
            return (candidate.shift, score)
        }.sorted { $0.score < $1.score }
        guard let winner = verified.first else { throw ImageError.noOverlap }
        if verified.count > 1, verified[1].score < winner.score + max(0.75, winner.score * 0.35) { throw ImageError.ambiguous }
        return winner.shift
    }

    static func registeredDisplacement(_ previous: PixelRaster, _ next: PixelRaster,
                             previousFeatures: ScrollFeatures? = nil, nextFeatures: ScrollFeatures? = nil,
                             excludingTop top: Int = 0, bottom: Int = 0) throws -> Int {
        guard previous.width == next.width, previous.height == next.height,
              previous.width >= 32, previous.height >= 64 else { throw ImageError.incompatible }
        let a = previousFeatures ?? ScrollFeatures(previous), b = nextFeatures ?? ScrollFeatures(next)
        let margin = max(2, previous.height / 100)
        let lower = max(top, margin), upper = previous.height - max(bottom, margin)
        let maximumShift = upper - lower - max(40, (upper - lower) / 5)
        guard maximumShift > 0 else { throw ImageError.incompatible }
        let columns = movingColumns(a, b, lower: lower, upper: upper)
        guard columns.count >= 3 else { throw ImageError.ambiguous }
        let verified = ScrollRegistration.proposals(previous, next, top: lower, bottom: previous.height - upper,
            columns: columns, maximumShift: maximumShift).compactMap { shift -> (shift: Int, score: Double)? in
                guard let score = try? verify(previous, next, shift: shift, top: lower,
                    bottom: previous.height - upper, columns: columns) else { return nil }
                return (shift, score)
            }.sorted { $0.score < $1.score }
        guard let winner = verified.first else { throw ImageError.noOverlap }
        if verified.contains(where: { abs($0.shift - winner.shift) > 3
            && $0.score < winner.score + max(0.75, winner.score * 0.35) }) { throw ImageError.ambiguous }
        return winner.shift
    }

    /// Recent frames establish the correspondence. The older anchor only
    /// refines rounding near that position; it must not search the whole page
    /// and silently choose a similar paragraph after its overlap is lost.
    static func refine(_ previous: PixelRaster, _ next: PixelRaster, around proposal: Double,
                       previousFeatures a: ScrollFeatures, nextFeatures b: ScrollFeatures,
                       excludingTop top: Int, bottom: Int) throws -> Double {
        let margin = max(2, previous.height / 100)
        let lower = max(top, margin), upper = previous.height - max(bottom, margin)
        let maximumShift = upper - lower - max(40, (upper - lower) / 5)
        guard abs(proposal) <= Double(maximumShift) else { throw ImageError.noOverlap }
        if proposal == 0, isUnchanged(previous, next) { return 0 }
        let columns = movingColumns(a, b, lower: lower, upper: upper)
        guard columns.count >= 3 else { throw ImageError.ambiguous }
        let center = Int(proposal.rounded())
        let verified = ((center - 1)...(center + 1)).compactMap { shift -> (shift: Double, score: Double)? in
            guard abs(shift) <= maximumShift,
                  let match = try? alignment(previous, next, shift: shift, top: lower,
                    bottom: previous.height - upper, columns: columns) else { return nil }
            return match
        }
        guard let winner = verified.min(by: { $0.score < $1.score }) else { throw ImageError.noOverlap }
        return winner.shift
    }

    private static func movingColumns(_ a: ScrollFeatures, _ b: ScrollFeatures, lower: Int, upper: Int) -> [Int] {
        var changes = [Int](repeating: 0, count: ScrollFeatures.columns)
        var sampledRows = 0
        for y in stride(from: lower, to: upper, by: max(1, (upper - lower) / 180)) {
            sampledRows += 1
            for c in changes.indices where abs(Int(a.values[y * ScrollFeatures.columns + c]) - Int(b.values[y * ScrollFeatures.columns + c])) > 2 {
                changes[c] += 1
            }
        }
        return changes.indices.filter { changes[$0] >= max(4, sampledRows / 40) }
    }

    /// Verify ink/edges over the overlap, including rows the coarse search never
    /// sampled. Similar text lines or large white areas are not enough evidence.
    private static func verify(_ a: PixelRaster, _ b: PixelRaster, shift: Int, top: Int, bottom: Int, columns: [Int]) throws -> Double {
        try alignment(a, b, shift: shift, top: top, bottom: bottom, columns: columns).score
    }

    private static func alignment(_ a: PixelRaster, _ b: PixelRaster, shift: Int, top: Int, bottom: Int,
                                  columns: [Int]) throws -> (shift: Double, score: Double) {
        let start = max(top, top + shift), end = min(a.height - bottom, a.height - bottom + shift)
        let rowStep = max(1, (end - start) / 120), columnStep = max(1, a.width / 160)
        // Smooth scrolling may place glyphs between physical pixels. Fit one common
        // subpixel phase across the overlap, rather than requiring a stationary frame.
        let phases = Array(stride(from: -0.875, through: 0.875, by: 0.125))
        let tileCount = 24
        var totals = [Double](repeating: 0, count: phases.count * 2 * tileCount)
        var matches = [Int](repeating: 0, count: totals.count)
        var tileSamples = [Int](repeating: 0, count: tileCount)
        let moving = Set(columns)
        var samples: [(x: Int, y: Int, ny: Int)] = []
        for y in stride(from: start, to: end, by: rowStep) {
            let ny = y - shift
            for x in stride(from: max(1, a.width / 32), to: min(a.width - 1, a.width * 31 / 32), by: columnStep) {
                let column = max(0, min(ScrollFeatures.columns - 1,
                    (x - a.width / 16) * ScrollFeatures.columns / max(1, a.width * 7 / 8)))
                guard moving.contains(column) else { continue }
                let edgeA = abs(a.luminance(x, y) - a.luminance(x - 1, y)) + abs(a.luminance(x, y) - a.luminance(x, max(0, y - 1)))
                let edgeB = abs(b.luminance(x, ny) - b.luminance(x - 1, ny)) + abs(b.luminance(x, ny) - b.luminance(x, max(0, ny - 1)))
                guard max(edgeA, edgeB) > 8 else { continue }
                samples.append((x, y, ny))
            }
        }
        guard samples.count >= 48, let firstRow = samples.first?.y, let lastRow = samples.last?.y,
              lastRow - firstRow >= 24 else { throw ImageError.ambiguous }
        // Divide the content-bearing extent, not the surrounding blank margin.
        // A short paragraph at one edge of a large white region still provides
        // independent evidence from several lines.
        for (x, y, ny) in samples {
            let band = min(3, (y - firstRow) * 4 / max(1, lastRow - firstRow + 1))
            let tile = band * 6 + min(5, x * 6 / a.width)
            tileSamples[tile] += 1
            // Both consecutive browser frames can already be resampled at
            // different fractional phases. Put both on the same lightly
            // filtered basis before fitting a phase; interpolating just one
            // raw glyph cannot undo the other's previous resampling.
            var values = [Double](repeating: 0, count: 18)
            for (side, raster, row) in [(0, a, y), (1, b, ny)] {
                for neighbor in -1...1 {
                    let center = max(0, min(raster.height - 1, row + neighbor))
                    for c in 0..<3 {
                        let before = Double(raster.bytes[(max(0, center - 1) * raster.width + x) * 4 + c])
                        let at = Double(raster.bytes[(center * raster.width + x) * 4 + c])
                        let after = Double(raster.bytes[(min(raster.height - 1, center + 1) * raster.width + x) * 4 + c])
                        values[(side * 3 + neighbor + 1) * 3 + c] = (before + 2 * at + after) / 4
                    }
                }
            }
            for (index, phase) in phases.enumerated() {
                let fraction = abs(phase), step = phase < 0 ? -1 : 1
                var errors = [0.0, 0.0]
                for c in 0..<3 {
                    let av = values[3+c], bv = values[12+c]
                    errors[0] += abs(av * (1 - fraction) + values[(1 + step) * 3+c] * fraction - bv) / 3
                    errors[1] += abs(bv * (1 - fraction) + values[(4 + step) * 3+c] * fraction - av) / 3
                }
                for side in 0..<2 {
                    let k = (index * 2 + side) * tileCount + tile
                    totals[k] += errors[side]
                    if errors[side] < 24 { matches[k] += 1 }
                }
            }
        }
        // Require a shared displacement/phase over most textured content and
        // multiple vertical bands. Local animated cards may be outliers; they must
        // not make every live frame fail until the page happens to become still.
        var valid: [(shift: Double, score: Double)] = []
        let evidence = tileSamples.filter { $0 >= 4 }.reduce(0) { $0 + min(96, $1) }
        let informativeBands = Set(tileSamples.indices.filter { tileSamples[$0] >= 4 }.map { $0 / 6 })
        // Empty page regions cannot supply evidence. Require consensus across
        // the regions that actually contain ink, with at least two separated
        // bands so one animated card cannot masquerade as document movement.
        let requiredBands = max(2, min(3, informativeBands.count))
        for phase in 0..<(phases.count * 2) {
            var inliers = 0, weight = 0, total = 0.0
            var bands = Set<Int>()
            for tile in 0..<tileCount where tileSamples[tile] >= 4 {
                let k = phase * tileCount + tile, n = Double(tileSamples[tile])
                if totals[k] / n < 12 && Double(matches[k]) / n > 0.9 {
                    inliers += tileSamples[tile]; total += totals[k]; bands.insert(tile / 6)
                    weight += min(96, tileSamples[tile])
                }
            }
            if inliers >= (requiredBands == 2 ? 48 : 24) && weight * 10 >= evidence * 7 && bands.count >= requiredBands {
                let offset = phases[phase / 2] * (phase % 2 == 0 ? 1 : -1)
                valid.append((Double(shift) + offset, total / Double(inliers)))
            }
        }
        guard let winner = valid.min(by: { $0.score < $1.score }) else { throw ImageError.noOverlap }
        return winner
    }

    /// Only treat an edge as fixed when it contains actual stationary texture.
    /// A white margin alone must never remove document content.
    static func fixedEdges(_ previous: PixelRaster, _ next: PixelRaster,
                           previousFeatures a: ScrollFeatures, nextFeatures b: ScrollFeatures) -> (top: Int, bottom: Int) {
        let sampled = fixedEdges(a, b)
        // The motion descriptor deliberately ignores the outermost columns.
        // Window and pane corners often exist ONLY there, while the center of
        // the same rows is scrolling content. Inspect every column for stable
        // vertical edge profiles, rather than requiring a stationary full row.
        // This inset controls rendering, not the matching search region.
        let limit = previous.height / 5, width = previous.width
        var bottom = sampled.bottom
        for x in 0..<width {
            var contrast = 0, lastEdge = 0, stableRows = 0
            for depth in 0..<limit {
                let y = previous.height - 1 - depth, i = (y * width + x) * 4
                var change = 0
                for c in 0..<4 { change = max(change, abs(Int(previous.bytes[i+c]) - Int(next.bytes[i+c]))) }
                if change > 1 { break }
                stableRows += 1
                if depth > 0 {
                    var gradient = 0
                    for c in 0..<4 { gradient = max(gradient, abs(Int(previous.bytes[i+c]) - Int(previous.bytes[i + width * 4+c]))) }
                    if gradient > 2 { contrast += gradient; lastEdge = depth + 1 }
                    else if lastEdge > 0, depth - lastEdge >= max(8, previous.height / 100) { break }
                }
            }
            // Flat margins carry no edge evidence. A single low-level pixel
            // fluctuation is also insufficient to reserve an entire footer.
            if stableRows >= 3 && contrast >= 12 { bottom = max(bottom, lastEdge) }
        }
        return (sampled.top, bottom)
    }

    static func fixedEdges(_ a: ScrollFeatures, _ b: ScrollFeatures) -> (top: Int, bottom: Int) {
        let limit = a.height / 5
        func length(_ rows: [Int]) -> Int {
            var count = 0, textured = 0
            for y in rows {
                guard a.distance(row: y, to: b, row: y) < 0.5 else { break }
                count += 1
                if a.energy[y] > 100 { textured += 1 }
            }
            return textured >= 3 && count >= 6 ? count : 0
        }
        return (length(Array(0..<limit)), length(Array((a.height - limit..<a.height).reversed())))
    }
}
