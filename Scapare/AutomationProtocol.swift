import Foundation
import Darwin

nonisolated struct AutomationRequest: Codable, Sendable {
    var command: String
    var image: Data?
    var region: [Double]?
    var delay: Double?
    var format: String?
    var rotation: Int?
    var flipHorizontal: Bool?
    var flipVertical: Bool?
    var grayscale: Bool?
    var inverted: Bool?
    var mosaic: [[Double]]?
    var blur: [[Double]]?
    var group: String?
    var cornerRadius: Double?
    var borderWidth: Double?
    var shadow: Bool?
}
nonisolated struct AutomationResponse: Codable, Sendable {
    var success: Bool
    var message: String = ""
    var image: Data?
}
nonisolated enum AutomationError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

/// Local Unix socket protocol, bounded length-prefixed messages, owned by the current user.
nonisolated enum AutomationWire {
    static let maxMessage = 140_000_000
    static func address(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw AutomationError.invalid("本机通信路径过长。") }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in destination.copyBytes(from: bytes) }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return address
    }
    static func connect(to path: String) throws -> Int32 {
        var address = try address(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AutomationError.invalid("无法创建本机连接。") }
        let result = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard result == 0 else { Darwin.close(fd); throw AutomationError.invalid("无法连接 Scapare。请先打开 App，并在更多设置中启用本机命令行。") }
        configure(fd); return fd
    }
    static func configure(_ fd: Int32) {
        var timeout = timeval(tv_sec: 120, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var noSignal: Int32 = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
    }
    static func send(_ data: Data, to fd: Int32) throws {
        guard data.count <= maxMessage else { throw ImageProtocolError.tooLarge }
        var size = UInt32(data.count).bigEndian
        let header = withUnsafeBytes(of: &size) { Data($0) }
        try write(header, to: fd); try write(data, to: fd)
    }
    static func receive(from fd: Int32) throws -> Data {
        let header = try read(count: 4, from: fd)
        let size = header.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard size <= maxMessage else { throw ImageProtocolError.tooLarge }
        return try read(count: Int(size), from: fd)
    }
    private static func write(_ data: Data, to fd: Int32) throws {
        try data.withUnsafeBytes { ptr in
            var sent = 0
            while sent < data.count {
                let n = Darwin.write(fd, ptr.baseAddress!.advanced(by: sent), data.count - sent)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw AutomationError.invalid("本机连接写入失败。") }; sent += n
            }
        }
    }
    private static func read(count: Int, from fd: Int32) throws -> Data {
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { ptr in
            var received = 0
            while received < count {
                let n = Darwin.read(fd, ptr.baseAddress!.advanced(by: received), count - received)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw AutomationError.invalid("本机连接已断开或超时。") }; received += n
            }
        }
        return data
    }
}
nonisolated enum ImageProtocolError: LocalizedError {
    case tooLarge
    var errorDescription: String? { "请求或返回图片超过本机自动化大小限制。" }
}

nonisolated final class LocalAutomationServer: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptor: Int32 = -1
    private var activeClient: Int32 = -1
    private let path: String
    private let handler: @Sendable (Data) async -> Data
    init(path: String, handler: @escaping @Sendable (Data) async -> Data) { self.path = path; self.handler = handler }
    func start() throws {
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory,
              (attributes[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              ((attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0) & 0o077 == 0 else { throw AutomationError.invalid("本机通信目录必须只允许当前用户访问。") }
        if FileManager.default.fileExists(atPath: path) {
            if let probe = try? AutomationWire.connect(to: path) { Darwin.close(probe); throw AutomationError.invalid("另一个 Scapare 实例正在提供命令行服务。") }
            let old = try FileManager.default.attributesOfItem(atPath: path)
            guard old[.type] as? FileAttributeType == .typeSocket, (old[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else { throw AutomationError.invalid("通信位置已有其他文件，未覆盖。") }
            try FileManager.default.removeItem(atPath: path)
        }
        var address = try AutomationWire.address(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AutomationError.invalid("无法创建本机服务。") }
        let result = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        guard result == 0, listen(fd, 4) == 0 else { Darwin.close(fd); throw AutomationError.invalid("无法启动本机服务。") }
        chmod(path, 0o600)
        lock.lock(); descriptor = fd; lock.unlock()
        DispatchQueue(label: "Scapare.Automation", qos: .utility).async { [weak self] in self?.acceptLoop(fd) }
    }
    private func acceptLoop(_ fd: Int32) {
        while true {
            lock.lock(); let running = descriptor == fd; lock.unlock(); guard running else { break }
            let client = accept(fd, nil, nil)
            guard client >= 0 else { break }
            lock.lock(); activeClient = client; lock.unlock()
            AutomationWire.configure(client)
            do {
                var uid: uid_t = 0, gid: gid_t = 0
                guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else { throw AutomationError.invalid("用户身份不匹配。") }
                let request = try AutomationWire.receive(from: client)
                let wait = DispatchSemaphore(value: 0)
                let result = LockedReply()
                Task { let data = await self.handler(request); result.set(data); wait.signal() }
                if wait.wait(timeout: .now() + 110) == .success, let response = result.get() { try AutomationWire.send(response, to: client) }
            } catch { /* A malformed/disconnected client must not affect the App. */ }
            lock.lock(); activeClient = -1; lock.unlock()
            Darwin.close(client)
        }
    }
    func stop() {
        lock.lock(); let fd = descriptor; descriptor = -1; let client = activeClient; if client >= 0 { shutdown(client, SHUT_RDWR) }; lock.unlock()
        if fd >= 0 { shutdown(fd, SHUT_RDWR); Darwin.close(fd); try? FileManager.default.removeItem(atPath: path) }
    }
    deinit { stop() }
    private final class LockedReply: @unchecked Sendable {
        private let lock = NSLock(); private var data: Data?
        func set(_ value: Data) { lock.lock(); data = value; lock.unlock() }
        func get() -> Data? { lock.lock(); defer { lock.unlock() }; return data }
    }
}
