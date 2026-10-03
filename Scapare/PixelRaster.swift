import AppKit
import CoreImage

/// Canonical top-to-bottom RGBA pixels; no assumptions about ScreenCaptureKit's native format.
nonisolated struct PixelRaster: Sendable {
    let width: Int
    let height: Int
    var bytes: [UInt8]
    init(width: Int, height: Int, bytes: [UInt8]) {
        self.width = width; self.height = height; self.bytes = bytes
    }
    init(_ image: CGImage) throws {
        guard image.width > 0, image.height > 0, image.width * image.height <= 100_000_000 else { throw ImageError.tooLarge }
        width = image.width; height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let ok = data.withUnsafeMutableBytes { ptr -> Bool in
            guard let ctx = CGContext(data: ptr.baseAddress, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard ok else { throw ImageError.decode }
        bytes = data
    }
    func image() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
    func luminance(_ x: Int, _ y: Int) -> Int {
        let offset = (y * width + x) * 4
        return (Int(bytes[offset]) * 77 + Int(bytes[offset + 1]) * 150 + Int(bytes[offset + 2]) * 29) >> 8
    }
    func color(x: Int, y: Int) -> (UInt8, UInt8, UInt8)? {
        guard (0..<width).contains(x), (0..<height).contains(y) else { return nil }
        let i = (y * width + x) * 4
        return (bytes[i], bytes[i+1], bytes[i+2])
    }
    func rows(_ range: Range<Int>) -> PixelRaster {
        PixelRaster(width: width, height: range.count, bytes: Array(bytes[(range.lowerBound * width * 4)..<(range.upperBound * width * 4)]))
    }
}

nonisolated enum ImageError: LocalizedError {
    case decode, tooLarge, incompatible, noOverlap, ambiguous
    var errorDescription: String? {
        switch self {
        case .decode: return "无法读取这张图片。"
        case .tooLarge: return "图片已达到长度或内存上限，请完成当前截图后分段截取。"
        case .incompatible: return "截图区域尺寸已改变，请重新开始。"
        case .noOverlap: return "没有找到可靠重叠。请向回滚动一些，让相邻画面至少保留三分之一相同内容。"
        case .ambiguous: return "画面重复或变化较多，暂未拼接。请缓慢向下滚动，避开固定页眉和动画。"
        }
    }
}

nonisolated enum ScrollMatch: Equatable { case unchanged, advance(Int) }

nonisolated enum ScrollMatcher {
    /// Compare texture across the width and several overlap rows. Never append on an ambiguous match.
    static func match(_ previous: PixelRaster, _ next: PixelRaster) throws -> ScrollMatch {
        guard previous.width == next.width, previous.height == next.height else { throw ImageError.incompatible }
        let h = previous.height, w = previous.width
        guard h >= 64, w >= 32 else { throw ImageError.incompatible }
        let xs = (0..<32).map { max(0, min(w - 1, w / 20 + $0 * (w * 9 / 10) / 32)) }
        func score(_ shift: Int) -> Double {
            let overlap = h - shift
            let rows = min(48, overlap)
            var total = 0, count = 0
            for row in 0..<rows {
                let y = row * (overlap - 1) / max(1, rows - 1)
                for x in xs {
                    total += abs(previous.luminance(x, y + shift) - next.luminance(x, y))
                    count += 1
                }
            }
            return Double(total) / Double(max(count, 1))
        }
        if score(0) < 0.7 { return .unchanged }
        let minOverlap = max(40, h / 3)
        let maxShift = h - minOverlap
        // Inspect every pixel offset. Skipping rows misses valid odd offsets on Retina
        // displays and produces misleading "no overlap" failures on fine textures.
        var candidates: [(Int, Double)] = []
        for shift in 1...maxShift { candidates.append((shift, score(shift))) }
        candidates.sort { $0.1 < $1.1 }
        let best = candidates[0]
        guard best.1 < 8 else { throw ImageError.noOverlap }
        let separated = candidates.first { abs($0.0 - best.0) > 5 }
        if let other = separated, other.1 < best.1 + max(1.2, best.1 * 0.3) { throw ImageError.ambiguous }
        var texture = 0
        for y in stride(from: 2, to: h - best.0, by: max(1, h / 80)) {
            for x in xs { texture += abs(next.luminance(x, y) - next.luminance(x, y - 2)) }
        }
        guard texture > 400 else { throw ImageError.ambiguous }
        return .advance(best.0)
    }
}

nonisolated struct ScrollStitcher: Sendable {
    private(set) var strips: [PixelRaster]
    private(set) var previous: PixelRaster
    private(set) var height: Int
    private(set) var frameCount = 1
    let maxHeight: Int
    init(first: PixelRaster, maxHeight: Int = 30_000) {
        strips = [first]; previous = first; height = first.height; self.maxHeight = maxHeight
    }
    mutating func append(_ next: PixelRaster) throws -> Bool {
        switch try ScrollMatcher.match(previous, next) {
        case .unchanged: return false
        case .advance(let rows):
            guard height + rows <= maxHeight, (height + rows) * next.width <= 60_000_000 else { throw ImageError.tooLarge }
            strips.append(next.rows((next.height - rows)..<next.height))
            previous = next; height += rows; frameCount += 1
            return true
        }
    }
    func image() -> CGImage? {
        PixelRaster(width: previous.width, height: height, bytes: strips.flatMap(\.bytes)).image()
    }
}

nonisolated enum PixelFilters {
    static func mosaic(_ input: PixelRaster, block: Int) -> PixelRaster {
        var result = input
        let size = max(4, min(100, block))
        for y in stride(from: 0, to: input.height, by: size) {
            for x in stride(from: 0, to: input.width, by: size) {
                let bottom = min(input.height, y + size), right = min(input.width, x + size)
                var sums = [Int](repeating: 0, count: 4)
                for row in y..<bottom { for col in x..<right { let i = (row * input.width + col) * 4; for c in 0..<4 { sums[c] += Int(input.bytes[i+c]) } } }
                let count = (bottom - y) * (right - x)
                let colors = sums.map { UInt8($0 / count) }
                for row in y..<bottom { for col in x..<right { let i = (row * input.width + col) * 4; for c in 0..<4 { result.bytes[i+c] = colors[c] } } }
            }
        }
        return result
    }
    /// Three separable box passes approximate a Gaussian without a GPU dependency.
    static func blur(_ input: PixelRaster, radius: Int) -> PixelRaster {
        let radius = max(2, min(40, radius))
        var result = input
        for _ in 0..<3 {
            result = box(result, radius: radius, horizontal: true)
            result = box(result, radius: radius, horizontal: false)
        }
        return result
    }
    private static func box(_ input: PixelRaster, radius: Int, horizontal: Bool) -> PixelRaster {
        var output = input
        let lines = horizontal ? input.height : input.width, length = horizontal ? input.width : input.height
        let diameter = radius * 2 + 1
        func offset(_ line: Int, _ position: Int) -> Int {
            let p = max(0, min(length - 1, position))
            return horizontal ? (line * input.width + p) * 4 : (p * input.width + line) * 4
        }
        for line in 0..<lines {
            var sums = [Int](repeating: 0, count: 4)
            for p in -radius...radius { let i = offset(line, p); for c in 0..<4 { sums[c] += Int(input.bytes[i+c]) } }
            for p in 0..<length {
                let i = offset(line, p)
                for c in 0..<4 { output.bytes[i+c] = UInt8(sums[c] / diameter) }
                let remove = offset(line, p - radius), add = offset(line, p + radius + 1)
                for c in 0..<4 { sums[c] += Int(input.bytes[add+c]) - Int(input.bytes[remove+c]) }
            }
        }
        return output
    }
}
