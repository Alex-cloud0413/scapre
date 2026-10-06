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
        case .noOverlap: return "这一段没有可靠衔接，已保留此前内容。请向回滚动一些以恢复衔接。"
        case .ambiguous: return "画面重复或变化较多，暂未追加，以免重复拼接。请回滚一些，或避开动画区域。"
        }
    }
}

nonisolated struct ScrollStitcher: Sendable {
    private(set) var strips: [PixelRaster]
    private(set) var previous: PixelRaster
    private var features: ScrollFeatures
    private var position = 0.0
    private var earliestPosition = 0
    private var furthestPosition = 0
    private var leadingStrips: [PixelRaster] = []
    private var header: PixelRaster?
    private var sidebars: [ScrollFixedSidebar] = []
    private var sidebarTracker: ScrollSidebarTracker
    private var recent: (raster: PixelRaster, features: ScrollFeatures, position: Double)?
    private(set) var recoveredMatches = 0
    private var didSetFixedEdges = false
    private var fixedTop = 0
    private var fixedBottom = 0
    private var headerHeight = 0
    private var footerHeight = 0
    private var footer: PixelRaster?
    private(set) var height: Int
    private(set) var frameCount = 1
    let maxHeight: Int
    private let tracksSidebars: Bool
    init(first: PixelRaster, maxHeight: Int = 30_000, tracksSidebars: Bool = true) {
        strips = [first]; previous = first; features = ScrollFeatures(first)
        height = first.height; self.maxHeight = maxHeight
        sidebarTracker = ScrollSidebarTracker(first: first)
        self.tracksSidebars = tracksSidebars
    }
    mutating func append(_ next: PixelRaster) throws -> Bool {
        let nextFeatures = ScrollFeatures(next)
        guard next.width == previous.width, next.height == previous.height else { throw ImageError.incompatible }
        var top = fixedTop, bottom = fixedBottom, outputTop = headerHeight, outputBottom = footerHeight
        if !didSetFixedEdges, !ScrollMatcher.isUnchanged(previous, next) {
            let edges = ScrollMatcher.fixedEdges(features, nextFeatures)
            top = edges.top; bottom = edges.bottom
        }
        let nextPosition: Double
        var recovered = false
        let reference = recent ?? (raster: previous, features: features, position: position)
        do {
            let local = try ScrollMatcher.displacement(reference.raster, next,
                previousFeatures: reference.features, nextFeatures: nextFeatures, excludingTop: top, bottom: bottom)
            let proposal = reference.position + (try ScrollMatcher.refine(reference.raster, next, around: Double(local),
                previousFeatures: reference.features, nextFeatures: nextFeatures, excludingTop: top, bottom: bottom))
            if recent != nil, let anchored = try? ScrollMatcher.refine(previous, next, around: proposal - position,
                previousFeatures: features, nextFeatures: nextFeatures, excludingTop: top, bottom: bottom) {
                nextPosition = position + anchored
            } else {
                nextPosition = proposal
                recovered = recent != nil
            }
        } catch {
            guard recent != nil else { throw error }
            // A return toward older content can overlap the anchor better than
            // the latest frame. Neither path ever adopts an unverified frame.
            let local = try ScrollMatcher.displacement(previous, next, previousFeatures: features,
                nextFeatures: nextFeatures, excludingTop: top, bottom: bottom)
            nextPosition = position + (try ScrollMatcher.refine(previous, next, around: Double(local),
                previousFeatures: features, nextFeatures: nextFeatures, excludingTop: top, bottom: bottom))
            recovered = true
        }
        let shift = nextPosition - position
        guard shift != 0 else { return false }
        let roundedPosition = Int(nextPosition.rounded())
        if !didSetFixedEdges, roundedPosition == 0 {
            // Subpixel startup has not exposed a new physical row yet. Keep
            // tracking it without permanently classifying its panes as empty.
            recent = (next, nextFeatures, nextPosition)
            return false
        }
        var nextSidebarTracker = sidebarTracker
        if tracksSidebars {
            nextSidebarTracker.observe(next, position: nextPosition,
                top: didSetFixedEdges ? outputTop : top, bottom: didSetFixedEdges ? outputBottom : bottom)
        }
        if !didSetFixedEdges {
            let ranges = nextSidebarTracker.exclusions
            // Sidebar labels near a viewport edge are not a fixed page header
            // or footer. Keep partial window decorations outside those panes.
            let decorations = ScrollMatcher.fixedEdges(previous, next, previousFeatures: features,
                nextFeatures: nextFeatures, excludingColumns: ranges, displacement: Int(shift.rounded()))
            outputTop = decorations.top; outputBottom = decorations.bottom
        }
        let prependRows = max(0, earliestPosition - roundedPosition)
        let appendRows = max(0, roundedPosition - furthestPosition)
        let newRows = prependRows + appendRows
        let contentHeight = next.height - outputTop - outputBottom
        guard prependRows <= contentHeight, appendRows <= contentHeight else { throw ImageError.noOverlap }
        guard height + newRows <= maxHeight, (height + newRows) * next.width <= 60_000_000 else { throw ImageError.tooLarge }
        // Fixed chrome belongs once at the two document ends. When capture
        // expands upward, the header must stay above the newly discovered rows.
        if !didSetFixedEdges {
            let first = strips[0]
            strips = [first.rows(outputTop..<(first.height - outputBottom))]
            if outputTop > 0 { header = first.rows(0..<outputTop) }
            if outputBottom > 0 { footer = first.rows((first.height - outputBottom)..<first.height) }
        }
        didSetFixedEdges = true
        sidebars = tracksSidebars ? nextSidebarTracker.overlays(top: outputTop, bottom: outputBottom,
            maximumHeight: height + newRows - outputTop - outputBottom) : []
        let sidebarChanged = nextSidebarTracker.revision != sidebarTracker.revision
        sidebarTracker = nextSidebarTracker
        fixedTop = top; fixedBottom = bottom; headerHeight = outputTop; footerHeight = outputBottom
        if outputTop > 0, roundedPosition <= earliestPosition { header = next.rows(0..<outputTop) }
        if outputBottom > 0, roundedPosition >= furthestPosition {
            footer = next.rows((next.height - outputBottom)..<next.height)
        }
        // Match against a keyframe for many updates, instead of rounding and
        // accumulating a new displacement on every fractional scrolling frame.
        if recovered || abs(shift) >= Double(max(16, next.height / 3)) {
            previous = next; features = nextFeatures; position = nextPosition
        }
        recent = (next, nextFeatures, nextPosition)
        if recovered { recoveredMatches += 1 }
        guard newRows > 0 else { return sidebarChanged }
        if prependRows > 0 {
            leadingStrips.append(next.rows(outputTop..<(outputTop + prependRows)))
            earliestPosition = roundedPosition
        }
        if appendRows > 0 {
            strips.append(next.rows((next.height - outputBottom - appendRows)..<(next.height - outputBottom)))
            furthestPosition = roundedPosition
        }
        height += newRows; frameCount += 1
        return true
    }
    var result: ScrollImagePieces {
        ScrollImagePieces(width: previous.width,
            strips: (header.map { [$0] } ?? []) + Array(leadingStrips.reversed()) + strips + (footer.map { [$0] } ?? []),
            sidebars: sidebars.map { ScrollSidebarOverlay(sidebar: $0, top: headerHeight, height: height - headerHeight - footerHeight) })
    }
    var capturedPositions: (minimum: Int, maximum: Int) { (earliestPosition, furthestPosition) }
    func image() -> CGImage? { result.image() }
    func preview(maxSize: CGSize) -> CGImage? { result.preview(maxSize: maxSize) }
}

