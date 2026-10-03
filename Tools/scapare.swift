import Foundation
import Darwin

@main
struct ScapareCLI {
    static let help = """
    Scapare — local screenshot and image tools
    Enable 更多设置 → 高级功能 → 本机命令行 in the running App first.

    scapare status | list | paste
    scapare capture --output shot.png [--region x,y,w,h] [--delay 0...60]
    scapare ocr|barcode image.png [more images...]
    scapare pin image.png [more images...] [--group name]
    scapare show|hide [--group name]
    scapare process image.png [more images...] --output-dir folder [options]
    scapare process image.png --output result.png [options]
    scapare export --output pins.json [--group name]
    scapare import pins.json

    Image options: --region x,y,w,h --rotate 90|180|270 --flip-horizontal
      --flip-vertical --grayscale --invert --mosaic x,y,w,h --blur x,y,w,h
      --round radius --border width --shadow --format png|jpg|tiff|bmp|gif
    Region/masks: original image pixels, top-left origin; masks before crop/rotate.
    Repeat --mosaic/--blur for several regions. Capture uses the primary display.
    --socket path overrides the local socket location. --overwrite permits replacing
    existing output files. Batch processing continues after errors and exits nonzero.
    Editable pin backups include ORIGINAL images, including regions masked in edits.
    No files are read/written by the App on behalf of the CLI; bytes cross the socket.
    """
    static func main() {
        do { try run(Array(CommandLine.arguments.dropFirst())) }
        catch { fputs("scapare: \(error.localizedDescription)\n", stderr); exit(1) }
    }
    static func run(_ args: [String]) throws {
        guard let command = args.first, command != "--help", command != "help" else { print(help); return }
        let valid = ["status", "list", "paste", "capture", "ocr", "barcode", "pin", "show", "hide", "process", "export", "import"]
        guard valid.contains(command) else { throw AutomationError.invalid("Unknown command. Run scapare --help.") }
        var request = AutomationRequest(command: command)
        var inputs: [String] = [], output: String?, outputDirectory: String?, socketPath: String?, overwrite = false
        var index = 1
        func value() throws -> String {
            index += 1; guard index < args.count else { throw AutomationError.invalid("Missing option value.") }; return args[index]
        }
        func number() throws -> Double { let text = try value(); guard let n = Double(text), n.isFinite else { throw AutomationError.invalid("Invalid number: \(text)") }; return n }
        func rectangle() throws -> [Double] {
            let pieces = try value().split(separator: ",", omittingEmptySubsequences: false)
            let values = pieces.compactMap { Double($0) }
            guard pieces.count == 4, values.count == 4, values.allSatisfy(\.isFinite) else { throw AutomationError.invalid("Expected x,y,width,height.") }; return values
        }
        while index < args.count {
            let arg = args[index]
            switch arg {
            case "--output", "-o": output = try value()
            case "--output-dir": outputDirectory = try value()
            case "--socket": socketPath = try value()
            case "--overwrite": overwrite = true
            case "--format": request.format = try value().lowercased()
            case "--group": request.group = try value()
            case "--region": request.region = try rectangle()
            case "--delay": request.delay = try number()
            case "--rotate": let v = try value(); guard let n = Int(v) else { throw AutomationError.invalid("Invalid rotation.") }; request.rotation = n
            case "--round": request.cornerRadius = try number()
            case "--border": request.borderWidth = try number()
            case "--flip-horizontal": request.flipHorizontal = true
            case "--flip-vertical": request.flipVertical = true
            case "--grayscale": request.grayscale = true
            case "--invert": request.inverted = true
            case "--shadow": request.shadow = true
            case "--mosaic": request.mosaic = (request.mosaic ?? []) + [try rectangle()]
            case "--blur": request.blur = (request.blur ?? []) + [try rectangle()]
            case "--": inputs.append(contentsOf: args.dropFirst(index + 1)); index = args.count; continue
            default:
                guard !arg.hasPrefix("-") else { throw AutomationError.invalid("Unknown option: \(arg)") }; inputs.append(arg)
            }
            index += 1
        }
        let needsInput = ["ocr", "barcode", "pin", "process", "import"].contains(command)
        guard needsInput == !inputs.isEmpty else { throw AutomationError.invalid(needsInput ? "Provide an input file." : "This command does not accept input files.") }
        if command == "import" && inputs.count != 1 { throw AutomationError.invalid("Import one backup at a time.") }
        let writes = ["capture", "process", "export"].contains(command)
        guard !writes || (output != nil) != (outputDirectory != nil) else { throw AutomationError.invalid("Choose --output or --output-dir.") }
        guard output == nil || inputs.count <= 1 else { throw AutomationError.invalid("Use --output-dir for multiple inputs.") }
        guard writes || (output == nil && outputDirectory == nil) else { throw AutomationError.invalid("This command prints text or changes pins; it does not write output images.") }
        if let ext = request.format, !["png", "jpg", "jpeg", "tiff", "tif", "bmp", "gif"].contains(ext) { throw AutomationError.invalid("Unsupported format.") }
        // Resolve every output and reject collisions before starting a batch.
        let jobs: [String?] = inputs.isEmpty ? [nil] : inputs.map(Optional.some)
        var outputs: [URL?] = []
        for input in jobs {
            if let output { outputs.append(URL(fileURLWithPath: output)) }
            else if let directory = outputDirectory {
                let stem = input.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? (command == "export" ? "Scapare-pins" : "Scapare-capture")
                outputs.append(URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(stem + "." + (command == "export" ? "json" : request.format ?? "png")))
            } else { outputs.append(nil) }
        }
        if command != "export", let format = request.format {
            func canonical(_ ext: String) -> String { ["jpeg": "jpg", "tif": "tiff"][ext.lowercased()] ?? ext.lowercased() }
            guard outputs.compactMap({ $0 }).allSatisfy({ canonical($0.pathExtension) == canonical(format) }) else { throw AutomationError.invalid("Output extension must match --format.") }
        }
        let destinations = outputs.compactMap { $0?.standardizedFileURL.path }
        guard Set(destinations).count == destinations.count else { throw AutomationError.invalid("Input names would produce duplicate output paths. Use separate output folders.") }
        for url in outputs.compactMap({ $0 }) where !overwrite && FileManager.default.fileExists(atPath: url.path) { throw AutomationError.invalid("Output exists: \(url.path). Use --overwrite explicitly.") }
        let realHome = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = socketPath.map { [$0] } ?? [realHome + "/Library/Containers/com.gaoyiming.SnapTool/Data/.scapare-ipc/socket", realHome + "/.scapare-ipc/socket"]
        guard let endpoint = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else { throw AutomationError.invalid("Open Scapare and enable local command-line access in advanced settings.") }
        var failures = 0
        for (jobIndex, input) in jobs.enumerated() {
            do {
                var job = request
                if let input {
                    let url = URL(fileURLWithPath: input), size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                    guard size <= 100_000_000 else { throw ImageProtocolError.tooLarge }
                    job.image = try Data(contentsOf: url, options: .mappedIfSafe)
                }
                if let url = outputs[jobIndex], command != "export" { job.format = job.format ?? url.pathExtension }
                let fd = try AutomationWire.connect(to: endpoint); defer { Darwin.close(fd) }
                try AutomationWire.send(JSONEncoder().encode(job), to: fd)
                let response = try JSONDecoder().decode(AutomationResponse.self, from: AutomationWire.receive(from: fd))
                guard response.success else { throw AutomationError.invalid(response.message) }
                if let url = outputs[jobIndex] {
                    guard let data = response.image else { throw AutomationError.invalid("No output data returned.") }
                    // withoutOverwriting is atomic with respect to a concurrent creator.
                    let options: Data.WritingOptions = overwrite ? [.atomic] : [.withoutOverwriting]
                    try data.write(to: url, options: options); print(url.path)
                } else {
                    if jobs.count > 1, let input { print("\(input):") }; print(response.message)
                }
            } catch { failures += 1; fputs("\(input ?? command): \(error.localizedDescription)\n", stderr) }
        }
        if failures > 0 { throw AutomationError.invalid("\(failures) operation(s) failed.") }
    }
}
