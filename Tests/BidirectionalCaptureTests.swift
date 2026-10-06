import AppKit

/// Source pixels and explicit page boundaries are the oracle. Increasing height
/// alone cannot prove that reversal, revisits or page transitions are correct.
@MainActor
enum BidirectionalCaptureTests {
    enum Failure: Error { case assertion(String), timeout }
    static func run() async throws -> Int {
        var passed = 0
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw Failure.assertion(name) }
            passed += 1; print("PASS: \(name)")
        }
        for scale in [1, 2] {
            let viewport = 600 * scale
            for style in ["prose", "code", "table", "cards", "whitespace"] {
                let page = try ScrollingScenarioTests.document(width: 640 * scale, height: 4800 * scale, scale: scale, style: style)
                let paths = [
                    ("bottom-to-top", [2100, 1800, 1500, 1200, 900, 600, 300, 0]),
                    ("both-extremes-and-revisits", [1050, 900, 700, 1050, 1350, 1650, 1900, 1600, 1300, 1000, 700, 450, 220, 0, 260, 540, 810, 1080, 1350, 1650, 1900, 1600, 1250, 950, 650, 350, 0])
                ]
                for (name, offsets) in paths {
                    let first = offsets[0] * scale
                    var stitcher = ScrollStitcher(first: page.rows(first..<(first + viewport)))
                    var minimum = first, maximum = first
                    for offset in offsets.dropFirst().map({ $0 * scale }) {
                        let frame = page.rows(offset..<(offset + viewport))
                        _ = try stitcher.append(frame)
                        minimum = min(minimum, offset); maximum = max(maximum, offset)
                        guard stitcher.height == maximum - minimum + viewport else {
                            throw Failure.assertion("\(style) \(scale)x \(name): duplicate or missing rows at \(offset)")
                        }
                        _ = try stitcher.append(frame)
                        guard stitcher.height == maximum - minimum + viewport else { throw Failure.assertion("A revisited viewport grew the image") }
                    }
                    try check(try PixelRaster(stitcher.image()!).bytes == page.rows(minimum..<(maximum + viewport)).bytes,
                        "\(style) \(scale)x \(name): exact source order with no duplicated rows")
                }
            }
        }

        let page = pattern(width: 160, height: 2400, seed: 14)
        let top = 24, bottom = 28, viewport = 400, bodyHeight = viewport - top - bottom
        let header = pattern(width: 160, height: top, seed: 31)
        let footer = pattern(width: 160, height: bottom, seed: 42)
        func fixedFrame(_ offset: Int) -> PixelRaster {
            PixelRaster(width: 160, height: viewport, bytes: header.bytes + page.rows(offset..<(offset + bodyHeight)).bytes + footer.bytes)
        }
        var fixed = ScrollStitcher(first: fixedFrame(800))
        for offset in [650, 500, 350, 200, 50, 0, 150, 300, 450, 600, 750, 900, 1050, 900, 750, 600, 450, 300, 150, 0] { _ = try fixed.append(fixedFrame(offset)) }
        let fixedExpected = header.bytes + page.rows(0..<(1050 + bodyHeight)).bytes + footer.bytes
        try check(try PixelRaster(fixed.image()!).bytes == fixedExpected,
            "Upward expansion keeps a fixed header above the content and a fixed footer below it exactly once")

        // Window corners and shadows at both viewport ends must not be repeated
        // while prepending, including decorations confined to a few edge columns.
        let document = try ScrollingScenarioTests.document(width: 640, height: 3600, scale: 1, style: "prose")
        func decorated(_ offset: Int) -> PixelRaster {
            var frame = document.rows(offset..<(offset + 600))
            for y in 0..<14 { for x in 0..<12 {
                let i = (y * 640 + x) * 4
                frame.bytes[i] = UInt8(100 + y); frame.bytes[i+1] = frame.bytes[i]; frame.bytes[i+2] = frame.bytes[i]
            } }
            for y in 580..<600 { for x in 0..<12 {
                let i = (y * 640 + x) * 4
                frame.bytes[i] = UInt8(100 + y - 580); frame.bytes[i+1] = frame.bytes[i]; frame.bytes[i+2] = frame.bytes[i]
            } }
            return frame
        }
        var corners = ScrollStitcher(first: decorated(900))
        for offset in [700, 500, 300, 100, 0, 200, 400, 600, 800, 1000, 1200] { _ = try corners.append(decorated(offset)) }
        let decoratedExpected = decorated(0).rows(0..<14).bytes + document.rows(14..<1780).bytes + decorated(1200).rows(580..<600).bytes
        try check(try PixelRaster(corners.image()!).bytes == decoratedExpected,
            "Up/down capture preserves partial-width top and bottom corner decorations only at their final edges")

        let smoothPage = try ScrollingScenarioTests.document(width: 640, height: 6000, scale: 1, style: "prose")
        var smooth = ScrollStitcher(first: interpolated(smoothPage, offset: 3000, height: 600))
        var worstDrift = 0, furthestUpward = 0.0
        for index in Array(1...160) + Array((0..<160).reversed()) {
            let distance = Double(index) * 17.3
            _ = try smooth.append(interpolated(smoothPage, offset: 3000 - distance, height: 600))
            furthestUpward = max(furthestUpward, distance)
            worstDrift = max(worstDrift, abs(smooth.height - 600 - Int(furthestUpward.rounded())))
        }
        try check(worstDrift <= 2 && abs(smooth.height - 3368) <= 2,
            "Fractional upward motion and a full return have at most two pixels of length drift")

        let assembler = ScrollCaptureAssembler()
        let firstPage = pattern(width: 96, height: 1600, seed: 71)
        let secondPage = pattern(width: 96, height: 1600, seed: 103)
        let staticPage = pattern(width: 96, height: 240, seed: 227)
        var progress = try await assembler.accept(firstPage.rows(800..<1040))
        for offset in [640, 480, 320, 480, 640, 800, 640, 480, 320] { progress = try await assembler.accept(firstPage.rows(offset..<(offset + 240))) }
        let firstResult = try PixelRaster((await assembler.image())!)
        try check(firstResult.bytes == firstPage.rows(320..<1040).bytes, "A page can begin at its bottom and grow upward")
        await assembler.beginNewPage(); await assembler.beginNewPage()
        try check(try PixelRaster((await assembler.image())!).bytes == firstResult.bytes,
            "Repeated or unfinished page transitions do not create empty pages or separators")
        do {
            _ = try await assembler.accept(pattern(width: 120, height: 240, seed: 0))
            throw Failure.assertion("A page of incompatible width was accepted")
        } catch ImageError.incompatible {}
        try check(try PixelRaster((await assembler.image())!).bytes == firstResult.bytes,
            "An invalid first frame on a new page preserves the complete previous page")
        for offset in [0, 80, 180, 100, 260, 360] { progress = try await assembler.accept(secondPage.rows(offset..<(offset + 240))) }
        await assembler.beginNewPage()
        progress = try await assembler.accept(staticPage)
        let separator = [UInt8](repeating: 255, count: 96 * 8 * 4)
        let expectedPages = firstPage.rows(320..<1040).bytes + separator + secondPage.rows(0..<600).bytes + separator + staticPage.bytes
        let assembledPages = try PixelRaster((await assembler.image())!)
        try check(progress.pageCount == 3 && progress.height == 1576 && assembledPages.bytes == expectedPages,
            "Reverse, mixed and static pages merge in explicit page order with exact pixels")
        let preview = try PixelRaster(progress.preview!)
        try check(preview.height <= 416 && preview.width <= 192, "Cross-page preview remains bounded")
        await assembler.beginNewPage()
        try check(try PixelRaster((await assembler.image())!).bytes == expectedPages, "Finishing before a new frame does not append an empty final page")

        let limited = ScrollCaptureAssembler(maxHeight: 650)
        _ = try await limited.accept(secondPage.rows(0..<240))
        _ = try await limited.accept(secondPage.rows(180..<420))
        await limited.beginNewPage()
        do { _ = try await limited.accept(staticPage); throw Failure.assertion("Cross-page height limit was bypassed") }
        catch ImageError.tooLarge {}
        try check(try PixelRaster((await limited.image())!).bytes == secondPage.rows(0..<420).bytes,
            "The total height limit applies across pages without losing already captured content")

        let screen = NSScreen.screens.first!
        let a = ManualSource(), b = ManualSource()
        var sources = [a, b], exported: CGImage?, closeCount = 0
        var updates: [ScrollCaptureProgress] = []
        let controller = ScrollingCaptureController(screen: screen, selection: CGRect(x: 0, y: 0, width: 96, height: 240),
            onClose: { closeCount += 1 }, makeSource: { sources.removeFirst() }, onCopy: { exported = $0; return true })
        controller.onProgress = { updates.append($0) }; controller.run()
        try await wait { a.continuation != nil }
        a.send(secondPage.rows(0..<240)); a.send(secondPage.rows(80..<320))
        try await wait { updates.last?.height == 320 }
        controller.pageButton.performClick(nil)
        try await wait { a.stopped && controller.pageButton.isEnabled }
        let pausedUpdates = updates.count
        a.send(staticPage)
        try await Task.sleep(for: .milliseconds(50))
        try check(controller.pageButton.title == "继续追加" && updates.count == pausedUpdates,
            "Switch Page stops the old stream; navigation frames never enter a page")
        controller.pageButton.performClick(nil)
        try await wait { b.continuation != nil }
        b.send(firstPage.rows(300..<540)); b.send(firstPage.rows(150..<390)); b.send(firstPage.rows(0..<240))
        try await wait { updates.last?.pageCount == 2 && updates.last?.height == 868 }
        controller.finishAndCopy()
        try await wait { exported != nil }
        let controllerExpected = secondPage.rows(0..<320).bytes + separator + firstPage.rows(0..<540).bytes
        try check(try PixelRaster(exported!).bytes == controllerExpected && closeCount == 1 && b.stopped,
            "The real page buttons resume a fresh source and Complete and Copy returns both ordered pages")
        controller.close()
        try check(closeCount == 1, "A cross-page session closes once")

        // Finishing while a fresh source is still being prepared must preserve
        // the old page and terminate; it must not wait forever for new frames.
        let opening = ManualSource(), delayed = ManualSource()
        var sourceCalls = 0, immediateExport: CGImage?
        let finishing = ScrollingCaptureController(screen: screen, selection: CGRect(x: 0, y: 0, width: 96, height: 240),
            onClose: {}, makeSource: {
                sourceCalls += 1
                if sourceCalls == 1 { return opening }
                try await Task.sleep(for: .milliseconds(200)); return delayed
            }, onCopy: { immediateExport = $0; return true })
        finishing.run(); try await wait { opening.continuation != nil }
        opening.send(staticPage); try await wait { finishing.pageButton.isEnabled }
        finishing.pageButton.performClick(nil); try await wait { opening.stopped && finishing.pageButton.isEnabled }
        finishing.pageButton.performClick(nil); try await wait { sourceCalls == 2 }
        finishing.finishAndCopy(); try await wait { immediateExport != nil }
        try check(try PixelRaster(immediateExport!).bytes == staticPage.bytes && delayed.stopped,
            "Finish during page preparation stops the fresh source and exports only valid existing pages")
        return passed
    }
    private static func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<250 { if predicate() { return }; try await Task.sleep(for: .milliseconds(20)) }
        throw Failure.timeout
    }
    private static func interpolated(_ page: PixelRaster, offset: Double, height: Int) -> PixelRaster {
        let y = Int(offset), phase = offset - Double(y)
        var frame = page.rows(y..<(y + height))
        for i in frame.bytes.indices {
            frame.bytes[i] = UInt8((Double(frame.bytes[i]) * (1 - phase) + Double(page.bytes[(y + 1) * page.width * 4 + i]) * phase).rounded())
        }
        return frame
    }
    private static func pattern(width: Int, height: Int, seed: UInt64) -> PixelRaster {
        var random = seed, bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            random = random &* 6364136223846793005 &+ 1442695040888963407
            let value = UInt8(truncatingIfNeeded: random >> 32), i = (y * width + x) * 4
            bytes[i] = value; bytes[i+1] = value; bytes[i+2] = value
        } }
        return PixelRaster(width: width, height: height, bytes: bytes)
    }
    private final class ManualSource: ScrollingCaptureSource {
        var continuation: AsyncThrowingStream<PixelRaster, Error>.Continuation?
        var stopped = false
        func frames() async throws -> AsyncThrowingStream<PixelRaster, Error> {
            let (frames, continuation) = AsyncThrowingStream<PixelRaster, Error>.makeStream()
            self.continuation = continuation; return frames
        }
        func send(_ raster: PixelRaster) { continuation?.yield(raster) }
        func stop() async { stopped = true; continuation?.finish() }
    }
}
