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
        var changes = [Int](repeating: 0, count: ScrollFeatures.columns)
        var sampledRows = 0
        for y in stride(from: lower, to: upper, by: max(1, (upper - lower) / 180)) {
            sampledRows += 1
            for c in changes.indices where abs(Int(a.values[y * ScrollFeatures.columns + c]) - Int(b.values[y * ScrollFeatures.columns + c])) > 2 {
                changes[c] += 1
            }
        }
        let columns = changes.indices.filter { changes[$0] >= max(4, sampledRows / 40) }
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

    /// Verify ink/edges over the overlap, including rows the coarse search never
    /// sampled. Similar text lines or large white areas are not enough evidence.
    private static func verify(_ a: PixelRaster, _ b: PixelRaster, shift: Int, top: Int, bottom: Int, columns: [Int]) throws -> Double {
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
        var count = 0
        for y in stride(from: start, to: end, by: rowStep) {
            let ny = y - shift
            for x in stride(from: max(1, a.width / 32), to: min(a.width - 1, a.width * 31 / 32), by: columnStep) {
                let column = max(0, min(ScrollFeatures.columns - 1,
                    (x - a.width / 16) * ScrollFeatures.columns / max(1, a.width * 7 / 8)))
                guard moving.contains(column) else { continue }
                let edgeA = abs(a.luminance(x, y) - a.luminance(x - 1, y)) + abs(a.luminance(x, y) - a.luminance(x, max(0, y - 1)))
                let edgeB = abs(b.luminance(x, ny) - b.luminance(x - 1, ny)) + abs(b.luminance(x, ny) - b.luminance(x, max(0, ny - 1)))
                guard max(edgeA, edgeB) > 8 else { continue }
                count += 1
                let band = min(3, (y - start) * 4 / max(1, end - start))
                let tile = band * 6 + min(5, x * 6 / a.width)
                tileSamples[tile] += 1
                let i = (y * a.width + x) * 4, j = (ny * b.width + x) * 4
                for (index, phase) in phases.enumerated() {
                    let fraction = abs(phase), step = phase < 0 ? -1 : 1
                    let ai = (max(0, min(a.height - 1, y + step)) * a.width + x) * 4
                    let bi = (max(0, min(b.height - 1, ny + step)) * b.width + x) * 4
                    var errors = [0.0, 0.0]
                    for c in 0..<3 {
                        let av = Double(a.bytes[i+c]), bv = Double(b.bytes[j+c])
                        errors[0] += abs(av * (1 - fraction) + Double(a.bytes[ai+c]) * fraction - bv) / 3
                        errors[1] += abs(bv * (1 - fraction) + Double(b.bytes[bi+c]) * fraction - av) / 3
                    }
                    for side in 0..<2 {
                        let k = (index * 2 + side) * tileCount + tile
                        totals[k] += errors[side]
                        if errors[side] < 24 { matches[k] += 1 }
                    }
                }
            }
        }
        guard count >= 24 else { throw ImageError.ambiguous }
        // Require a shared displacement/phase over most textured content and
        // three vertical bands. Local animated cards may be outliers; they must
        // not make every live frame fail until the page happens to become still.
        var valid: [Double] = []
        let evidence = tileSamples.filter { $0 >= 4 }.reduce(0) { $0 + min(96, $1) }
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
            if inliers >= 24 && weight * 10 >= evidence * 7 && bands.count >= 3 {
                valid.append(total / Double(inliers))
            }
        }
        guard let score = valid.min() else { throw ImageError.noOverlap }
        return score
    }

    /// Only treat an edge as fixed when it contains actual stationary texture.
    /// A white margin alone must never remove document content.
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
