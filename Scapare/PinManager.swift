import AppKit

final class PinManager {
    static let shared = PinManager()
    private(set) var controllers: [PinWindowController] = []
    var captureWindowIDs: Set<CGWindowID> { Set(controllers.compactMap(\.captureWindowID)) }
    private var preserveFailedArchive = false
    private var saveTask: Task<Void, Never>?
    private(set) var lastSaveError: String?
    var onChange: (() -> Void)?
    private var store: PinStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return PinStore(url: base.appendingPathComponent("Scapare/Pins.json"))
    }
    @discardableResult
    func add(_ image: NSImage, frame: CGRect? = nil, originalData: Data? = nil, sourceText: String? = nil, sourceHTML: String? = nil) -> Bool {
        guard controllers.count < 100 else { AppDialogs.error("最多保留 100 张贴图，请先导出或整理现有贴图。"); return false }
        guard let data = originalData ?? image.pngData else { return false }
        do { _ = try ImageInputs.decode(data) } catch { AppDialogs.error(error.localizedDescription); return false }
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let ratio = image.size.width / max(1, image.size.height)
        let w = min(600, screen.width * 0.7, image.size.width), h = min(screen.height * 0.7, w / ratio)
        let rect = frame ?? CGRect(x: screen.midX - h * ratio / 2, y: screen.midY - h / 2, width: h * ratio, height: h)
        var record = PinRecord(imageData: data, frame: rect); record.opacity = AppearanceSettings.options.pinOpacity; record.sourceText = sourceText; record.sourceHTML = sourceHTML
        install(record); changed(); return true
    }
    private func install(_ record: PinRecord) {
        let controller = PinWindowController(record: record)
        controller.onChange = { [weak self] in self?.changed() }
        controllers.append(controller); controller.showIfVisible()
    }
    func pasteClipboard() {
        do {
            let pb = NSPasteboard.general
            if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
                guard controllers.count + urls.count <= 100 else { throw ImageError.tooLarge }
                let data = try urls.map { try Data(contentsOf: $0, options: .mappedIfSafe) }
                let images = try data.map { try ImageInputs.decode($0) }
                for (image, bytes) in zip(images, data) { add(image, originalData: bytes) }
            } else {
                let image = try ImageInputs.clipboard()
                let isImage = pb.data(forType: .png) != nil || pb.data(forType: .tiff) != nil
                add(image, sourceText: isImage ? nil : pb.string(forType: .string).map { String($0.prefix(100_000)) }, sourceHTML: isImage ? nil : pb.string(forType: .html).map { String($0.prefix(300_000)) })
            }
        } catch { AppDialogs.error(error.localizedDescription) }
    }
    func restore() {
        guard SettingsManager.restorePins, FileManager.default.fileExists(atPath: store.url.path) else { return }
        do { for pin in try store.read() { install(pin) } }
        catch { preserveFailedArchive = true; lastSaveError = "贴图恢复失败，原始备份仍保留；可手动导出当前贴图：" + error.localizedDescription }
    }
    func changed() {
        onChange?(); saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
            self?.saveNow()
        }
    }
    func saveNow() {
        guard SettingsManager.restorePins, !preserveFailedArchive else { return }
        do { try store.write(controllers.map(\.record)); lastSaveError = nil }
        catch { lastSaveError = error.localizedDescription }
        onChange?()
    }
    func showAll() { controllers.forEach { $0.setHidden(false) }; changed() }
    func hideAll() { controllers.forEach { $0.setHidden(true) }; changed() }
    func restoreMouseInteraction() { controllers.forEach { $0.setClickThrough(false) } }
    func solo(_ selected: PinWindowController) { controllers.forEach { $0.setHidden($0 !== selected) }; changed() }
    func remove(_ ids: Set<UUID>) {
        controllers.filter { ids.contains($0.record.id) }.forEach { $0.dispose() }
        controllers.removeAll { ids.contains($0.record.id) }; changed()
    }
    func exportPins(_ pins: [PinRecord]? = nil) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Scapare 可编辑贴图备份.json"
        panel.message = "可编辑备份包含原图和标注。若要分享打码后的图片，请使用「保存为图片」。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try JSONEncoder().encode(PinArchive(pins: pins ?? controllers.map(\.record))).write(to: url, options: .atomic) }
        catch { AppDialogs.error(error.localizedDescription) }
    }
    func archiveData(group: String? = nil) throws -> Data {
        try JSONEncoder().encode(PinArchive(pins: controllers.map(\.record).filter { group == nil || $0.group == group }))
    }
    func importData(_ data: Data) throws {
        let records = try PinStore.decode(data)
        guard controllers.count + records.count <= 100 else { throw ImageError.tooLarge }
        for var record in records { record.id = UUID(); install(record) }; changed()
    }
    func importPins() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 180_000_000 else { throw ImageError.tooLarge }
            try importData(Data(contentsOf: url))
        } catch { AppDialogs.error(error.localizedDescription) }
    }
}
