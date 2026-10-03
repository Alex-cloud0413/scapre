import Vision
import AppKit

enum OCRService {
    nonisolated static func recognize(pngData: Data) async throws -> String {
        let worker = Task.detached(priority: .userInitiated) { () throws -> String in
            try Task.checkCancellation()
            guard let rep = NSBitmapImageRep(data: pngData), let image = rep.cgImage else {
                throw NSError(domain: "Scapare.OCR", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "无法读取图片，请重新截图。"])
            }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
            try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
            try Task.checkCancellation()
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }
}
