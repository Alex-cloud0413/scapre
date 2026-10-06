import AppKit
import ImageIO

@MainActor
enum FixedSidebarCompositionTests {
    enum Failure: Error { case assertion(String) }
    static func run() async throws -> Int {
        var passed = 0
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw Failure.assertion(name) }
            passed += 1; print("PASS: \(name)")
        }
        for scale in [1, 2] {
            for sides in ["left", "right", "both"] {
                let fixture = try Fixture(scale: scale, sides: sides)
                for offsets in [[0, 3, 15, 80, 240, 500, 800, 1050], [900, 700, 500, 300, 100, 0, 200, 450, 750, 1100, 800, 500, 200, 0]] {
                    let first = offsets[0] * scale
                    var capture = ScrollStitcher(first: fixture.frame(first))
                    var minimum = first, maximum = first
                    for offset in offsets.dropFirst().map({ $0 * scale }) {
                        _ = try capture.append(fixture.frame(offset))
                        minimum = min(minimum, offset); maximum = max(maximum, offset)
                        let actual = try PixelRaster(capture.image()!), expected = fixture.expected(minimum: minimum, maximum: maximum)
                        if actual.bytes != expected.bytes {
                            let index = zip(actual.bytes, expected.bytes).enumerated().first(where: { $0.element.0 != $0.element.1 })!.offset
                            throw Failure.assertion("sidebar=\(sides) scale=\(scale) offset=\(offset) ranges=\(capture.result.sidebars.map { $0.sidebar.columns }) first mismatch=\(index / 4 % fixture.width),\(index / 4 / fixture.width) heights=\(actual.height),\(expected.height)")
                        }
                        try check(actual.bytes == expected.bytes,
                            "\(sides) fixed sidebar appears once with exact full-width body pixels (\(scale)x, \(offset))")
                    }
                }
            }
        }
        let plain = try ScrollingScenarioTests.document(width: 640, height: 3600, scale: 1, style: "prose")
        let smoothFixture = try Fixture(scale: 1, sides: "left")
        var smooth = ScrollStitcher(first: smoothFixture.frame(0))
        for offset in [0.125, 0.25, 0.375, 0.75, 1.5, 3.5, 8, 19, 40, 80, 160, 320, 520, 750] {
            let lower = Int(offset), fraction = offset - Double(lower)
            var frame = smoothFixture.frame(lower)
            let following = smoothFixture.frame(lower + 1)
            for i in frame.bytes.indices {
                frame.bytes[i] = UInt8((Double(frame.bytes[i]) * (1 - fraction) + Double(following.bytes[i]) * fraction).rounded())
            }
            _ = try smooth.append(frame)
        }
        let smoothOutput = try PixelRaster(smooth.image()!)
        for y in 0..<smoothOutput.height {
            let actual = (y * 640 * 4)..<((y * 640 + 144) * 4)
            let row = min(y, 599), expected = (row * 640 * 4)..<((row * 640 + 144) * 4)
            guard Array(smoothOutput.bytes[actual]) == Array(smoothFixture.sidebar.bytes[expected]) else {
                throw Failure.assertion("Subpixel startup duplicated the fixed sidebar at row \(y)")
            }
        }
        try check(!smooth.result.sidebars.isEmpty && abs(smooth.height - 1350) <= 1,
            "Subpixel startup retains one fixed sidebar without requiring scrolling to stop")
        for scale in [1, 2] {
            let table = try ScrollingScenarioTests.document(width: 640 * scale, height: 3600 * scale, scale: scale, style: "table")
            var capture = ScrollStitcher(first: table.rows(0..<(600 * scale)))
            for offset in [29, 58, 116, 290, 580, 870].map({ $0 * scale }) {
                _ = try capture.append(table.rows(offset..<(offset + 600 * scale)))
                try check(try PixelRaster(capture.image()!).bytes == table.rows(0..<(offset + 600 * scale)).bytes,
                    "Repeated table labels remain document content at whole-row scroll offsets (\(scale)x, \(offset))")
            }
        }
        let left = try Fixture(scale: 1, sides: "left")
        let right = try Fixture(scale: 1, sides: "right")
        let assembler = ScrollCaptureAssembler()
        for offset in [700, 500, 300, 100, 0, 200, 500, 900] { _ = try await assembler.accept(plain.rows(offset..<(offset + 600))) }
        await assembler.beginNewPage()
        for offset in [800, 600, 400, 200, 0, 200, 500, 800, 1100, 700, 300, 0] { _ = try await assembler.accept(left.frame(offset)) }
        await assembler.beginNewPage()
        for offset in [0, 20, 80, 250, 500, 800] { _ = try await assembler.accept(right.frame(offset)) }
        let separator = [UInt8](repeating: 255, count: 640 * 11 * 4)
        let expected = plain.rows(0..<1500).bytes + separator + left.expected(minimum: 0, maximum: 1100).bytes + separator + right.expected(minimum: 0, maximum: 800).bytes
        try check(try PixelRaster((await assembler.image())!).bytes == expected,
            "Cross-page reversal retains each page's own sidebar once without repainting adjacent pages")
        if let path = ProcessInfo.processInfo.environment["SCAPARE_SIDEBAR_REPLAY_IMAGE"] {
            guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                  let viewport = image.cropping(to: CGRect(x: 0, y: 5505, width: 3349, height: 1400)) else {
                throw Failure.assertion("Cannot read the supplied sidebar replay viewport")
            }
            let real = try PixelRaster(viewport), header = real.rows(0..<150)
            let sidebarWidth = 780, bodyHeight = 1250
            var document = PixelRaster(width: real.width, height: 5000,
                bytes: [UInt8](repeating: 255, count: real.width * 5000 * 4))
            for y in 0..<document.height { for x in 900..<2800 where y % 43 < 26 {
                let i = (y * document.width + x) * 4, value = UInt8((y * 37 + x * 19 + y * x / 11) % 200)
                document.bytes[i] = value; document.bytes[i+1] = value; document.bytes[i+2] = value
            } }
            func frame(_ offset: Int) -> PixelRaster {
                var result = PixelRaster(width: real.width, height: 1400,
                    bytes: header.bytes + document.rows(offset..<(offset + bodyHeight)).bytes)
                for y in 150..<1400 {
                    let range = (y * real.width * 4)..<((y * real.width + sidebarWidth) * 4)
                    result.bytes.replaceSubrange(range, with: real.bytes[range])
                }
                return result
            }
            var capture = ScrollStitcher(first: frame(600)), minimum = 600, maximum = 600
            for offset in [420, 240, 80, 0, 30, 110, 250, 480, 700, 1000, 1300, 1100, 700, 300, 0] {
                _ = try capture.append(frame(offset)); minimum = min(minimum, offset); maximum = max(maximum, offset)
                var expected = PixelRaster(width: real.width, height: 1400 + maximum - minimum,
                    bytes: header.bytes + document.rows(minimum..<(maximum + bodyHeight)).bytes)
                for y in 150..<expected.height {
                    let range = (y * real.width * 4)..<((y * real.width + sidebarWidth) * 4)
                    let pixels = y < 1400 ? Array(real.bytes[range]) : [UInt8](repeating: 255, count: sidebarWidth * 4)
                    expected.bytes.replaceSubrange(range, with: pixels)
                }
                let actual = try PixelRaster(capture.image()!)
                if actual.bytes != expected.bytes {
                    let index = zip(actual.bytes, expected.bytes).enumerated().first(where: { $0.element.0 != $0.element.1 })!.offset
                    throw Failure.assertion("real sidebar offset=\(offset) overlays=\(capture.result.sidebars.map { ($0.sidebar.columns, $0.top, $0.height) }) mismatch=\(index / 4 % real.width),\(index / 4 / real.width) values=\(actual.bytes[index]),\(expected.bytes[index]) heights=\(actual.height),\(expected.height)")
                }
                try check(actual.bytes == expected.bytes,
                    "Supplied App Store Connect sidebar with controlled body preserves exact full-width pixels at \(offset)")
            }
            if let directory = ProcessInfo.processInfo.environment["SCAPARE_TEST_RENDER_DIR"], let image = capture.image(),
               let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: directory).appendingPathComponent("sidebar-replay-after.png") as CFURL, "public.png" as CFString, 1, nil) {
                CGImageDestinationAddImage(destination, image, nil)
                try check(CGImageDestinationFinalize(destination), "Save the production algorithm's real-sidebar replay output for inspection")
            }
        }
        return passed
    }

    struct Fixture {
        let scale: Int
        let width: Int
        let viewport: Int
        let document: PixelRaster
        let sidebar: PixelRaster
        let ranges: [Range<Int>]
        init(scale: Int, sides: String) throws {
            self.scale = scale; width = 640 * scale; viewport = 600 * scale
            ranges = (sides == "right" ? [] : [0..<(144 * scale)]) + (sides == "left" ? [] : [(512 * scale)..<width])
            document = try ScrollingScenarioTests.document(width: width, height: 4800 * scale, scale: scale, style: "prose")
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: viewport,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSColor.white.setFill(); NSBezierPath(rect: CGRect(x: 0, y: 0, width: width, height: viewport)).fill()
            for range in ranges {
                let dark = range.lowerBound > 0
                (dark ? NSColor(calibratedWhite: 0.12, alpha: 1) : NSColor(calibratedWhite: 0.95, alpha: 1)).setFill()
                NSBezierPath(rect: CGRect(x: range.lowerBound, y: 0, width: range.count, height: viewport)).fill()
                for row in 0..<10 {
                    ("\(row) · 页面设置" as NSString).draw(at: CGPoint(x: range.lowerBound + 12 * scale, y: viewport - (40 + row * 51) * scale),
                        withAttributes: [.font: NSFont.systemFont(ofSize: CGFloat(12 * scale)), .foregroundColor: dark ? NSColor.white : NSColor.black])
                }
            }
            NSGraphicsContext.restoreGraphicsState()
            sidebar = try PixelRaster(bitmap.cgImage!)
        }
        func frame(_ offset: Int) -> PixelRaster {
            var result = document.rows(offset..<(offset + viewport))
            for y in 0..<viewport { for range in ranges {
                let start = (y * width + range.lowerBound) * 4, end = (y * width + range.upperBound) * 4
                result.bytes.replaceSubrange(start..<end, with: sidebar.bytes[start..<end])
            } }
            return result
        }
        func expected(minimum: Int, maximum: Int) -> PixelRaster {
            var result = document.rows(minimum..<(maximum + viewport))
            for y in 0..<result.height { for range in ranges {
                let start = (y * width + range.lowerBound) * 4, end = (y * width + range.upperBound) * 4
                let source = ((min(y, viewport - 1) * width + range.lowerBound) * 4)..<((min(y, viewport - 1) * width + range.upperBound) * 4)
                result.bytes.replaceSubrange(start..<end, with: sidebar.bytes[source])
            } }
            return result
        }
    }
}
