import AppKit
import ScreenCaptureKit
import Carbon.HIToolbox

@main
struct RegressionTests {
    @MainActor static func main() async throws {
        var passed = 0
        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            guard condition() else { fatalError("FAIL: \(name)") }
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
        print("\(passed) regression checks passed.")
    }
}
