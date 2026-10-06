import AppKit
import ImageIO

/// The attachment is a final composite, not a recording. Use its unrepeated
/// sidebar pixels with a known moving body; never claim to reconstruct input.
@MainActor
enum ThirdPageSidebarReplayTests {
    enum Failure: Error { case assertion(String) }
    static func run() throws -> Int {
        guard let path = ProcessInfo.processInfo.environment["SCAPARE_THIRD_PAGE_REPLAY_IMAGE"] else { return 0 }
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil), image.width == 3350, image.height == 11237,
              let viewport = image.cropping(to: CGRect(x: 0, y: 6190, width: 3350, height: 1900)) else {
            throw Failure.assertion("Latest third-page attachment has unexpected dimensions")
        }
        let real = try PixelRaster(viewport), headerHeight = 300, sidebarWidth = 800
        let header = real.rows(0..<headerHeight), bodyHeight = real.height - headerHeight
        var document = PixelRaster(width: real.width, height: 5000,
            bytes: [UInt8](repeating: 255, count: real.width * 5000 * 4))
        for y in 0..<document.height { for x in 900..<3000 {
            let i = (y * document.width + x) * 4, value = UInt8((y * 37 + x * 19 + y * x / 11) % 200)
            document.bytes[i] = value; document.bytes[i+1] = value; document.bytes[i+2] = value
        } }
        func frame(_ offset: Int, hovered: Bool) -> PixelRaster {
            var result = PixelRaster(width: real.width, height: real.height,
                bytes: header.bytes + document.rows(offset..<(offset + bodyHeight)).bytes)
            for y in headerHeight..<real.height {
                let range = (y * real.width * 4)..<((y * real.width + sidebarWidth) * 4)
                result.bytes.replaceSubrange(range, with: real.bytes[range])
            }
            if hovered {
                for y in 420..<450 { for x in 320..<740 {
                    let i = (y * real.width + x) * 4
                    for c in 0..<3 where result.bytes[i+c] > 225 { result.bytes[i+c] -= 20 }
                } }
            }
            return result
        }
        var capture = ScrollStitcher(first: frame(700, hovered: false)), minimum = 700, maximum = 700
        var passed = 0
        for (index, offset) in [450, 200, 0, 80, 260, 500, 800, 1100, 1600, 2100, 1700, 1000, 300, 0].enumerated() {
            _ = try capture.append(frame(offset, hovered: index % 2 == 0))
            minimum = min(minimum, offset); maximum = max(maximum, offset)
            var expected = PixelRaster(width: real.width, height: real.height + maximum - minimum,
                bytes: header.bytes + document.rows(minimum..<(maximum + bodyHeight)).bytes)
            for y in headerHeight..<expected.height {
                let range = (y * real.width * 4)..<((y * real.width + sidebarWidth) * 4)
                let pixels = y < real.height ? Array(real.bytes[range]) : [UInt8](repeating: 255, count: sidebarWidth * 4)
                expected.bytes.replaceSubrange(range, with: pixels)
            }
            let actual = try PixelRaster(capture.image()!)
            guard actual.bytes == expected.bytes else {
                let mismatch = zip(actual.bytes, expected.bytes).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? 0
                throw Failure.assertion("Third-page replay offset=\(offset) mask=\(capture.result.sidebars.map { ($0.sidebar.columns, $0.top, $0.sidebar.pixels.height) }) mismatch=\(mismatch/4%real.width),\(mismatch/4/real.width) heights=\(actual.height)/\(expected.height)")
            }
            passed += 1; print("PASS: Latest third-page sidebar with changing hover: exact full-width output at \(offset)")
        }
        if let directory = ProcessInfo.processInfo.environment["SCAPARE_TEST_RENDER_DIR"], let image = capture.image(),
           let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: directory).appendingPathComponent("third-page-sidebar-after.png") as CFURL,
                "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw Failure.assertion("Cannot save replay output") }
            passed += 1; print("PASS: Save latest third-page replay output for inspection")
        }
        // Preview must use the same geometry as export and remain bounded.
        guard let preview = capture.preview(maxSize: CGSize(width: 192, height: 416)), preview.width <= 192, preview.height <= 416 else {
            throw Failure.assertion("Invalid bounded sidebar preview")
        }
        passed += 1; print("PASS: Latest third-page replay has a bounded production preview")
        return passed
    }
}
