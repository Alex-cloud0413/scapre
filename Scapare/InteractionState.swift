import AppKit
import Carbon.HIToolbox

struct CaptureShortcut: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    var isValid: Bool {
        let functionKeys: Set<UInt32> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        let modifierKeys: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        let supportedModifiers = UInt32(cmdKey | controlKey | optionKey | shiftKey)
        return keyCode != 53 && !modifierKeys.contains(keyCode)
            && (modifiers & supportedModifiers != 0 || functionKeys.contains(keyCode))
    }
}

/// Keep the previous registration alive until its replacement succeeds.
@MainActor
final class ShortcutBinding<Registration> {
    private(set) var shortcut: CaptureShortcut?
    private(set) var registration: Registration?

    func replace(with candidate: CaptureShortcut,
                 register: (CaptureShortcut) throws -> Registration,
                 persist: (CaptureShortcut) -> Void) throws {
        guard candidate != shortcut || registration == nil else { return }
        let replacement = try register(candidate)
        registration = replacement
        shortcut = candidate
        persist(candidate)
    }
}

struct EditSnapshot: Equatable, Codable {
    var selection: CGRect?
    var annotations: [Annotation] = []
}

/// A history entry owns its editing and undo state even while another entry is visible.
@MainActor
final class EditingSession {
    var snapshot = EditSnapshot()
    let undoManager = UndoManager()
    var onChange: (() -> Void)?

    init() {
        undoManager.groupsByEvent = false
        undoManager.levelsOfUndo = 100
    }

    func commit(from previous: EditSnapshot) {
        guard previous != snapshot else { return }
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { $0.restore(previous) }
        undoManager.setActionName("编辑截图")
        undoManager.endUndoGrouping()
        onChange?()
    }

    private func restore(_ value: EditSnapshot) {
        let inverse = snapshot
        undoManager.registerUndo(withTarget: self) { $0.restore(inverse) }
        snapshot = value
        onChange?()
    }
}

struct BoundedHistory<Entry> {
    private(set) var entries: [Entry] = []
    private(set) var index = 0
    let capacity: Int
    var current: Entry? { entries.isEmpty ? nil : entries[index] }

    mutating func append(_ entry: Entry) {
        entries.append(entry)
        if entries.count > max(1, capacity) { entries.removeFirst(entries.count - max(1, capacity)) }
        index = entries.count - 1
    }

    func destination(delta: Int) -> Int? {
        let target = index + delta
        return entries.indices.contains(target) && target != index ? target : nil
    }

    mutating func move(to target: Int) {
        guard entries.indices.contains(target) else { return }
        index = target
    }
}

enum SaveOutcome { case saved, cancelled }

enum SaveFlow {
    static func run(data: Data, chooseURL: () -> URL?,
                    write: (Data, URL) throws -> Void,
                    retry: (Error) -> Bool) -> SaveOutcome {
        while let url = chooseURL() {
            do { try write(data, url); return .saved }
            catch { if !retry(error) { return .cancelled } }
        }
        return .cancelled
    }
}

enum PixelGeometry {
    static func cropRect(selection: CGRect, viewSize: CGSize, imageSize: CGSize) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let rect = CGRect(x: selection.minX * imageSize.width / viewSize.width,
                          y: (viewSize.height - selection.maxY) * imageSize.height / viewSize.height,
                          width: selection.width * imageSize.width / viewSize.width,
                          height: selection.height * imageSize.height / viewSize.height).integral
        return rect.intersection(CGRect(origin: .zero, size: imageSize))
    }

    static func textHandle(for bounds: CGRect) -> CGRect {
        CGRect(x: bounds.maxX - 7, y: bounds.minY - 7, width: 14, height: 14)
    }
}

enum OCRState: Equatable {
    case loading, empty, result(String), failure(String)
    var text: String { if case .result(let value) = self { return value }; return "" }
    var canCopy: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    static func recognized(_ value: String) -> OCRState {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : .result(value)
    }
}
