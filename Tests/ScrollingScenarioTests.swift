import AppKit

/// Known source documents are the oracle: successful capture must reproduce
/// their rows, not just increase the reported height or return no error.
enum ScrollingScenarioTests {
    enum Failure: Error { case assertion(String) }

    @MainActor static func run() throws -> Int {
        var passed = 0
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw Failure.assertion(name) }
            passed += 1
            print("PASS: \(name)")
        }
        let start = ContinuousClock.now
        for scale in [1, 2] {
            let width = 640 * scale, viewport = 600 * scale
            for style in ["prose", "code", "table", "cards", "whitespace"] {
                let page = try document(width: width, height: viewport * 7, scale: scale, style: style)
                let cadences = [
                    ("accelerating", [3, 12, 29, 70, 145, 330, 640, 1050, 1470, 1800, 2180]),
                    ("anchor-bridging", [170, 540, 710, 1080, 1250, 1620, 1790, 2160]),
                    ("reversing", [70, 210, 580, 930, 730, 510, 650, 950, 1300, 1700, 2020])
                ]
                for (name, steps) in cadences {
                    var capture = ScrollStitcher(first: page.rows(0..<viewport))
                    var furthest = 0
                    var lastOffset = 0, blankRecoveries = 0
                    for step in steps {
                        let offset = step * scale, frame = page.rows(offset..<(offset + viewport))
                        do { _ = try capture.append(frame) }
                        catch {
                            let overlap = max(lastOffset, offset)..<min(lastOffset + viewport, offset + viewport)
                            let inkRows = overlap.filter { y in
                                page.bytes[(y * width * 4)..<((y + 1) * width * 4)].contains(where: { $0 < 240 })
                            }
                            guard !overlap.isEmpty, inkRows.count < 14 * scale else {
                                throw Failure.assertion("\(style) \(scale)x \(name) stopped at \(offset): \(error)")
                            }
                            // Blank overlap (at most a clipped glyph fragment)
                            // does not identify a reliable displacement. Preserve
                            // the result and recover on a return to visible text.
                            guard capture.height == viewport + furthest else {
                                throw Failure.assertion("Blank-only overlap damaged completed content")
                            }
                            for bridge in stride(from: lastOffset + viewport / 6, to: offset, by: viewport / 6) {
                                _ = try capture.append(page.rows(bridge..<(bridge + viewport)))
                            }
                            _ = try capture.append(frame)
                            blankRecoveries += 1
                        }
                        lastOffset = offset
                        furthest = max(furthest, offset)
                        guard capture.height == viewport + furthest else {
                            throw Failure.assertion("\(style) \(scale)x \(name) wrong height at \(offset): \(capture.height)")
                        }
                        let height = capture.height
                        _ = try capture.append(frame)
                        guard capture.height == height else { throw Failure.assertion("Stationary frame appended") }
                    }
                    try check(try PixelRaster(capture.image()!).bytes == page.rows(0..<(furthest + viewport)).bytes,
                              "Scenario \(style) \(scale)x \(name): exact source rows; blank/glyph-fragment overlaps requiring return: \(blankRecoveries)")
                }
                if style != "whitespace" {
                    let from = page.rows(0..<viewport), to = page.rows((137 * scale)..<(137 * scale + viewport))
                    let shift = try ScrollMatcher.registeredDisplacement(from, to)
                    try check(shift == 137 * scale, "Vision proposal verified on original \(style) \(scale)x pixels")
                }
            }
        }

        let page = try document(width: 640, height: 6000, scale: 1, style: "prose")
        var capture = ScrollStitcher(first: page.rows(0..<600))
        _ = try capture.append(page.rows(170..<770))
        let preserved = try PixelRaster(capture.image()!).bytes
        // Blank intermediate rendering and an unseen jump must never become
        // the reference. Recovery must resume from the last proven position.
        let invalid = PixelRaster(width: 640, height: 600, bytes: [UInt8](repeating: 255, count: 640 * 600 * 4))
        for frame in [invalid, page.rows(3500..<4100)] {
            do { _ = try capture.append(frame); throw Failure.assertion("Invalid overlap accepted") }
            catch is ImageError {}
            try check(try PixelRaster(capture.image()!).bytes == preserved, "Invalid frame preserves every previously captured pixel")
        }
        for offset in [260, 620, 980, 1200] { _ = try capture.append(page.rows(offset..<(offset + 600))) }
        try check(try PixelRaster(capture.image()!).bytes == page.rows(0..<1800).bytes,
                  "A failed frame and a missing-overlap jump can recover without adopting unverified content")

        // Cross many keyframes, not just a few fractional movements near zero.
        var smooth = ScrollStitcher(first: page.rows(0..<600))
        var worstError = 0
        for index in 1...160 {
            let offset = Double(index) * 17.3
            do { _ = try smooth.append(fractional(page, offset: offset, height: 600)) }
            catch { throw Failure.assertion("Long fractional run stopped at \(offset): \(error)") }
            worstError = max(worstError, abs(smooth.height - 600 - Int(offset.rounded())))
        }
        try check(worstError <= 2, "Long fractional scrolling across keyframes has at most two pixels of length drift (\(worstError))")
        print("BENCHMARK: scenario matrix completed in \(start.duration(to: .now))")
        return passed
    }

    @MainActor private static func document(width: Int, height: Int, scale: Int, style: String) throws -> PixelRaster {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let dark = style == "code"
        (dark ? NSColor(calibratedWhite: 0.10, alpha: 1) : NSColor.white).setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: width, height: height)).fill()
        let phrases = ["连续截图保留每一行内容", "Different lines need unique evidence", "Recover without duplicating rows", "键盘和触控板自然滚动", "Verify the source pixels before appending"]
        let spacing = 29 * scale
        for row in 0..<(height / spacing) {
            let y = row * spacing
            if style == "whitespace", (y / scale) % 850 > 620 { continue }
            let text: String
            if style == "code" { text = "let item_\(row) = values[\(row * 37 + 17)] // \(phrases[row % phrases.count])" }
            else if style == "table" { text = String(format: "%04d    %08d    %05d", row, row * 719 + 4321, row * 13) }
            else { text = "\(row) · \(phrases[row % phrases.count]) / \(row * 193 + 17)" }
            (text as NSString).draw(at: CGPoint(x: 24 * scale, y: height - y - 24 * scale),
                withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: CGFloat(14 * scale), weight: .regular),
                                 .foregroundColor: dark ? NSColor(calibratedRed: 0.62, green: 0.82, blue: 0.72, alpha: 1) : NSColor.black])
            if style == "cards", row % 9 == 4 {
                for tile in 0..<6 {
                    NSColor(calibratedRed: CGFloat((row * 17 + tile * 29) % 210) / 255,
                            green: CGFloat((row * 47 + tile * 71) % 190) / 255,
                            blue: CGFloat((row * 83 + tile * 23) % 230) / 255, alpha: 1).setFill()
                    NSBezierPath(roundedRect: CGRect(x: (24 + tile * 82) * scale, y: height - y - 88 * scale,
                                                    width: 74 * scale, height: (30 + tile * 7) * scale),
                                 xRadius: CGFloat(8 * scale), yRadius: CGFloat(8 * scale)).fill()
                }
            }
        }
        return try PixelRaster(bitmap.cgImage!)
    }

    private static func fractional(_ page: PixelRaster, offset: Double, height: Int) -> PixelRaster {
        let y = Int(offset), fraction = offset - Double(y)
        var result = page.rows(y..<(y + height))
        for i in result.bytes.indices {
            let following = page.bytes[(y + 1) * page.width * 4 + i]
            result.bytes[i] = UInt8((Double(result.bytes[i]) * (1 - fraction) + Double(following) * fraction).rounded())
        }
        return result
    }
}
