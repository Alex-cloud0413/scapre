//
//  OCRService.swift
//  Scapare
//
//  文字识别(OCR)。用苹果自带的 Vision 框架，离线识别，支持中英文。
//

import Vision
import AppKit

enum OCRService {
    // 传入 PNG 数据(可跨线程安全传递)，返回识别出的文字。
    nonisolated static func recognize(pngData: Data) async -> String {
        await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            guard let rep = NSBitmapImageRep(data: pngData),
                  let cgImage = rep.cgImage else {
                continuation.resume(returning: "")
                return
            }

            let request = VNRecognizeTextRequest { request, _ in
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: "")
            }
        }
    }
}
