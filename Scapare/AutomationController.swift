import AppKit

/// Files stay with the CLI. The sandbox receives image bytes and returns bytes only.
final class AutomationController {
    static let shared = AutomationController()
    private var server: LocalAutomationServer?
    private(set) var error: String?
    var enabled: Bool { UserDefaults.standard.bool(forKey: "automation_enabled") }
    var socketPath: String { NSHomeDirectory() + "/.scapare-ipc/socket" }
    func restore() { if enabled { do { try start() } catch { self.error = error.localizedDescription } } }
    func setEnabled(_ enabled: Bool) throws {
        if enabled { try start() } else { server?.stop(); server = nil }
        UserDefaults.standard.set(enabled, forKey: "automation_enabled"); error = nil
    }
    private func start() throws {
        guard server == nil else { return }
        let candidate = LocalAutomationServer(path: socketPath) { data in
            let response: AutomationResponse
            do {
                let request = try JSONDecoder().decode(AutomationRequest.self, from: data)
                response = try await AutomationController.shared.execute(request)
            } catch { response = AutomationResponse(success: false, message: error.localizedDescription) }
            if let data = try? JSONEncoder().encode(response), data.count <= AutomationWire.maxMessage { return data }
            return (try? JSONEncoder().encode(AutomationResponse(success: false, message: ImageProtocolError.tooLarge.localizedDescription))) ?? Data()
        }
        try candidate.start(); server = candidate
    }
    func stop() { server?.stop(); server = nil }
    private func execute(_ request: AutomationRequest) async throws -> AutomationResponse {
        guard enabled else { throw AutomationError.invalid("本机命令行已关闭。") }
        switch request.command {
        case "status": return AutomationResponse(success: true, message: "Scapare ready · \(PinManager.shared.controllers.count) pins")
        case "process":
            guard let data = request.image else { throw ImageError.decode }
            return AutomationResponse(success: true, image: try AutomationImages.process(data, request: request))
        case "ocr", "barcode":
            guard let data = request.image else { throw ImageError.decode }; _ = try ImageInputs.decode(data)
            let text = request.command == "ocr" ? try await OCRService.recognize(pngData: data) : try await OCRService.barcodes(pngData: data)
            return AutomationResponse(success: true, message: text)
        case "capture":
            let delay = request.delay ?? 0
            guard delay.isFinite, (0...60).contains(delay) else { throw AutomationError.invalid("延时范围为 0–60 秒。") }
            if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
            guard enabled else { throw AutomationError.invalid("本机命令行已关闭。") }
            let shots = try await ScreenshotEngine.captureAllDisplays()
            guard let shot = shots.first(where: { $0.screen.displayID == CGMainDisplayID() }) ?? shots.first else { throw ScreenshotError.noDisplays }
            let image = NSImage(cgImage: shot.image, size: CGSize(width: shot.image.width, height: shot.image.height))
            return AutomationResponse(success: true, image: try AutomationImages.process(ImageFileSaver.encoded(image, extension: "png"), request: request))
        case "pin", "paste":
            guard PinManager.shared.controllers.count < 100 else { throw ImageError.tooLarge }
            let image = try request.command == "paste" ? ImageInputs.clipboard() : ImageInputs.decode(request.image ?? Data())
            guard PinManager.shared.add(image, originalData: request.image) else { throw AutomationError.invalid("贴图未创建。") }
            if let group = request.group { PinManager.shared.controllers.last?.setGroup(String(group.prefix(100))) }
            return AutomationResponse(success: true, message: "已贴出")
        case "show", "hide":
            for controller in PinManager.shared.controllers where request.group == nil || controller.record.group == request.group {
                controller.setHidden(request.command == "hide")
            }
            PinManager.shared.changed(); return AutomationResponse(success: true)
        case "list":
            let items = PinManager.shared.controllers.map { ["id": $0.record.id.uuidString, "title": $0.record.title, "group": $0.record.group, "hidden": String($0.record.hidden)] }
            let data = try JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted, .sortedKeys])
            return AutomationResponse(success: true, message: String(decoding: data, as: UTF8.self))
        case "export": return AutomationResponse(success: true, image: try PinManager.shared.archiveData(group: request.group))
        case "import":
            try PinManager.shared.importData(request.image ?? Data()); return AutomationResponse(success: true, message: "已导入贴图")
        default: throw AutomationError.invalid("未知命令。请运行 scapare --help。")
        }
    }
}

enum AutomationImages {
    /// All coordinates use source pixels with a top-left origin, before crop/rotation.
    static func process(_ data: Data, request: AutomationRequest) throws -> Data {
        let input = try ImageInputs.decode(data)
        guard var image = input.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw ImageError.decode }
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let extent = CGRect(x: 0, y: 0, width: width, height: height)
        var annotations: [Annotation] = []
        for (tool, regions) in [(AnnotationTool.mosaic, request.mosaic ?? []), (.blur, request.blur ?? [])] {
            guard regions.count <= 100 else { throw ImageError.tooLarge }
            for values in regions {
                let rect = try pixelRect(values, extent: extent)
                var annotation = Annotation(tool: tool, color: .black, lineWidth: 4)
                annotation.start = CGPoint(x: rect.minX, y: height - rect.maxY)
                annotation.end = CGPoint(x: rect.maxX, y: height - rect.minY)
                annotations.append(annotation)
            }
        }
        if !annotations.isEmpty {
            guard let result = ScreenshotRenderer.render(image: image, selection: extent, viewSize: extent.size, annotations: annotations) else { throw ImageError.decode }
            image = result
        }
        if let values = request.region {
            guard let crop = image.cropping(to: try pixelRect(values, extent: extent)) else { throw ImageError.decode }; image = crop
        }
        let degrees = request.rotation ?? 0
        guard degrees % 90 == 0, (-360...360).contains(degrees) else { throw AutomationError.invalid("旋转角度需为 −360 到 360 之间的 90 度倍数。") }
        image = try ImageTransform.apply(image, quarterTurns: degrees / 90, flipHorizontal: request.flipHorizontal ?? false, flipVertical: request.flipVertical ?? false)
        guard let colored = ImageEffects.colorTransform(image, grayscale: request.grayscale ?? false, inverted: request.inverted ?? false) else { throw ImageError.decode }
        let radius = request.cornerRadius ?? 0, border = request.borderWidth ?? 0
        guard radius.isFinite, border.isFinite, (0...2000).contains(radius), (0...100).contains(border) else { throw AutomationError.invalid("圆角或边框数值无效。") }
        guard let decorated = ImageDecoration(cornerRadius: radius, borderWidth: border, shadow: request.shadow ?? false).apply(colored) else { throw ImageError.tooLarge }
        return try ImageFileSaver.encoded(NSImage(cgImage: decorated, size: CGSize(width: decorated.width, height: decorated.height)), extension: request.format ?? "png")
    }
    static func pixelRect(_ values: [Double], extent: CGRect) throws -> CGRect {
        guard values.count == 4, values.allSatisfy({ $0.isFinite && abs($0) <= 60_000 }), values[2] >= 1, values[3] >= 1 else { throw AutomationError.invalid("区域格式为 x,y,width,height，宽高至少为 1。") }
        let rect = CGRect(x: values[0], y: values[1], width: values[2], height: values[3]).integral
        guard extent.contains(rect) else { throw AutomationError.invalid("区域超出原图范围。") }; return rect
    }
}