/// Retains original strips without flattening completed pages into a second full
/// image. Used by both one-page stitching and ordered cross-page composition.
nonisolated struct ScrollImagePieces: Sendable {
    let width: Int
    let strips: [PixelRaster]
    var sidebars: [ScrollSidebarOverlay] = []
    var height: Int { strips.reduce(0) { $0 + $1.height } }
    func image() -> CGImage? {
        guard height > 0 else { return nil }
        var bytes = strips.flatMap(\.bytes)
        for sidebar in sidebars { sidebar.apply(to: &bytes, width: width) }
        return PixelRaster(width: width, height: height, bytes: bytes).image()
    }
    func preview(maxSize: CGSize) -> CGImage? {
        let height = height
        guard height > 0 else { return nil }
        let scale = min(1, maxSize.width / CGFloat(width), maxSize.height / CGFloat(height))
        let w = max(1, Int(CGFloat(width) * scale)), h = max(1, Int(CGFloat(height) * scale))
        guard let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        var top = 0
        for strip in strips {
            guard let image = strip.image() else { return nil }
            let bottom = top + strip.height
            let y0 = CGFloat(height - bottom) * CGFloat(h) / CGFloat(height)
            let y1 = CGFloat(height - top) * CGFloat(h) / CGFloat(height)
            context.draw(image, in: CGRect(x: 0, y: y0, width: CGFloat(w), height: y1 - y0))
            top = bottom
        }
        for sidebar in sidebars { sidebar.draw(in: context, outputHeight: height, xScale: CGFloat(w) / CGFloat(width), yScale: CGFloat(h) / CGFloat(height)) }
        return context.makeImage()
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
