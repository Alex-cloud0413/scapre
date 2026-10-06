import AppKit

/// Exercise non-ideal panes, not only two perfectly identical first frames.
@MainActor
enum AdaptiveSidebarTests {
    enum Failure: Error { case assertion(String) }
    static func run() async throws -> Int {
        var passed = 0
        func check(_ condition: Bool, _ message: String) throws {
            guard condition else { throw Failure.assertion(message) }
            passed += 1; print("PASS: \(message)")
        }
        for scale in [1, 2] {
            for side in ["left", "right"] {
                let fixture = try FixedSidebarCompositionTests.Fixture(scale: scale, sides: side)
                let pane = fixture.ranges[0]
                func hovered(_ offset: Int) -> PixelRaster {
                    var frame = fixture.frame(offset * scale)
                    // One hover row changes every column of the pane; the rest
                    // of the navigation stays fixed during continuous motion.
                    for y in (72 * scale)..<(102 * scale) { for x in pane {
                        let i = (y * fixture.width + x) * 4
                        for c in 0..<3 { frame.bytes[i+c] = frame.bytes[i+c] > 220 ? 215 : frame.bytes[i+c] }
                    } }
                    return frame
                }
                var capture = ScrollStitcher(first: fixture.frame(0))
                for offset in [24, 70, 150, 280, 450, 700, 1000, 750, 400, 0] {
                    _ = try capture.append(hovered(offset))
                }
                let result = try PixelRaster(capture.image()!)
                if result.bytes != fixture.expected(minimum: 0, maximum: 1000 * scale).bytes {
                    let expected = fixture.expected(minimum: 0, maximum: 1000 * scale)
                    let index = zip(result.bytes, expected.bytes).enumerated().first(where: { $0.element.0 != $0.element.1 })!.offset
                    throw Failure.assertion("hover \(side) \(scale)x mask=\(capture.result.sidebars.map { $0.sidebar.columns }) first difference=\(index / 4 % fixture.width),\(index / 4 / fixture.width) \(result.bytes[index])/\(expected.bytes[index]) heights=\(result.height)/\(expected.height)")
                }
                try check(result.bytes == fixture.expected(minimum: 0, maximum: 1000 * scale).bytes,
                    "\(side) sidebar survives a changing hover row during forward/reverse scrolling (\(scale)x)")

                var loading = fixture.frame(0)
                // A layout settles after the first capture. Later validated
                // pairs must be allowed to classify the now-stationary pane.
                for y in 0..<fixture.viewport {
                    let target = ((y * fixture.width + pane.lowerBound) * 4)..<((y * fixture.width + pane.upperBound) * 4)
                    let sourceY = min(fixture.viewport - 1, y + 7 * scale)
                    let source = ((sourceY * fixture.width + pane.lowerBound) * 4)..<((sourceY * fixture.width + pane.upperBound) * 4)
                    loading.bytes.replaceSubrange(target, with: fixture.sidebar.bytes[source])
                }
                var delayed = ScrollStitcher(first: loading)
                for offset in [20, 80, 200, 400, 700, 1000, 700, 300, 0] {
                    _ = try delayed.append(fixture.frame(offset * scale))
                }
                let expected = fixture.expected(minimum: 0, maximum: 1000 * scale)
                try check(try PixelRaster(delayed.image()!).bytes == expected.bytes,
                    "Late sidebar detection repairs all retained strips after an unreliable initial pair (\(side), \(scale)x)")
            }
        }

        let fixture = try FixedSidebarCompositionTests.Fixture(scale: 1, sides: "left")
        // A short navigation menu occupies only one vertical band, unlike the
        // full-height menu used by the original sidebar fixtures.
        func sparse(_ offset: Int) -> PixelRaster {
            var frame = fixture.frame(offset)
            for y in 0..<600 where !(280..<350).contains(y) {
                let range = (y * 640 * 4)..<((y * 640 + 144) * 4)
                let blank = (599 * 640 * 4)..<((599 * 640 + 144) * 4)
                frame.bytes.replaceSubrange(range, with: fixture.sidebar.bytes[blank])
            }
            return frame
        }
        let sparseFirst = sparse(0)
        var short = ScrollStitcher(first: sparseFirst)
        for offset in [25, 70, 160, 330, 550, 900, 600, 250, 0] { _ = try short.append(sparse(offset)) }
        var expected = fixture.expected(minimum: 0, maximum: 900)
        for y in 0..<600 {
            let range = (y * 640 * 4)..<((y * 640 + 144) * 4)
            expected.bytes.replaceSubrange(range, with: sparseFirst.bytes[range])
        }
        try check(try PixelRaster(short.image()!).bytes == expected.bytes,
            "A short fixed menu is preserved once without requiring texture in three vertical bands")

        // Third-page regression: each page learns independently, and a hover
        // on page three cannot permanently disable or repaint page two's pane.
        let plain = try ScrollingScenarioTests.document(width: 640, height: 3000, scale: 1, style: "prose")
        let right = try FixedSidebarCompositionTests.Fixture(scale: 1, sides: "right")
        let assembler = ScrollCaptureAssembler()
        for offset in [0, 80, 200, 450, 700] { _ = try await assembler.accept(plain.rows(offset..<(offset + 600))) }
        await assembler.beginNewPage()
        for offset in [500, 300, 100, 0, 250, 600, 900] { _ = try await assembler.accept(right.frame(offset)) }
        await assembler.beginNewPage()
        for offset in [0, 25, 70, 160, 330, 550, 900, 600, 250, 0] { _ = try await assembler.accept(sparse(offset)) }
        let separator = [UInt8](repeating: 255, count: 640 * 11 * 4)
        let pages = plain.rows(0..<1300).bytes + separator + right.expected(minimum: 0, maximum: 900).bytes + separator + expected.bytes
        try check(try PixelRaster((await assembler.image())!).bytes == pages,
            "Three-page append with bidirectional scrolling deduplicates the third page's short sidebar and preserves preceding pages")

        // Some body columns repeat at exactly one scroll step. They must not
        // determine a viewport footer and cut off the sidebar's lower labels.
        var periodic = PixelRaster(width: 640, height: 2200, bytes: [UInt8](repeating: 255, count: 640 * 2200 * 4))
        for y in 0..<periodic.height { for x in 180..<600 {
            let i = (y * 640 + x) * 4, value = UInt8((y * 37 + x * 19 + y * x / 11) % 200)
            for c in 0..<3 { periodic.bytes[i+c] = value }
        } }
        func periodicFrame(_ offset: Int) -> PixelRaster {
            var frame = periodic.rows(offset..<(offset + 600))
            for y in 0..<600 {
                let range = (y * 640 * 4)..<((y * 640 + 144) * 4)
                frame.bytes.replaceSubrange(range, with: fixture.sidebar.bytes[range])
            }
            return frame
        }
        var repeated = ScrollStitcher(first: periodicFrame(900)), minimum = 900, maximum = 900
        for offset in [650, 400, 150, 0, 250, 500, 800, 1100, 700, 300, 0] {
            _ = try repeated.append(periodicFrame(offset)); minimum = min(minimum, offset); maximum = max(maximum, offset)
            var oracle = periodic.rows(minimum..<(maximum + 600))
            for y in 0..<oracle.height {
                let range = (y * 640 * 4)..<((y * 640 + 144) * 4)
                let row = min(y, 599), source = (row * 640 * 4)..<((row * 640 + 144) * 4)
                oracle.bytes.replaceSubrange(range, with: fixture.sidebar.bytes[source])
            }
            guard try PixelRaster(repeated.image()!).bytes == oracle.bytes else {
                throw Failure.assertion("Periodic body column became a fixed footer at \(offset)")
            }
        }
        try check(true, "Periodic body columns cannot cut off a fixed sidebar as a false footer during bidirectional scrolling")
        let retained = try PixelRaster(repeated.image()!).bytes
        do {
            _ = try repeated.append(PixelRaster(width: 640, height: 600, bytes: [UInt8](repeating: 255, count: 640 * 600 * 4)))
            throw Failure.assertion("Unverified blank frame accepted by sidebar tracker")
        } catch is ImageError {}
        try check(try PixelRaster(repeated.image()!).bytes == retained,
            "An unverified frame cannot change learned sidebar geometry or any retained output pixel")

        for scale in [1, 2] {
            let width = 640 * scale, viewport = 600 * scale, sideWidth = 144 * scale
            let body = try ScrollingScenarioTests.document(width: width, height: 2800 * scale, scale: scale, style: "prose")
            let navigation = try ScrollingScenarioTests.document(width: sideWidth, height: 2800 * scale, scale: scale, style: "prose")
            for stop in [240, 350] {
                func frame(_ offset: Int) -> PixelRaster {
                    var frame = body.rows((offset*scale)..<((offset+600)*scale))
                    let pane = navigation.rows((min(offset,stop)*scale)..<((min(offset,stop)+600)*scale))
                    for y in 0..<viewport {
                        let target = (y*width*4)..<((y*width+sideWidth)*4)
                        frame.bytes.replaceSubrange(target, with: pane.bytes[(y*sideWidth*4)..<((y+1)*sideWidth*4)])
                    }
                    return frame
                }
                for offsets in [[0, 24, 80, 170, 330, 500, 800, 1100, 800, 450, 150, 0],
                                [900, 700, 500, 300, 150, 0, 150, 400, 700, 1100, 700, 300, 0]] {
                    var capture = ScrollStitcher(first: frame(offsets[0]))
                    for offset in offsets.dropFirst() {
                        do { _ = try capture.append(frame(offset)) }
                        catch { throw Failure.assertion("Sticky sidebar input stopped: scale=\(scale) stop=\(stop) start=\(offsets[0]) offset=\(offset) error=\(error)") }
                    }
                    var oracle = body.rows(0..<(1700*scale))
                    for y in 0..<oracle.height {
                        let target = (y*width*4)..<((y*width+sideWidth)*4)
                        let source = (y*sideWidth*4)..<((y+1)*sideWidth*4)
                        let pixels = y < (stop+600)*scale ? Array(navigation.bytes[source]) : [UInt8](repeating: 255, count: sideWidth*4)
                        oracle.bytes.replaceSubrange(target, with: pixels)
                    }
                    guard try PixelRaster(capture.image()!).bytes == oracle.bytes else {
                        throw Failure.assertion("Sidebar that scrolls then sticks duplicates or loses navigation rows: \(scale)x stop=\(stop) start=\(offsets[0])")
                    }
                    try check(true, "Sidebar has independent scroll coordinates through sticking and reversal (\(scale)x, stop \(stop), start \(offsets[0]))")
                }
            }
        }
        return passed
    }
}
