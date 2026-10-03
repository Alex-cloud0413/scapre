import AppKit

enum ScreenshotRenderer {
    static func render(image: CGImage, selection: CGRect, viewSize: CGSize,
                       annotations: [Annotation]) -> CGImage? {
        let rect = PixelGeometry.cropRect(selection: selection, viewSize: viewSize,
                                          imageSize: CGSize(width: image.width, height: image.height))
        guard !rect.isNull, rect.width >= 1, rect.height >= 1,
              let cropped = image.cropping(to: rect) else { return nil }
        guard !annotations.isEmpty else { return cropped }
        guard let context = CGContext(data: nil, width: cropped.width, height: cropped.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
        let sx = CGFloat(image.width) / viewSize.width
        let sy = CGFloat(image.height) / viewSize.height
        context.scaleBy(x: sx, y: sy)
        context.translateBy(x: -rect.minX / sx, y: -(viewSize.height - rect.maxY / sy))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        annotations.forEach { $0.draw() }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
