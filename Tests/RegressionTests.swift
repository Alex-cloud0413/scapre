import AppKit
import ScreenCaptureKit
import Carbon.HIToolbox
import Darwin
import CoreVideo

@main
struct RegressionTests {
    @MainActor static func main() async throws {
        setbuf(stdout, nil)
        var passed = 0
        func check(_ condition: @autoclosure () throws -> Bool, _ name: String) rethrows {
            guard try condition() else { fatalError("FAIL: \(name)") }
            passed += 1
            print("PASS: \(name)")
        }
        enum Failure: Error { case occupied, diskFull }
        final class Token {}
        let functionKeys: [UInt32] = [122,120,99,118,96,97,98,100,101,109,103,111]
        check(functionKeys.allSatisfy { CaptureShortcut(keyCode: $0, modifiers: 0).isValid }, "All F1–F12 work without modifiers")
        check(!CaptureShortcut(keyCode: 0, modifiers: 0).isValid, "Unmodified letters are rejected")
        check(!CaptureShortcut(keyCode: 53, modifiers: UInt32(cmdKey)).isValid, "Escape remains a cancellation key")
        check(!CaptureShortcut(keyCode: 56, modifiers: UInt32(shiftKey)).isValid, "Modifier-only input is rejected")
        check(CaptureShortcut(keyCode: 0, modifiers: UInt32(cmdKey | shiftKey)).isValid, "Modified letters are accepted")

        let binding = ShortcutBinding<Token>()
        let first = CaptureShortcut(keyCode: 0, modifiers: UInt32(cmdKey))
        let second = CaptureShortcut(keyCode: 1, modifiers: UInt32(cmdKey))
        var saved: [CaptureShortcut] = []
        let original = Token()
        try binding.replace(with: first, register: { _ in original }, persist: { saved.append($0) })
        do {
            try binding.replace(with: second, register: { _ in throw Failure.occupied }, persist: { saved.append($0) })
            fatalError("Registration failure was swallowed")
        } catch Failure.occupied {}
        check(binding.registration === original && binding.shortcut == first && saved == [first], "Conflict keeps the working binding and saved settings")
        var registeredAgain = false
        try binding.replace(with: first, register: { _ in registeredAgain = true; return Token() }, persist: { saved.append($0) })
        check(!registeredAgain && saved == [first], "Re-selecting the current shortcut is a no-op")
        try binding.replace(with: second, register: { _ in Token() }, persist: { saved.append($0) })
        check(binding.registration !== original && saved == [first,second], "Successful registration commits the new shortcut")

        let defaultsName = "Scapare.Tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: defaultsName)!
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        SettingsManager.initializeDefaults(in: defaults)
        check(defaults.integer(forKey: "shortcut_keyCode") == Int(SettingsManager.defaultKeyCode)
              && !defaults.bool(forKey: "setup_completed"), "First launch initializes a shortcut without completing onboarding")
        SettingsManager.save(keyCode: 122, modifiers: 0, in: defaults)
        SettingsManager.initializeDefaults(in: defaults)
        check(defaults.integer(forKey: "shortcut_keyCode") == 122 && !defaults.bool(forKey: "setup_completed"),
              "Changing the shortcut preserves incomplete onboarding across launches")
        defaults.set(true, forKey: "setup_completed")
        SettingsManager.initializeDefaults(in: defaults)
        check(defaults.bool(forKey: "setup_completed"), "Completed onboarding remains complete")
        defaults.removeObject(forKey: "setup_completed")
        SettingsManager.initializeDefaults(in: defaults)
        check(defaults.bool(forKey: "setup_completed") && defaults.integer(forKey: "shortcut_keyCode") == 122,
              "Existing users retain their shortcut during onboarding migration")

        let sessionA = EditingSession()
        let sessionB = EditingSession()
        var before = sessionA.snapshot
        sessionA.snapshot.selection = CGRect(x: 10, y: 20, width: 100, height: 80)
        sessionA.commit(from: before)
        before = sessionA.snapshot
        var annotation = Annotation(tool: .rectangle, color: .blue, lineWidth: 2)
        annotation.start = CGPoint(x: 20, y: 30)
        annotation.end = CGPoint(x: 80, y: 60)
        sessionA.snapshot.annotations.append(annotation)
        sessionA.commit(from: before)
        let editedA = sessionA.snapshot
        sessionA.undoManager.undo()
        check(sessionA.snapshot.annotations.isEmpty && sessionA.snapshot.selection == before.selection, "Undo removes the last annotation without losing the selection")
        sessionA.undoManager.redo()
        check(sessionA.snapshot == editedA, "Redo restores the exact annotation")
        var history = BoundedHistory<EditingSession>(capacity: 6)
        history.append(sessionA)
        history.append(sessionB)
        history.move(to: history.destination(delta: -1)!)
        check(history.current === sessionA && history.current?.snapshot == editedA, "History navigation preserves the edited session")
        history.current?.undoManager.undo()
        history.move(to: 1)
        check(history.current === sessionB && history.current?.snapshot.annotations.isEmpty == true, "Each history entry has isolated undo state")
        history.move(to: 0)
        history.current?.undoManager.redo()
        check(history.current?.snapshot == editedA, "Undo and redo survive switching away and back")
        check(history.destination(delta: -1) == nil && history.index == 0, "History boundary does not mutate the active entry")
        for _ in 0..<6 { history.append(EditingSession()) }
        check(history.entries.count == 6 && history.index == 5, "History retention stays bounded to six captures")
        sessionA.undoManager.undo()
        before = sessionA.snapshot
        sessionA.snapshot.annotations.append(Annotation(tool: .ellipse, color: .red, lineWidth: 3))
        sessionA.commit(from: before)
        check(!sessionA.undoManager.canRedo, "A new edit after undo discards stale redo")

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("scapare-regression-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let url = temp.appendingPathComponent("capture.png")
        let bytes = Data([1,2,3,4])
        var writeCount = 0
        let cancelled = SaveFlow.run(data: bytes, chooseURL: { nil }, write: { _,_ in writeCount += 1 }, retry: { _ in fatalError() })
        check(cancelled == .cancelled && writeCount == 0, "Cancelling the save panel never writes or reports success")
        var retryCount = 0
        let failed = SaveFlow.run(data: bytes, chooseURL: { url }, write: { _,_ in throw Failure.diskFull }, retry: { _ in retryCount += 1; return false })
        check(failed == .cancelled && retryCount == 1, "Write failure surfaces once and returns to editing")
        let retried = SaveFlow.run(data: bytes, chooseURL: { url }, write: { data, target in
            writeCount += 1
            if writeCount == 1 { throw Failure.diskFull }
            try data.write(to: target, options: .atomic)
        }, retry: { _ in true })
        let savedData = try Data(contentsOf: url)
        check(retried == .saved && savedData == bytes && writeCount == 2, "Retry writes the original image bytes successfully")

        check(!OCRState.loading.canCopy && !OCRState.empty.canCopy && !OCRState.failure("failure").canCopy, "Loading, empty and failed OCR cannot copy placeholders")
        check(OCRState.recognized("  \n ") == .empty, "Whitespace-only OCR is treated as empty")
        check(OCRState.recognized("你好\nScapare").text == "你好\nScapare", "OCR preserves meaningful multiline text")
        do {
            _ = try await OCRService.recognize(pngData: Data([0,1,2]))
            fatalError("Invalid image should fail")
        } catch { check(!error.localizedDescription.isEmpty, "Invalid OCR input produces an error rather than an empty success") }

        let permission = NSError(domain: SCStreamErrorDomain, code: SCStreamError.Code.userDeclined.rawValue)
        if case .permissionDenied = ScreenshotError.classify(permission) { check(true, "Permission denial is classified separately") }
        else { fatalError("Wrong permission classification") }
        if case .captureFailed = ScreenshotError.classify(NSError(domain: "Other", code: permission.code)) { check(true, "Unrelated capture failure does not request permissions") }
        else { fatalError("Wrong capture classification") }

        let selection = CGRect(x: 10.25, y: 12.25, width: 20.5, height: 15.5)
        let pixels = PixelGeometry.cropRect(selection: selection, viewSize: CGSize(width: 100, height: 80), imageSize: CGSize(width: 200,height: 160))
        check(pixels == CGRect(x: 20,y: 104,width: 42,height: 32), "Retina size uses the same integral pixel bounds as export")
        let oneX = PixelGeometry.cropRect(selection: CGRect(x: 10, y: 12, width: 20, height: 15),
                                         viewSize: CGSize(width: 100, height: 80), imageSize: CGSize(width: 100, height: 80))
        check(oneX == CGRect(x: 10, y: 53, width: 20, height: 15), "Non-Retina crops preserve one pixel per point")
        let textBounds = CGRect(x: 20,y: 30,width: 80,height: 20)
        let handle = PixelGeometry.textHandle(for: textBounds)
        check(handle.contains(CGPoint(x: 100,y: 30)) && !handle.contains(CGPoint(x: 50,y: 50)), "Text resize hit region matches the lower-right visual handle")
        let context = CGContext(data: nil, width: 200, height: 160, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.red.cgColor)
        context.fill(CGRect(x: 0,y: 0,width: 200,height: 160))
        let image = context.makeImage()!
        let plain = ScreenshotRenderer.render(image: image, selection: selection, viewSize: CGSize(width: 100,height: 80), annotations: [])!
        annotation.start = CGPoint(x: 12,y: 15)
        annotation.end = CGPoint(x: 26,y: 25)
        let marked = ScreenshotRenderer.render(image: image, selection: selection, viewSize: CGSize(width: 100,height: 80), annotations: [annotation])!
        check(plain.width == 42 && plain.height == 32 && marked.width == plain.width && marked.height == plain.height,
              "Annotation rendering preserves the exact source crop resolution")
        let plainBytes = plain.dataProvider!.data! as Data
        let markedBytes = marked.dataProvider!.data! as Data
        check(plainBytes[0] > 200 && markedBytes[0] > 200, "Compositing retains the screenshot background")
        let edgeOffset = 6 * marked.bytesPerRow + 10 * 4
        check(markedBytes[edgeOffset + 2] > 200 && markedBytes[edgeOffset] < 50,
              "Annotations align with the cropped source pixels on Retina")
        let exported = NSBitmapImageRep(data: NSImage(cgImage: marked, size: selection.size).pngData!)!
        check(exported.pixelsWide == 42 && exported.pixelsHigh == 32,
              "Final PNG encoding preserves the dimensions shown in the selection label")

        func patterned(width: Int, height: Int) -> PixelRaster {
            var bytes = [UInt8](repeating: 255, count: width * height * 4)
            var random: UInt64 = 1289
            for y in 0..<height { for x in 0..<width {
                random = random &* 6364136223846793005 &+ 1442695040888963407
                let v = UInt8(truncatingIfNeeded: random >> 32), i = (y * width + x) * 4
                bytes[i] = v; bytes[i+1] = v; bytes[i+2] = v
            } }
            return PixelRaster(width: width, height: height, bytes: bytes)
        }
        let page = patterned(width: 96, height: 800)
        let frame1 = page.rows(0..<240), frame2 = page.rows(80..<320), frame3 = page.rows(180..<420)
        let roundTrip = try PixelRaster(frame1.image()!)
        check(roundTrip.bytes == frame1.bytes, "Pixel normalization preserves row order and colors")
        try check(try ScrollMatcher.match(frame1, frame1) == .unchanged, "Stationary long-capture frames are ignored")
        try check(try ScrollMatcher.match(frame1, frame2) == .advance(80), "Long capture finds an exact vertical overlap")
        var stitcher = ScrollStitcher(first: frame1)
        _ = try stitcher.append(frame2); _ = try stitcher.append(frame3)
        let stitched = try PixelRaster(stitcher.image()!)
        check(stitcher.height == 420 && stitcher.frameCount == 3 && stitched.bytes == page.rows(0..<420).bytes,
              "Three scrolling frames stitch into the exact original pixels without duplicate rows")
        let stitchedHeight = stitcher.height
        do { _ = try stitcher.append(page.rows(500..<740)); fatalError("Unmatched scroll accepted") }
        catch { check(stitcher.height == stitchedHeight, "Excessive scroll leaves the completed long capture intact") }
        do { _ = try ScrollMatcher.match(frame2, frame1); fatalError("Reverse scroll accepted") }
        catch { check(true, "Reverse scrolling is not silently appended") }
        var limited = ScrollStitcher(first: frame1, maxHeight: 260)
        do { _ = try limited.append(frame2); fatalError("Long capture exceeded its limit") }
        catch { check(limited.height == 240, "Long capture enforces its length limit without losing previous frames") }
        var repeatedBytes = frame1.bytes
        for y in 0..<240 { for x in 0..<96 {
            let i = (y * 96 + x) * 4, value: UInt8 = (y % 20 < 8) ? 0 : 255
            repeatedBytes[i] = value; repeatedBytes[i+1] = value; repeatedBytes[i+2] = value
        } }
        let repeating = PixelRaster(width: 96, height: 240, bytes: repeatedBytes)
        let shiftedRepeating = PixelRaster(width: 96, height: 240, bytes: Array(repeatedBytes[(5 * 96 * 4)...]) + Array(repeatedBytes[..<(5 * 96 * 4)]))
        do { _ = try ScrollMatcher.match(repeating, shiftedRepeating); fatalError("Ambiguous repeated texture accepted") }
        catch { check(true, "Repeated patterns are rejected instead of producing a guessed seam") }
        do { _ = try ScrollMatcher.match(frame1, page.rows(0..<200)); fatalError("Different size accepted") }
        catch { check(true, "Long capture rejects changed viewport dimensions") }

        // Use actual text on a white page, not only random noise. Repeated rows,
        // empty margins and fractional smooth scrolling are the difficult cases.
        func documentPage(width: Int, height: Int, table: Bool = false) throws -> PixelRaster {
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: width * 4, bitsPerPixel: 32)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
            NSColor.white.setFill(); NSBezierPath(rect: CGRect(x: 0, y: 0, width: width, height: height)).fill()
            let phrases = ["Continuous capture keeps document lines in order", "A screenshot should not require pauses", "Fast movement uses overlapping live frames", "Duplicate sections must never be appended", "Copy the finished image directly", "Numbers and paragraph lengths change the content"]
            for row in 0..<(height / 34) {
                let text = String(format: "%04d  ", row) + phrases[row % phrases.count] + " / " + String(row * 193 + 17)
                let line = table ? String(format: "Item %04d   total %08d", row, row * 719 + 4321) : text
                (line as NSString).draw(at: CGPoint(x: 36, y: height - 34 * row - 30),
                    withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 18, weight: .regular), .foregroundColor: NSColor.black])
            }
            NSGraphicsContext.restoreGraphicsState()
            return try PixelRaster(bitmap.cgImage!)
        }
        let textDocument = try documentPage(width: 1280, height: 10000)
        let viewportHeight = 1200
        var continuous = ScrollStitcher(first: textDocument.rows(0..<viewportHeight))
        let naturalOffsets = [19, 45, 82, 143, 245, 410, 680, 1070, 1610, 2330, 3210, 4000, 4520, 4860, 5100]
        let benchmarkStart = ContinuousClock.now
        for offset in naturalOffsets { _ = try continuous.append(textDocument.rows(offset..<(offset + viewportHeight))) }
        let elapsed = benchmarkStart.duration(to: .now)
        try check(try PixelRaster(continuous.image()!).bytes == textDocument.rows(0..<(5100 + viewportHeight)).bytes,
              "Natural and fast continuous text scrolling produces exact pixels without gaps or overlap")
        print("BENCHMARK: 1280 × 1200 text frames, \(naturalOffsets.count) matches in \(elapsed)")
        for offset in [4880, 4670, 4510, 4700, 4900, 5100, 5200] {
            _ = try continuous.append(textDocument.rows(offset..<(offset + viewportHeight)))
        }
        try check(try PixelRaster(continuous.image()!).bytes == textDocument.rows(0..<(5200 + viewportHeight)).bytes,
              "Scrolling backward and forward appends only content beyond the previous endpoint")
        var slow = ScrollStitcher(first: textDocument.rows(0..<viewportHeight))
        for offset in stride(from: 3, through: 150, by: 3) { _ = try slow.append(textDocument.rows(offset..<(offset + viewportHeight))) }
        check(slow.height == viewportHeight + 150, "Small continuous movements do not accumulate duplicated rows")
        func fractionalViewport(_ offset: Double) -> PixelRaster {
            let y = Int(offset), fraction = offset - Double(y)
            var output = textDocument.rows(y..<(y + viewportHeight))
            let following = textDocument.rows((y + 1)..<(y + 1 + viewportHeight))
            for i in output.bytes.indices {
                output.bytes[i] = UInt8((Double(output.bytes[i]) * (1 - fraction) + Double(following.bytes[i]) * fraction).rounded())
            }
            return output
        }
        var fractional = ScrollStitcher(first: textDocument.rows(0..<viewportHeight))
        var fractionalAccepted = 0
        for frame in 1...40 {
            if (try? fractional.append(fractionalViewport(Double(frame) * 0.6))) == true { fractionalAccepted += 1 }
        }
        check(abs(fractional.height - viewportHeight - 24) <= 1 && fractionalAccepted >= 10,
              "Fractional smooth scrolling does not round up each frame into duplicated content")
        let tableDocument = try documentPage(width: 1280, height: 4000, table: true)
        var tableCapture = ScrollStitcher(first: tableDocument.rows(0..<viewportHeight))
        for offset in [20, 58, 170, 415, 740, 1100, 1500] { _ = try tableCapture.append(tableDocument.rows(offset..<(offset + viewportHeight))) }
        try check(try PixelRaster(tableCapture.image()!).bytes == tableDocument.rows(0..<(1500 + viewportHeight)).bytes,
              "A narrow repeated table on a wide white page aligns by its distinct row content")
        let stickyHeader = patterned(width: 1280, height: 48), stickyFooter = patterned(width: 1280, height: 36)
        func stickyFrame(_ offset: Int) -> PixelRaster {
            PixelRaster(width: 1280, height: viewportHeight,
                bytes: stickyHeader.bytes + textDocument.rows(offset..<(offset + viewportHeight - 84)).bytes + stickyFooter.bytes)
        }
        var sticky = ScrollStitcher(first: stickyFrame(0))
        for offset in [30, 110, 250, 460, 650] { _ = try sticky.append(stickyFrame(offset)) }
        let stickyExpected = stickyHeader.bytes + textDocument.rows(0..<(650 + viewportHeight - 84)).bytes + stickyFooter.bytes
        try check(try PixelRaster(sticky.image()!).bytes == stickyExpected, "Fixed headers and footers appear once rather than at every join")

        // A selection around a browser window includes its bottom border/shadow.
        // These rows have vertical gradients but no horizontal text or noise.
        // They must be retained once, outside the appended document strips.
        func windowEdge(width: Int, height: Int) -> PixelRaster {
            var bytes = [UInt8](repeating: 255, count: width * height * 4)
            for y in 0..<height { for x in 0..<width {
                let i = (y * width + x) * 4
                let value = UInt8(90 + 150 * y / max(1, height - 1))
                bytes[i] = value; bytes[i+1] = value; bytes[i+2] = value
            } }
            return PixelRaster(width: width, height: height, bytes: bytes)
        }
        let shadowFooter = windowEdge(width: 1280, height: 44)
        func shadowFrame(_ offset: Int) -> PixelRaster {
            PixelRaster(width: 1280, height: viewportHeight,
                bytes: stickyHeader.bytes + textDocument.rows(offset..<(offset + viewportHeight - 92)).bytes + shadowFooter.bytes)
        }
        check(ScrollMatcher.fixedEdges(ScrollFeatures(shadowFrame(0)), ScrollFeatures(shadowFrame(3))).bottom == 44,
              "The fixed shadow extent excludes adjacent white document rows")
        var windowCapture = ScrollStitcher(first: shadowFrame(0))
        var everyWindowFrameIsExact = true
        for offset in [3, 8, 19, 45, 82, 143, 245, 410, 680, 1070, 1610] {
            _ = try windowCapture.append(shadowFrame(offset))
            let expected = stickyHeader.bytes + textDocument.rows(0..<(offset + viewportHeight - 92)).bytes + shadowFooter.bytes
            let actual = try PixelRaster(windowCapture.image()!)
            everyWindowFrameIsExact = everyWindowFrameIsExact && actual.bytes == expected
        }
        let windowExpected = stickyHeader.bytes + textDocument.rows(0..<(1610 + viewportHeight - 92)).bytes + shadowFooter.bytes
        try check(everyWindowFrameIsExact && (try PixelRaster(windowCapture.image()!).bytes == windowExpected),
              "A browser's uniform bottom border and shadow appear exactly once without repeated gray strips")
        for offset in [1450, 1300, 1500, 1610, 1740] { _ = try windowCapture.append(shadowFrame(offset)) }
        try check(try PixelRaster(windowCapture.image()!).bytes == stickyHeader.bytes
                  + textDocument.rows(0..<(1740 + viewportHeight - 92)).bytes + shadowFooter.bytes,
              "Scrolling back and forward retains the window shadow once and preserves all new document rows")

        var marginDocument = textDocument
        for rows in [0..<128, (viewportHeight - 128)..<(viewportHeight + 128)] {
            marginDocument.bytes.replaceSubrange((rows.lowerBound * 1280 * 4)..<(rows.upperBound * 1280 * 4),
                with: [UInt8](repeating: 255, count: rows.count * 1280 * 4))
        }
        let marginFirst = marginDocument.rows(0..<viewportHeight)
        let marginNext = marginDocument.rows(3..<(viewportHeight + 3))
        let marginEdges = ScrollMatcher.fixedEdges(ScrollFeatures(marginFirst), ScrollFeatures(marginNext))
        check(marginEdges.top == 0 && marginEdges.bottom == 0,
              "Stationary-looking white document margins are not classified as fixed window edges")
        var marginCapture = ScrollStitcher(first: marginFirst)
        for offset in [3, 19, 82, 143, 245, 410, 680, 850, 1070, 1350, 1610] {
            _ = try marginCapture.append(marginDocument.rows(offset..<(offset + viewportHeight)))
        }
        try check(try PixelRaster(marginCapture.image()!).bytes == marginDocument.rows(0..<(1610 + viewportHeight)).bytes,
              "Real white document margins retain every source row after continuous scrolling")

        // A browser selection can contain a moving feed alongside a stationary
        // sidebar. Those stationary edges must not veto the document movement.
        let sidebar = try documentPage(width: 1280, height: viewportHeight, table: true)
        func browserFrame(_ offset: Int) -> PixelRaster {
            var raster = stickyFrame(offset)
            for y in 48..<(viewportHeight - 36) {
                let start = (y * raster.width + 900) * 4
                let end = (y + 1) * raster.width * 4
                raster.bytes.replaceSubrange(start..<end, with: sidebar.bytes[start..<end])
                // Distinct cards and numbers in the right-hand stationary panel.
                for x in 925..<1240 where (y % 53 < 16 && x % 29 < 18) {
                    let i = (y * raster.width + x) * 4
                    raster.bytes[i] = UInt8((y / 53 * 31 + x / 29 * 7) % 170)
                    raster.bytes[i+1] = raster.bytes[i]; raster.bytes[i+2] = raster.bytes[i]
                }
            }
            return raster
        }
        var browser = ScrollStitcher(first: browserFrame(0))
        for offset in [19, 45, 82, 143, 245, 410, 680, 1070, 1610] {
            _ = try browser.append(browserFrame(offset))
        }
        check(browser.height == viewportHeight + 1610 && browser.frameCount > 5,
              "A moving browser feed stitches continuously beside a stationary sidebar")
        func columnPixels(in raster: PixelRaster, columns: Range<Int>) -> [UInt8] {
            (0..<raster.height).flatMap { y in
                Array(raster.bytes[((y * raster.width + columns.lowerBound) * 4)..<((y * raster.width + columns.upperBound) * 4)])
            }
        }
        let browserOutput = try PixelRaster(browser.image()!)
        let browserExpected = PixelRaster(width: 1280, height: viewportHeight + 1610,
            bytes: stickyHeader.bytes + textDocument.rows(0..<(1610 + viewportHeight - 84)).bytes + stickyFooter.bytes)
        check(columnPixels(in: browserOutput, columns: 0..<880) == columnPixels(in: browserExpected, columns: 0..<880),
              "The browser's moving column preserves every original row without duplicates")
        let savedBrowserHeight = browser.height
        do { _ = try browser.append(browserFrame(7500)); fatalError("Browser jump without overlap accepted") }
        catch { check(browser.height == savedBrowserHeight, "A fixed sidebar cannot hide missing overlap after a large document jump") }
        func animatedBrowserFrame(_ offset: Int, tick: Int) -> PixelRaster {
            var raster = browserFrame(offset)
            for y in 310..<430 { for x in 630..<800 {
                let i = (y * raster.width + x) * 4
                raster.bytes[i] = UInt8((x * 7 + y * 11 + tick * 37) % 256)
                raster.bytes[i+1] = UInt8((x + tick * 29) % 256)
                raster.bytes[i+2] = UInt8((y * 3 + tick * 13) % 256)
            } }
            return raster
        }
        var animatedBrowser = ScrollStitcher(first: animatedBrowserFrame(0, tick: 0))
        for (tick, offset) in [19, 45, 82, 143, 245, 410, 680, 1070, 1610].enumerated() {
            _ = try animatedBrowser.append(animatedBrowserFrame(offset, tick: tick + 1))
        }
        check(animatedBrowser.height == viewportHeight + 1610,
              "A localized animated card does not require the rest of the page to stop scrolling")
        var stationaryAnimation = ScrollStitcher(first: animatedBrowserFrame(0, tick: 0))
        for tick in 1...12 { _ = try? stationaryAnimation.append(animatedBrowserFrame(0, tick: tick)) }
        check(stationaryAnimation.height == viewportHeight,
              "Animation without document movement never extends the screenshot")

        // Retina-sized Chinese feed, as in the reported browser screenshot.
        let chineseWidth = 3349, chineseHeight = 1936, chineseDocumentHeight = 6500
        let chineseBitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: chineseWidth, pixelsHigh: chineseDocumentHeight,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: chineseWidth * 4, bitsPerPixel: 32)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: chineseBitmap)
        NSColor.white.setFill(); NSBezierPath(rect: CGRect(x: 0, y: 0, width: chineseWidth, height: chineseDocumentHeight)).fill()
        let chinesePhrases = ["连续滚动时不应要求停下来才能拼接", "固定导航和侧栏不应干扰正文衔接", "每一段内容都应按原来的顺序保存", "加速和回滚之后不能产生重复内容"]
        for row in 0..<(chineseDocumentHeight / 52) {
            ("第\(row)行  " + chinesePhrases[row % chinesePhrases.count] + "  \(row * 193 + 17)" as NSString)
                .draw(at: CGPoint(x: 520, y: chineseDocumentHeight - row * 52 - 42),
                      withAttributes: [.font: NSFont.systemFont(ofSize: 28), .foregroundColor: NSColor.black])
        }
        NSGraphicsContext.restoreGraphicsState()
        let chinesePage = try PixelRaster(chineseBitmap.cgImage!)
        let chineseHeader = patterned(width: chineseWidth, height: 240)
        let chineseSide = patterned(width: 650, height: chineseHeight - 240)
        func chineseFrame(_ offset: Double) -> PixelRaster {
            let y = Int(offset), fraction = offset - Double(y)
            var body = chinesePage.rows(y..<(y + chineseHeight - 240))
            if fraction > 0 {
                let following = chinesePage.rows((y + 1)..<(y + 1 + chineseHeight - 240))
                for i in body.bytes.indices {
                    body.bytes[i] = UInt8((Double(body.bytes[i]) * (1 - fraction) + Double(following.bytes[i]) * fraction).rounded())
                }
            }
            for row in 0..<body.height {
                body.bytes.replaceSubrange(((row * chineseWidth + 2100) * 4)..<((row * chineseWidth + 2750) * 4),
                    with: chineseSide.bytes[(row * 650 * 4)..<((row + 1) * 650 * 4)])
            }
            return PixelRaster(width: chineseWidth, height: chineseHeight, bytes: chineseHeader.bytes + body.bytes)
        }
        var chineseCapture = ScrollStitcher(first: chineseFrame(0))
        let chineseOffsets: [Double] = [12.6, 45.2, 87.8, 151.4, 310.6, 650.2, 1120.8, 1800.4, 2500, 2780, 3100]
        let chineseStart = ContinuousClock.now
        var chineseMatchTime = Duration.zero
        for offset in chineseOffsets {
            let frame = chineseFrame(offset), start = ContinuousClock.now
            do { _ = try chineseCapture.append(frame) }
            catch { print("CHINESE_FAILURE at \(offset): \(error)"); throw error }
            chineseMatchTime += start.duration(to: .now)
        }
        check(abs(chineseCapture.height - chineseHeight - 3100) <= 1 && chineseCapture.frameCount > 8,
              "Retina Chinese text with fixed navigation/sidebar accepts fractional and fast scrolling")
        print("BENCHMARK: 3349 × 1936 mixed Chinese frames, \(chineseOffsets.count) matches in \(chineseMatchTime); including fixture generation \(chineseStart.duration(to: .now))")
        var integerChinese = ScrollStitcher(first: chineseFrame(0))
        for offset in [19, 45, 82, 143, 245, 410, 680, 1070, 1610] { _ = try integerChinese.append(chineseFrame(Double(offset))) }
        let integerChineseOutput = try PixelRaster(integerChinese.image()!)
        let integerChineseExpected = PixelRaster(width: chineseWidth, height: chineseHeight + 1610,
            bytes: chineseHeader.bytes + chinesePage.rows(0..<(chineseHeight - 240 + 1610)).bytes)
        check(columnPixels(in: integerChineseOutput, columns: 500..<1700) == columnPixels(in: integerChineseExpected, columns: 500..<1700),
              "Retina Chinese feed keeps exact source rows across successive moving frames")
        for from in [0.125, 0.375, 0.625, 0.875] {
            let reference = chineseFrame(from)
            for to in [0.125, 0.375, 0.625, 0.875] {
                do {
                    let shift = try ScrollMatcher.displacement(reference, chineseFrame(150 + to), excludingTop: 240)
                    check(abs(Double(shift) - (150 + to - from)) <= 1,
                          "Chinese glyph phases \(from) → \(to) retain the physical displacement")
                } catch { print("PHASE_FAILURE \(from) → \(to): \(error)"); throw error }
            }
        }

        let turned = try ImageTransform.apply(frame1.image()!, quarterTurns: 1, flipHorizontal: false, flipVertical: false)
        check(turned.width == 240 && turned.height == 96, "Pin rotation swaps dimensions")
        let restored = try ImageTransform.apply(turned, quarterTurns: -1, flipHorizontal: false, flipVertical: false)
        let restoredPixels = try PixelRaster(restored)
        check(restoredPixels.bytes == frame1.bytes, "Inverse pin rotations preserve every pixel")
        let flipped = try ImageTransform.apply(frame1.image()!, quarterTurns: 0, flipHorizontal: true, flipVertical: false)
        let unflipped = try ImageTransform.apply(flipped, quarterTurns: 0, flipHorizontal: true, flipVertical: false)
        let unflippedPixels = try PixelRaster(unflipped)
        check(unflippedPixels.bytes == frame1.bytes, "Two horizontal flips restore the source pixels")
        let sourceImage = NSImage(cgImage: frame1.image()!, size: CGSize(width: 96, height: 240))
        for ext in ["png", "jpg", "tiff", "bmp", "gif"] {
            let encoded = try ImageFileSaver.encoded(sourceImage, extension: ext)
            let decoded = NSBitmapImageRep(data: encoded)!
            check(decoded.pixelsWide == 96 && decoded.pixelsHigh == 240, "\(ext.uppercased()) export preserves image dimensions")
        }
        var styled = annotation
        styled.tool = .highlighter; styled.dashed = true; styled.rotation = 30; styled.opacity = 0.5
        styled.textBackground = "FFFFFF"; styled.doubleArrow = true; styled.ellipticalMask = true
        let decodedAnnotation = try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(styled))
        check(decodedAnnotation.tool == styled.tool && decodedAnnotation.color.hexString == styled.color.hexString && decodedAnnotation.rotation == 30 && decodedAnnotation.dashed && decodedAnnotation.opacity == 0.5,
              "Editable annotations preserve style and geometry through backup encoding")
        let photoData = sourceImage.pngData!
        var pin = PinRecord(imageData: photoData, snapshot: EditSnapshot(selection: CGRect(x: 0, y: 0, width: 96, height: 240), annotations: [styled]), frame: CGRect(x: 20, y: 30, width: 96, height: 240))
        pin.group = "设计参考"; pin.quarterTurns = 1; pin.hidden = true
        let pinStore = PinStore(url: temp.appendingPathComponent("Pins.json"))
        try pinStore.write([pin]); let loaded = try pinStore.read()
        check(loaded.count == 1 && loaded[0].group == pin.group && loaded[0].hidden && loaded[0].snapshot?.annotations.first?.tool == .highlighter,
              "Pin backups preserve image data, groups, visibility and editable annotations")
        pin.group = "新分组"; try pinStore.write([pin])
        try Data("invalid".utf8).write(to: pinStore.url)
        try check(try pinStore.read()[0].group == "设计参考", "A corrupt pin archive recovers from the previous valid backup")
        do { _ = try PinStore.decode(JSONEncoder().encode(PinArchive(version: 99, pins: [pin]))); fatalError("Unknown schema accepted") }
        catch { check(true, "Pin import rejects unsupported archive versions") }
        do { _ = try PinStore.decode(JSONEncoder().encode(PinArchive(pins: [pin, pin]))); fatalError("Duplicate pin IDs accepted") }
        catch { check(true, "Pin import rejects duplicate identities") }
        let sourceRaster = frame1.image()!
        if let mosaic = ImageEffects.redact(sourceRaster, tool: .mosaic, amount: 12), let blurred = ImageEffects.redact(sourceRaster, tool: .blur, amount: 12) {
            let m = try PixelRaster(mosaic), b = try PixelRaster(blurred)
            check(m.width == 96 && m.height == 240 && m.bytes != frame1.bytes, "Mosaic changes source pixels while preserving dimensions")
            check(b.width == 96 && b.height == 240 && b.bytes != frame1.bytes, "Blur changes source pixels while preserving dimensions")
        } else { fatalError("Redaction filters failed") }
        let tall = patterned(width: 96, height: 2100)
        try check(try ScrollMatcher.match(tall.rows(0..<1600), tall.rows(307..<1907)) == .advance(307), "Retina-height scrolling finds non-grid-aligned offsets")
        let decorated = ImageDecoration(cornerRadius: 20, borderWidth: 2, shadow: true).apply(sourceRaster)!
        check(decorated.width == 136 && decorated.height == 280, "Decorated export includes measured border and shadow padding")
        let rounded = try PixelRaster(ImageDecoration(cornerRadius: 20).apply(sourceRaster)!)
        check(rounded.bytes[3] == 0 && rounded.bytes[(120 * 96 + 48) * 4 + 3] == 255, "Rounded export keeps transparent corners and opaque image content")
        let jpeg = try ImageFileSaver.encoded(NSImage(cgImage: rounded.image()!, size: CGSize(width: 96, height: 240)), extension: "jpg")
        let jpegRaster = try PixelRaster(NSBitmapImageRep(data: jpeg)!.cgImage!)
        check(jpegRaster.bytes[0] > 230 && jpegRaster.bytes[1] > 230 && jpegRaster.bytes[2] > 230, "JPEG flattens transparent corners onto white")

        var request = AutomationRequest(command: "process"); request.region = [8, 20, 40, 60]; request.rotation = 90
        let processed = try AutomationImages.process(photoData, request: request)
        let output = NSBitmapImageRep(data: processed)!
        check(output.pixelsWide == 60 && output.pixelsHigh == 40, "CLI crop then rotation produces exact expected dimensions")
        request.region = [-2, 0, 40, 60]
        do { _ = try AutomationImages.process(photoData, request: request); fatalError("Out-of-bounds CLI crop accepted") }
        catch { check(true, "CLI refuses out-of-bounds crop without silently changing the request") }
        request = AutomationRequest(command: "process"); request.rotation = 13
        do { _ = try AutomationImages.process(photoData, request: request); fatalError("Invalid rotation accepted") }
        catch { check(true, "CLI rejects unsupported rotation") }
        request.rotation = nil; request.mosaic = [[0, 0, 48, 80]]
        let redacted = try PixelRaster(NSBitmapImageRep(data: AutomationImages.process(photoData, request: request))!.cgImage!)
        check(redacted.rows(0..<80).bytes != frame1.rows(0..<80).bytes && redacted.rows(80..<240).bytes == frame1.rows(80..<240).bytes,
              "CLI redaction affects the top-left requested region only")
        var cover = Annotation(tool: .rectangle, color: .red, lineWidth: 2); cover.filled = true; cover.start = .zero; cover.end = CGPoint(x: 96, y: 240)
        var erase = Annotation(tool: .eraser, color: .black, lineWidth: 2); erase.start = CGPoint(x: 0, y: 160); erase.end = CGPoint(x: 48, y: 240)
        let erasedImage = ScreenshotRenderer.render(image: sourceRaster, selection: CGRect(x: 0, y: 0, width: 96, height: 240), viewSize: CGSize(width: 96, height: 240), annotations: [cover, erase])!
        let erasedPixels = try PixelRaster(erasedImage)
        check(Array(erasedPixels.bytes[0..<48 * 4]) == Array(frame1.bytes[0..<48 * 4]) && erasedPixels.bytes[120 * 96 * 4] > 240,
              "Eraser restores original pixels over earlier annotations only within its region")
        var invalid = styled; invalid.fontSize = .infinity
        check(!invalid.isValid, "Import rejects non-finite annotation geometry")
        pin.snapshot = EditSnapshot(selection: CGRect(x: 0, y: 0, width: -1, height: 20), annotations: [])
        // CGRect normalizes negative widths in its accessors, so test a non-finite extent instead.
        pin.snapshot?.selection = CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 20)
        do { _ = try PinStore.decode(JSONEncoder().encode(PinArchive(pins: [pin]))); fatalError("Invalid snapshot accepted") }
        catch { check(true, "Invalid editable backup geometry is rejected") }
        let rich = ClipboardText.html("<p><strong>Hello</strong> &amp; <em>world</em> &#x4F60;</p><script>secret()</script><img src='https://example.invalid/a.png'>")
        check(rich.string.contains("Hello & world 你") && !rich.string.contains("secret"), "Clipboard HTML keeps text and entities while dropping executable content")
        let boldFont = rich.attribute(.font, at: 0, effectiveRange: nil) as! NSFont
        check(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask), "Clipboard HTML preserves local bold formatting")
        check(ClipboardText.image(rich).size.width > 100, "Rich clipboard text renders to a bounded local image")
        var options = AppearanceOptions()
        check(options.isValid, "Default appearance satisfies configuration bounds")
        check(options.statusSymbol == "longjuan" && BrandIcon.menuBarImage().isTemplate,
              "New installs use the LongJuan menu bar template")
        var legacyAppearance = AppearanceOptions()
        legacyAppearance.statusSymbol = "scissors"; legacyAppearance.theme = 2
        legacyAppearance.palette = ["00FF00", "0000FF"]
        defaults.set(try JSONEncoder().encode(legacyAppearance), forKey: "appearance_v1")
        AppearanceSettings.migrateBrandIcon(in: defaults)
        var expectedAppearance = legacyAppearance; expectedAppearance.statusSymbol = "longjuan"
        check(AppearanceSettings.options(in: defaults) == expectedAppearance,
              "Upgrade replaces default scissors and preserves theme and palette")
        defaults.set(try JSONEncoder().encode(legacyAppearance), forKey: "appearance_v1")
        AppearanceSettings.migrateBrandIcon(in: defaults)
        check(AppearanceSettings.options(in: defaults).statusSymbol == "scissors",
              "The icon migration never repeats after a user's later choice")
        defaults.removeObject(forKey: "longjuan_icon_migrated_v1")
        legacyAppearance.statusSymbol = "camera"
        defaults.set(try JSONEncoder().encode(legacyAppearance), forKey: "appearance_v1")
        AppearanceSettings.migrateBrandIcon(in: defaults)
        check(AppearanceSettings.options(in: defaults) == legacyAppearance,
              "Upgrade keeps a deliberately selected alternate menu bar icon")
        options.magnifierSize = .infinity
        check(!options.isValid, "Appearance import rejects invalid dimensions")
        options = AppearanceOptions(); options.palette = ["FF0000", "0000FF"]
        try check(try JSONDecoder().decode(AppearanceOptions.self, from: JSONEncoder().encode(options)) == options, "Shared appearance preserves palette order and settings")
        styled.fontName = "Helvetica"; styled.textOutlineColor = "123456"; styled.arrowStyle = 1
        let richAnnotation = try JSONDecoder().decode(Annotation.self, from: JSONEncoder().encode(styled))
        check(richAnnotation.fontName == "Helvetica" && richAnnotation.textOutlineColor == "123456" && richAnnotation.arrowStyle == 1, "Backup preserves custom fonts, outline colors and arrow styles")

        // Exercise the real AppKit target/action chain with synthetic source images.
        // Never captures the desktop, posts input events, or touches the clipboard.
        _ = NSApplication.shared
        guard let screen = NSScreen.screens.first else { throw NSError(domain: "Scapare.Tests", code: 1, userInfo: [NSLocalizedDescriptionKey: "AppKit regression checks require access to the macOS window server."]) }
        let editorSession = EditingSession()
        var requestedRegion: CGRect?
        let capture = CaptureController(beginScrollingCapture: { _, rect, finished in
            requestedRegion = rect
            finished()
        })
        let editor = EditorView(shot: DisplayShot(screen: screen, image: frame1.image()!),
                                controller: capture, session: editorSession, canvasSize: CGSize(width: 1200, height: 800))
        editor.setSelection(CGRect(x: 100, y: 160, width: 360, height: 240))
        func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
        let toolbar = descendants(editor).compactMap { $0 as? EditorToolbar }.first!
        let scrollButton = descendants(toolbar).compactMap { $0 as? NSButton }.first { $0.identifier?.rawValue == "scrolling-capture" }!
        scrollButton.performClick(nil)
        check(requestedRegion == editorSession.snapshot.selection, "Toolbar click dispatches the selected region into scrolling capture")
        requestedRegion = nil
        editor.setSelection(CGRect(x: 100, y: 160, width: 10, height: 20))
        scrollButton.performClick(nil)
        check(requestedRegion == nil && descendants(editor).compactMap { $0 as? NSTextField }.contains { $0.stringValue.contains("选区太小") },
              "Small scroll selections show actionable feedback instead of failing silently")
        let testWindow = NSWindow(contentRect: editor.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        testWindow.isReleasedWhenClosed = false
        testWindow.contentView = editor
        editor.setSelection(CGRect(x: 100, y: 160, width: 360, height: 240))
        editor.setHistoryStatus("框选后选择工具；鼠标悬停可查看功能")
        testWindow.contentView?.layoutSubtreeIfNeeded()
        toolbar.layoutSubtreeIfNeeded()
        let hoverPoint = scrollButton.convert(CGPoint(x: scrollButton.bounds.midX, y: scrollButton.bounds.midY), to: nil)
        let hoverEvent = NSEvent.mouseEvent(with: .mouseMoved, location: hoverPoint, modifierFlags: [], timestamp: 0,
            windowNumber: testWindow.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0)!
        toolbar.mouseMoved(with: hoverEvent)
        check(editor.subviews.compactMap { $0 as? ToolbarHelpBubble }.contains { $0.label.stringValue.contains("滚动截图") },
              "Real toolbar hover routing shows the function hint above the editor")
        if let renderPath = ProcessInfo.processInfo.environment["SCAPARE_TEST_RENDER_DIR"] {
            let folder = URL(fileURLWithPath: renderPath)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let rect = editor.bounds
            if let bitmap = editor.bitmapImageRepForCachingDisplay(in: rect) {
                editor.cacheDisplay(in: rect, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: folder.appendingPathComponent("toolbar-hover.png"))
            }
        }
        toolbar.mouseExited(with: hoverEvent)
        check(!editor.subviews.contains { $0 is ToolbarHelpBubble }, "Toolbar mouse exit removes the displayed hint")
        let buttons = descendants(toolbar).compactMap { $0 as? NSControl }.filter { $0 is NSButton || $0 is NSSegmentedControl }
        check(!buttons.isEmpty && buttons.allSatisfy { !($0.toolTip ?? "").isEmpty }, "Every toolbar button, menu and width selector has a function hint")

        let host = NSView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let clippingScroll = NSScrollView(frame: CGRect(x: 200, y: 20, width: 400, height: 44))
        let document = NSView(frame: CGRect(x: 0, y: 0, width: 1000, height: 44))
        let control = NSButton(frame: CGRect(x: 240, y: 8, width: 30, height: 28))
        document.addSubview(control)
        clippingScroll.documentView = document
        host.addSubview(clippingScroll)
        clippingScroll.contentView.scroll(to: CGPoint(x: 200, y: 0))
        let help = ToolbarHoverHelp()
        help.show("滚动截图", for: control, in: host)
        check(help.bubble.superview === host && host.bounds.contains(help.bubble.frame), "Hover help escapes toolbar clipping and stays within the capture window")
        check(help.bubble.hitTest(help.bubble.frame.origin) == nil, "Hover help does not intercept mouse input")
        control.frame.origin.y = 560
        host.addSubview(control)
        help.show("顶部提示", for: control, in: host)
        check(host.bounds.contains(help.bubble.frame), "Hover help remains visible near the top edge")
        help.hide()
        check(help.bubble.superview == nil, "Hover exit removes the hint")
        check(ScrollMatcher.isUnchanged(frame1, frame1) && !ScrollMatcher.isUnchanged(frame1, frame2), "Stable-frame check distinguishes still content from scrolling")
        let fullSizePreview = try PixelRaster(stitcher.preview(maxSize: CGSize(width: 96, height: 420))!)
        check(fullSizePreview.bytes == stitched.bytes, "Live preview preserves the exact top-to-bottom order of stitched strips")
        let smallPreview = stitcher.preview(maxSize: CGSize(width: 80, height: 120))!
        check(smallPreview.width <= 80 && smallPreview.height <= 120, "Live preview uses bounded thumbnail dimensions")
        let visible = CGRect(x: -1200, y: -100, width: 1200, height: 800)
        let region = CGRect(x: -1100, y: 100, width: 400, height: 400)
        let panelSize = CGSize(width: 440, height: 262)
        let origin = ScrollCaptureLayout.panelOrigin(size: panelSize, region: region, visibleFrame: visible)
        check(visible.contains(CGRect(origin: origin, size: panelSize)) && !region.intersects(CGRect(origin: origin, size: panelSize)),
              "Scroll controls avoid the selected region on an offset secondary display")
        let fullOrigin = ScrollCaptureLayout.panelOrigin(size: panelSize, region: visible, visibleFrame: visible)
        check(visible.contains(CGRect(origin: fullOrigin, size: panelSize)), "Full-screen selections keep scroll controls reachable")

        final class SyntheticScrollSource: ScrollingCaptureSource {
            let images: [PixelRaster]
            var count = 0
            var fails = false
            var stopped = false
            var continuation: AsyncThrowingStream<PixelRaster, Error>.Continuation?
            var producer: Task<Void, Never>?
            init(_ images: [PixelRaster]) { self.images = images }
            func frames() async throws -> AsyncThrowingStream<PixelRaster, Error> {
                if fails { throw Failure.occupied }
                let (stream, continuation) = AsyncThrowingStream<PixelRaster, Error>.makeStream()
                self.continuation = continuation
                producer = Task {
                    for image in images {
                        guard !Task.isCancelled else { return }
                        count += 1
                        continuation.yield(image)
                        try? await Task.sleep(for: .milliseconds(16))
                    }
                }
                return stream
            }
            func stop() async { stopped = true; producer?.cancel(); continuation?.finish() }
        }
        let synthetic = SyntheticScrollSource([frame1, frame2, frame3])
        var closeCount = 0
        var finishedImage: CGImage?
        let scrolling = ScrollingCaptureController(screen: screen, selection: CGRect(x: 20, y: 40, width: 96, height: 240),
            onClose: { closeCount += 1 }, makeSource: { synthetic }, onFinish: { finishedImage = $0 })
        check(!scrolling.panel.hidesOnDeactivate && !scrolling.regionOutline.hidesOnDeactivate && scrolling.regionOutline.ignoresMouseEvents,
              "Scroll controls survive app deactivation and the region outline passes input through")
        scrolling.run()
        for _ in 0..<150 {
            if descendants(scrolling.panel.contentView!).compactMap({ $0 as? NSTextField }).contains(where: { $0.stringValue.contains("3 帧") }) { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        check(scrolling.finishButton.isEnabled && synthetic.count >= 3, "Continuous capture consumes moving frames without waiting for a duplicate stationary frame")
        if let renderPath = ProcessInfo.processInfo.environment["SCAPARE_TEST_RENDER_DIR"], let content = scrolling.panel.contentView {
            content.layoutSubtreeIfNeeded()
            if let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                content.cacheDisplay(in: content.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: renderPath).appendingPathComponent("scroll-panel.png"))
            }
        }
        check(scrolling.panel.contentView!.frame.size == CGSize(width: 440, height: 240), "Live preview cannot enlarge the control panel off-screen")
        scrolling.finishButton.performClick(nil)
        for _ in 0..<100 { if finishedImage != nil { break }; try await Task.sleep(for: .milliseconds(20)) }
        let completed = try finishedImage.map(PixelRaster.init)
        check(completed?.bytes == stitched.bytes && closeCount == 1, "Finish button returns the stitched image and closes the capture exactly once")
        scrolling.close()
        check(closeCount == 1, "Repeated close cannot deliver a second completion")
        let failing = SyntheticScrollSource([frame1]); failing.fails = true
        var failedClosed = false
        let failedScrolling = ScrollingCaptureController(screen: screen, selection: CGRect(x: 0, y: 0, width: 96, height: 240),
            onClose: { failedClosed = true }, makeSource: { failing })
        failedScrolling.run()
        for _ in 0..<100 {
            if failedScrolling.status.stringValue.contains("捕获已停止") { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        check(failedScrolling.status.stringValue.contains("捕获已停止") && !failedScrolling.finishButton.isEnabled,
              "Initial capture failure remains visible without enabling an empty result")
        failedScrolling.close()
        check(failedClosed, "Failed capture can close and release the capture session")

        // ScreenCaptureKit's BGRA frames must be copied and channel-correct before
        // the system reuses its surface. The queue must retain the latest bounded tail.
        var pixelBuffer: CVPixelBuffer?
        check(CVPixelBufferCreate(kCFAllocatorDefault, 96, 240, kCVPixelFormatType_32BGRA, nil, &pixelBuffer) == kCVReturnSuccess,
              "Create a synthetic ScreenCaptureKit-format surface")
        let buffer = pixelBuffer!
        let receiver = ScrollFrameReceiver()
        for value in 0..<10 {
            CVPixelBufferLockBaseAddress(buffer, [])
            let pointer = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(buffer)
            for y in 0..<240 { for x in 0..<96 {
                let i = y * stride + x * 4
                pointer[i] = UInt8(value); pointer[i+1] = 72; pointer[i+2] = 180; pointer[i+3] = 255
            } }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            receiver.receive(buffer)
        }
        receiver.finish()
        var received: [PixelRaster] = []
        for try await frame in receiver.frames { received.append(frame) }
        check(received.count == 3 && received.map { $0.bytes[2] } == [7,8,9] && received.allSatisfy { $0.bytes[0] == 180 && $0.bytes[1] == 72 && $0.bytes[3] == 255 },
              "Bounded stream retains the newest three independent RGBA frames without channel swaps")

        final class BufferedScrollSource: ScrollingCaptureSource {
            let images: [PixelRaster]
            var continuation: AsyncThrowingStream<PixelRaster, Error>.Continuation?
            var stopped = false
            init(_ images: [PixelRaster]) { self.images = images }
            func frames() async throws -> AsyncThrowingStream<PixelRaster, Error> {
                let (stream, continuation) = AsyncThrowingStream<PixelRaster, Error>.makeStream()
                self.continuation = continuation
                for image in images { continuation.yield(image) }
                return stream
            }
            func stop() async { stopped = true; continuation?.finish() }
        }
        let copySource = BufferedScrollSource([frame1, frame2, frame3])
        let isolatedPasteboard = NSPasteboard(name: NSPasteboard.Name("Scapare.CopyTest." + UUID().uuidString))
        defer { isolatedPasteboard.clearContents() }
        var copyClosed = 0, copyCalls = 0, editCalls = 0
        let copying = ScrollingCaptureController(screen: screen, selection: CGRect(x: 0, y: 0, width: 96, height: 240),
            onClose: { copyClosed += 1 }, makeSource: { copySource },
            onCopy: { image in
                copyCalls += 1
                return Clipboard.copy(image: NSImage(cgImage: image, size: CGSize(width: image.width, height: image.height)), to: isolatedPasteboard)
            }, onFinish: { _ in editCalls += 1 })
        copying.run()
        for _ in 0..<100 { if copying.copyButton.isEnabled { break }; try await Task.sleep(for: .milliseconds(5)) }
        check(copying.copyButton.isEnabled, "Complete and Copy becomes available after the first live frame")
        copying.copyButton.performClick(nil)
        for _ in 0..<100 { if copyClosed > 0 { break }; try await Task.sleep(for: .milliseconds(10)) }
        let copiedPNG = isolatedPasteboard.data(forType: .png)!
        let copiedPixels = try PixelRaster(NSBitmapImageRep(data: copiedPNG)!.cgImage!)
        check(copiedPixels.bytes == stitched.bytes && copySource.stopped && copyClosed == 1 && copyCalls == 1 && editCalls == 0,
              "Complete and Copy drains queued frames into a pasteable exact long image without opening the editor")
        let retrySource = BufferedScrollSource([frame1])
        var retryClosed = false, copyAttempts = 0
        let retryCopy = ScrollingCaptureController(screen: screen, selection: CGRect(x: 0, y: 0, width: 96, height: 240),
            onClose: { retryClosed = true }, makeSource: { retrySource }, onCopy: { _ in copyAttempts += 1; return copyAttempts > 1 })
        retryCopy.run()
        for _ in 0..<100 { if retryCopy.copyButton.isEnabled { break }; try await Task.sleep(for: .milliseconds(5)) }
        retryCopy.copyButton.performClick(nil)
        for _ in 0..<100 { if retryCopy.status.stringValue.contains("复制失败") { break }; try await Task.sleep(for: .milliseconds(10)) }
        check(!retryClosed && retryCopy.copyButton.isEnabled && retryCopy.finishButton.isEnabled,
              "A clipboard failure preserves the long image and offers retry or editing")
        retryCopy.copyButton.performClick(nil)
        for _ in 0..<100 { if retryClosed { break }; try await Task.sleep(for: .milliseconds(10)) }
        check(retryClosed && copyAttempts == 2, "Copy can retry after the stream has stopped without restarting capture")

        let socketDirectory = URL(fileURLWithPath: "/private/tmp/sc-ipc-" + String(UUID().uuidString.prefix(8)))
        defer { try? FileManager.default.removeItem(at: socketDirectory) }
        let socketPath = socketDirectory.appendingPathComponent("socket").path
        let server = LocalAutomationServer(path: socketPath) { data in data }
        try server.start(); defer { server.stop() }
        let reply = try await Task.detached {
            let fd = try AutomationWire.connect(to: socketPath); defer { Darwin.close(fd) }
            let data = Data("Scapare protocol round-trip".utf8)
            try AutomationWire.send(data, to: fd); return try AutomationWire.receive(from: fd)
        }.value
        check(reply == Data("Scapare protocol round-trip".utf8), "Local automation round-trip preserves request bytes")
        let socketAttributes = try FileManager.default.attributesOfItem(atPath: socketPath)
        check((socketAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Local socket is accessible only to its owner")
        let secondServer = LocalAutomationServer(path: socketPath) { data in data }
        do { try secondServer.start(); fatalError("Active socket replaced") }
        catch { check(true, "A second App instance cannot replace the active command socket") }
        server.stop()
        check(!FileManager.default.fileExists(atPath: socketPath), "Disabling local automation removes its endpoint")
        do { _ = try AutomationWire.address(String(repeating: "x", count: 200)); fatalError("Oversized path accepted") }
        catch { check(true, "Oversized socket paths fail before a descriptor is opened") }
        print("\(passed) regression checks passed.")
    }
}
