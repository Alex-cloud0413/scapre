import AppKit
import ScreenCaptureKit
import CoreMedia
import CoreVideo
import Accelerate

nonisolated extension PixelRaster {
    init(bgraBuffer buffer: CVPixelBuffer) throws {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { throw ImageError.decode }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        guard w > 0, h > 0, w * h <= 60_000_000 else { throw ImageError.tooLarge }
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { throw ImageError.decode }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw ImageError.decode }
        var source = vImage_Buffer(data: base, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: CVPixelBufferGetBytesPerRow(buffer))
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let error = bytes.withUnsafeMutableBytes { raw -> vImage_Error in
            var destination = vImage_Buffer(data: raw.baseAddress!, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w * 4)
            let map: [UInt8] = [2, 1, 0, 3]
            return vImagePermuteChannels_ARGB8888(&source, &destination, map, vImage_Flags(kvImageNoFlags))
        }
        guard error == kvImageNoError else { throw ImageError.decode }
        self.init(width: w, height: h, bytes: bytes)
    }
}

/// The callback runs on one serial queue and releases each ScreenCaptureKit
/// surface immediately. AsyncStream bounds retained frames when matching lags.
nonisolated final class ScrollFrameReceiver: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let frames: AsyncThrowingStream<PixelRaster, Error>
    private let continuation: AsyncThrowingStream<PixelRaster, Error>.Continuation
    override init() {
        (frames, continuation) = AsyncThrowingStream.makeStream(bufferingPolicy: .bufferingNewest(3))
        super.init()
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        receive(buffer)
    }
    func receive(_ buffer: CVPixelBuffer) {
        do { continuation.yield(try PixelRaster(bgraBuffer: buffer)) }
        catch { continuation.finish(throwing: error) }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { continuation.finish(throwing: error) }
    func finish() { continuation.finish() }
}

@MainActor
final class RegionCaptureSource: ScrollingCaptureSource {
    private let stream: SCStream
    private let receiver: ScrollFrameReceiver
    private var started = false
    private var stopped = false
    private let displayID: CGDirectDisplayID
    private let screenSize: CGSize
    private let scale: CGFloat

    init(screen: NSScreen, selection: CGRect) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let id = screen.displayID, let display = content.displays.first(where: { $0.displayID == id }) else { throw ScreenshotError.noDisplays }
        displayID = id; screenSize = screen.frame.size; scale = screen.backingScaleFactor
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let config = SCStreamConfiguration()
        let rect = PixelGeometry.cropRect(selection: selection, viewSize: screenSize,
                                          imageSize: CGSize(width: screenSize.width * scale, height: screenSize.height * scale))
        config.sourceRect = CGRect(x: rect.minX / scale, y: rect.minY / scale, width: rect.width / scale, height: rect.height / scale)
        config.width = Int(rect.width); config.height = Int(rect.height)
        config.showsCursor = false
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 3
        config.captureResolution = .best
        config.colorSpaceName = CGColorSpace.sRGB
        receiver = ScrollFrameReceiver()
        stream = SCStream(filter: filter, configuration: config, delegate: receiver)
        try stream.addStreamOutput(receiver, type: .screen,
                                   sampleHandlerQueue: DispatchQueue(label: "Scapare.ScrollingFrames", qos: .userInitiated))
    }
    func frames() async throws -> AsyncThrowingStream<PixelRaster, Error> {
        guard !stopped else { throw CancellationError() }
        if !started { try await stream.startCapture(); started = true }
        if stopped { try? await stream.stopCapture(); throw CancellationError() }
        return receiver.frames
    }
    func validateDisplay() throws {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }),
              screen.frame.size == screenSize, screen.backingScaleFactor == scale else { throw ImageError.incompatible }
    }
    func stop() async {
        guard !stopped else { return }
        stopped = true
        if started { try? await stream.stopCapture() }
        receiver.finish()
    }
}
