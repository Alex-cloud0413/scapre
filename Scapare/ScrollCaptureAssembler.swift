import AppKit

nonisolated struct ScrollCaptureProgress: Sendable {
    let width: Int
    let height: Int
    let frameCount: Int
    let pageCount: Int
    let preview: CGImage?
    init(width: Int, height: Int, frameCount: Int, pageCount: Int = 1, preview: CGImage?) {
        self.width = width; self.height = height; self.frameCount = frameCount
        self.pageCount = pageCount; self.preview = preview
    }
}

/// One independently aligned document per explicit page boundary. Capture and
/// matching remain continuous within a page; unrelated screens never become a
/// guessed scroll movement or overwrite already captured pixels.
actor ScrollCaptureAssembler {
    private var stitcher: ScrollStitcher?
    private var completedStrips: [PixelRaster] = []
    private var completedHeight = 0
    private var completedFrames = 0
    private var completedPages = 0
    private var pendingPage = false
    private var lastPreview = ContinuousClock.now
    private let maxHeight: Int
    init(maxHeight: Int = 30_000) { self.maxHeight = maxHeight }

    // Deferring the boundary until a valid first frame avoids empty pages or
    // separators when a user switches again, cancels, or finishes immediately.
    func beginNewPage() { if stitcher != nil { pendingPage = true } }

    func accept(_ raster: PixelRaster) throws -> ScrollCaptureProgress {
        let initial = stitcher == nil || pendingPage
        let appended: Bool
        if initial {
            if let current = stitcher {
                guard raster.width == current.previous.width, raster.height == current.previous.height else { throw ImageError.incompatible }
            }
            let prior = pendingPage ? stitcher?.result : nil
            let separatorHeight = prior == nil ? 0 : max(8, Int(Double(raster.width) * 0.018))
            let sealedHeight = completedHeight + (prior?.height ?? 0) + separatorHeight
            let available = min(maxHeight, 60_000_000 / max(1, raster.width)) - sealedHeight
            guard raster.width > 0, raster.height > 0, raster.height <= available else { throw ImageError.tooLarge }
            let next = ScrollStitcher(first: raster, maxHeight: available)
            if let prior, let current = stitcher {
                completedStrips.append(contentsOf: prior.strips)
                completedStrips.append(PixelRaster(width: raster.width, height: separatorHeight,
                    bytes: [UInt8](repeating: 255, count: raster.width * separatorHeight * 4)))
                completedHeight = sealedHeight; completedFrames += current.frameCount; completedPages += 1
            }
            stitcher = next; pendingPage = false; appended = true
        } else { appended = try stitcher!.append(raster) }
        let now = ContinuousClock.now
        let shouldPreview = initial || (appended && lastPreview.duration(to: now) >= .milliseconds(150))
        if shouldPreview { lastPreview = now }
        let state = stitcher!
        return ScrollCaptureProgress(width: state.previous.width, height: completedHeight + state.height,
            frameCount: completedFrames + state.frameCount, pageCount: completedPages + 1,
            preview: shouldPreview ? result?.preview(maxSize: CGSize(width: 192, height: 416)) : nil)
    }
    private var result: ScrollImagePieces? {
        guard let stitcher else { return nil }
        return ScrollImagePieces(width: stitcher.previous.width, strips: completedStrips + stitcher.result.strips)
    }
    func image() -> CGImage? { result?.image() }
}
