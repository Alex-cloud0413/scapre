import AppKit
import Foundation

/// Download is explicit, never triggered by HTML rendering or a clipboard change.
enum WebImageImporter {
    static func offer(_ url: URL) {
        guard url.scheme?.lowercased() == "https", let host = url.host else { AppDialogs.error("网络图片仅支持 HTTPS 地址。"); return }
        let alert = NSAlert(); alert.messageText = "下载并贴出这张网络图片？"; alert.informativeText = "将连接 \(host)，最多下载 25 MB。"
        alert.addButton(withTitle: "下载"); alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        BoundedImageDownload.fetch(url) { result in
            Task { @MainActor in
                do { let data = try result.get(); PinManager.shared.add(try ImageInputs.decode(data), originalData: data) }
                catch { AppDialogs.error("网络图片未导入：" + error.localizedDescription) }
            }
        }
    }
    static func pasteURL() {
        guard let text = NSPasteboard.general.string(forType: .URL) ?? NSPasteboard.general.string(forType: .string), let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { AppDialogs.error("剪贴板中没有图片网址。"); return }
        offer(url)
    }
}
nonisolated final class BoundedImageDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var bytes = Data()
    private var completion: (@Sendable (Result<Data, Error>) -> Void)?
    private var session: URLSession?
    private let limit = 25_000_000
    static func fetch(_ url: URL, completion: @escaping @Sendable (Result<Data, Error>) -> Void) {
        let delegate = BoundedImageDownload(); delegate.completion = completion
        let config = URLSessionConfiguration.ephemeral; config.httpShouldSetCookies = false; config.timeoutIntervalForRequest = 30; config.timeoutIntervalForResource = 60
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: queue); delegate.session = session
        session.dataTask(with: url).resume()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme?.lowercased() == "https" ? request : nil)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let okay = (response as? HTTPURLResponse).map { (200...299).contains($0.statusCode) } ?? false
        completionHandler(okay && response.expectedContentLength <= limit ? .allow : .cancel)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard bytes.count + data.count <= limit else { finish(.failure(ImageProtocolError.tooLarge)); return }; bytes.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) } else { finish(.success(bytes)) }
    }
    private func finish(_ result: Result<Data, Error>) {
        let callback = completion; completion = nil; callback?(result)
        session?.invalidateAndCancel(); session = nil; bytes.removeAll()
    }
}
