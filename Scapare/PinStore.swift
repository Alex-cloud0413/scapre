import AppKit

struct PinRecord: Codable {
    var id = UUID()
    var title = "贴图"
    var group = "默认"
    var imageData: Data
    var snapshot: EditSnapshot?
    var sourceText: String?
    var sourceHTML: String?
    var frame: CGRect
    var opacity: Double = 1
    var quarterTurns = 0
    var flipHorizontal = false
    var flipVertical = false
    var grayscale = false
    var inverted = false
    var topmost = true
    var hidden = false
    var thumbnail = false
    var normalFrame: CGRect?
    var background = 0
}
struct PinArchive: Codable { var version = 1; var pins: [PinRecord] }

struct PinStore {
    let url: URL
    var backupURL: URL { url.deletingPathExtension().appendingPathExtension("previous.json") }
    private func readData(_ location: URL) throws -> Data {
        guard (try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 180_000_000 else { throw ImageError.tooLarge }
        return try Data(contentsOf: location, options: .mappedIfSafe)
    }
    func read() throws -> [PinRecord] {
        do { return try Self.decode(readData(url)) }
        catch {
            if FileManager.default.fileExists(atPath: backupURL.path) { return try Self.decode(readData(backupURL)) }
            throw error
        }
    }
    static func decode(_ data: Data) throws -> [PinRecord] {
        guard data.count <= 180_000_000 else { throw ImageError.tooLarge }
        let archive = try JSONDecoder().decode(PinArchive.self, from: data)
        guard archive.version == 1, archive.pins.count <= 100, Set(archive.pins.map(\.id)).count == archive.pins.count else { throw ImageError.incompatible }
        for pin in archive.pins {
            guard [pin.frame.minX, pin.frame.minY, pin.frame.width, pin.frame.height, pin.opacity].allSatisfy(\.isFinite),
                  pin.frame.width > 0, pin.frame.height > 0, pin.frame.width < 60_000, pin.frame.height < 60_000,
                  pin.title.count <= 200, pin.group.count <= 100, (-3...3).contains(pin.quarterTurns), (0...4).contains(pin.background),
                  (0.1...1).contains(pin.opacity), pin.imageData.count <= 100_000_000,
                  (pin.sourceText?.count ?? 0) <= 100_000, (pin.sourceHTML?.count ?? 0) <= 300_000,
                  (pin.snapshot?.annotations.count ?? 0) <= 2000, (pin.snapshot?.annotations.allSatisfy(\.isValid) ?? true) else { throw ImageError.incompatible }
            if let selection = pin.snapshot?.selection {
                guard !selection.isNull, [selection.minX, selection.minY, selection.width, selection.height].allSatisfy({ $0.isFinite && abs($0) < 100_000 }), selection.width > 0, selection.height > 0 else { throw ImageError.incompatible }
            }
            if let frame = pin.normalFrame {
                guard [frame.minX, frame.minY, frame.width, frame.height].allSatisfy({ $0.isFinite && abs($0) < 100_000 }), frame.width > 0, frame.height > 0 else { throw ImageError.incompatible }
            }
            _ = try ImageInputs.decode(pin.imageData)
        }
        return archive.pins
    }
    func write(_ pins: [PinRecord]) throws {
        let data = try JSONEncoder().encode(PinArchive(pins: pins))
        guard data.count <= 180_000_000 else { throw ImageError.tooLarge }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let previous = try? readData(url), (try? Self.decode(previous)) != nil { try previous.write(to: backupURL, options: .atomic) }
        try data.write(to: url, options: .atomic)
    }
}

nonisolated enum ImageTransform {
    static func apply(_ image: CGImage, quarterTurns: Int, flipHorizontal: Bool, flipVertical: Bool) throws -> CGImage {
        if quarterTurns % 4 == 0 && !flipHorizontal && !flipVertical { return image }
        let source = try PixelRaster(image)
        let turns = (quarterTurns % 4 + 4) % 4
        let w = turns % 2 == 0 ? source.width : source.height, h = turns % 2 == 0 ? source.height : source.width
        var output = [UInt8](repeating: 0, count: w * h * 4)
        for y in 0..<source.height {
            for x in 0..<source.width {
                let dx: Int, dy: Int
                switch turns {
                case 1: dx = source.height - 1 - y; dy = x
                case 2: dx = source.width - 1 - x; dy = source.height - 1 - y
                case 3: dx = y; dy = source.width - 1 - x
                default: dx = x; dy = y
                }
                let targetX = flipHorizontal ? w - 1 - dx : dx, targetY = flipVertical ? h - 1 - dy : dy
                let i = (y * source.width + x) * 4, j = (targetY * w + targetX) * 4
                output[j] = source.bytes[i]; output[j+1] = source.bytes[i+1]; output[j+2] = source.bytes[i+2]; output[j+3] = source.bytes[i+3]
            }
        }
        guard let result = PixelRaster(width: w, height: h, bytes: output).image() else { throw ImageError.decode }
        return result
    }
}
