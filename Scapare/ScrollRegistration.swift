import CoreGraphics
import Vision

/// Independent proposals from the system image-registration engine. These are
/// never sufficient to append pixels: ScrollMatcher verifies the original image
/// content and rejects conflicting alignments before accepting a proposal.
nonisolated enum ScrollRegistration {
    static func proposals(_ previous: PixelRaster, _ next: PixelRaster,
                          top: Int, bottom: Int, columns: [Int], maximumShift: Int) -> [Int] {
        guard let first = columns.first, let last = columns.last,
              let a = previous.image(), let b = next.image() else { return [] }
        let columnWidth = Double(previous.width * 7 / 8) / Double(ScrollFeatures.columns)
        let left = max(0, Int(Double(previous.width / 16) + Double(first) * columnWidth - columnWidth))
        let right = min(previous.width, Int(Double(previous.width / 16) + Double(last + 1) * columnWidth))
        let body = CGRect(x: left, y: top, width: right - left, height: previous.height - top - bottom)
        guard body.width >= 32, body.height >= 64 else { return [] }
        var regions = [body]
        if body.width >= 256 {
            let width = floor(body.width * 0.65)
            regions += [CGRect(x: body.minX, y: body.minY, width: width, height: body.height),
                        CGRect(x: body.maxX - width, y: body.minY, width: width, height: body.height)]
        }
        var results: [Int] = []
        for region in regions {
            guard let source = a.cropping(to: region), let target = b.cropping(to: region) else { continue }
            let scale = min(1, 1280 / max(region.width, region.height))
            guard let reference = resized(source, scale: scale), let current = resized(target, scale: scale) else { continue }
            let request = VNTranslationalImageRegistrationRequest(targetedCGImage: reference)
            let handler = VNImageRequestHandler(cgImage: current, options: [:])
            guard (try? handler.perform([request])) != nil, let result = request.results?.first,
                  result.confidence >= 0.5 else { continue }
            let x = result.alignmentTransform.tx / scale, y = result.alignmentTransform.ty / scale
            guard x.isFinite, y.isFinite, abs(x) <= 3, abs(y) <= CGFloat(maximumShift) else { continue }
            let shift = Int(y.rounded())
            // Resizing and glyph resampling can move the proposal by a pixel or
            // two. Refine on the original pixels rather than using the float as-is.
            for value in (shift - 3)...(shift + 3) where abs(value) <= maximumShift {
                if !results.contains(value) { results.append(value) }
            }
        }
        return results
    }

    private static func resized(_ image: CGImage, scale: CGFloat) -> CGImage? {
        if scale == 1 { return image }
        let width = max(1, Int(CGFloat(image.width) * scale)), height = max(1, Int(CGFloat(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
