import AppKit
import ApplicationServices

enum ElementPicker {
    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "element_detection") }
        set { UserDefaults.standard.set(newValue, forKey: "element_detection") }
    }
    static func requestPermission() -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
    static func frames(at cocoaPoint: CGPoint, processID: pid_t) -> [CGRect] {
        guard enabled, AXIsProcessTrusted() else { return [] }
        let app = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(app, 0.03)
        let referenceHeight = NSScreen.screens.first?.frame.height ?? 0
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(app, Float(cocoaPoint.x), Float(referenceHeight - cocoaPoint.y), &found) == .success,
              var element = found else { return [] }
        var result: [CGRect] = []
        for _ in 0..<5 {
            AXUIElementSetMessagingTimeout(element, 0.03)
            var positionValue: CFTypeRef?, sizeValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
               AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
               let positionValue, let sizeValue, CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() {
                var point = CGPoint.zero, size = CGSize.zero
                if AXValueGetValue(positionValue as! AXValue, .cgPoint, &point), AXValueGetValue(sizeValue as! AXValue, .cgSize, &size), size.width > 3, size.height > 3 {
                    let rect = CGRect(x: point.x, y: referenceHeight - point.y - size.height, width: size.width, height: size.height)
                    if rect.contains(cocoaPoint), !result.contains(rect) { result.append(rect) }
                }
            }
            var parent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parent) == .success,
                  let parent, CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            element = parent as! AXUIElement
        }
        return result
    }
}

final class HotCornerMonitor {
    private var timer: Timer?
    private var enteredAt: Date?
    private var fired = false
    private var currentCorner: Int?
    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }
    func stop() { timer?.invalidate(); timer = nil }
    private func poll() {
        guard UserDefaults.standard.bool(forKey: "hot_corner"), !ShortcutPolicy.ownsKeyboardFocus, !ShortcutPolicy.isIgnored else { enteredAt = nil; fired = false; return }
        let point = NSEvent.mouseLocation
        let points = NSScreen.screens.flatMap { screen in
            let f = screen.frame
            return [CGPoint(x: f.minX, y: f.maxY), CGPoint(x: f.maxX, y: f.maxY), CGPoint(x: f.minX, y: f.minY), CGPoint(x: f.maxX, y: f.minY)]
        }
        let corner = points.firstIndex { abs(point.x - $0.x) < 5 && abs(point.y - $0.y) < 5 }.map { $0 % 4 }
        if corner != currentCorner { currentCorner = corner; enteredAt = nil; fired = false }
        guard let corner else { return }
        if enteredAt == nil { enteredAt = Date() }
        if !fired, Date().timeIntervalSince(enteredAt!) >= 0.8 {
            fired = true
            let values = UserDefaults.standard.array(forKey: "hot_corner_actions") as? [Int] ?? [0, 1, 0, 0]
            guard values.count == 4 else { return }
            switch values[corner] {
            case 1: CaptureController.shared.startCapture()
            case 2: PinManager.shared.pasteClipboard()
            case 3: ShortcutAction.togglePins.run()
            case 4: PinManager.shared.showAll()
            case 5: PinManager.shared.hideAll()
            default: break
            }
        }
    }
}
