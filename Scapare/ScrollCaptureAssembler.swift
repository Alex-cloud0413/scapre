import AppKit

nonisolated struct ScrollCaptureProgress: Sendable {
    let width: Int
    let height: Int
    let frameCount: Int
    let preview: CGImage?
}

/// Owns the accumulated image off the main actor. Capture, matching and UI
/// repainting have separate rates; a preview never holds up incoming frames.
actor ScrollCaptureAssembler {
    private var stitcher: ScrollStitcher?
    private var lastPreview = ContinuousClock.now
    func accept(_ raster: PixelRaster) throws -> ScrollCaptureProgress {
        let initial = stitcher == nil
        let appended: Bool
        if initial { stitcher = ScrollStitcher(first: raster); appended = true }
        else { appended = try stitcher!.append(raster) }
        let now = ContinuousClock.now
        let shouldPreview = initial || (appended && lastPreview.duration(to: now) >= .milliseconds(150))
        if shouldPreview { lastPreview = now }
        let state = stitcher!
        return ScrollCaptureProgress(width: state.previous.width, height: state.height, frameCount: state.frameCount,
                                     preview: shouldPreview ? state.preview(maxSize: CGSize(width: 192, height: 416)) : nil)
    }
    func image() -> CGImage? { stitcher?.image() }
}
