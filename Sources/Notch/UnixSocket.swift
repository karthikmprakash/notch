import Foundation

/// Tiny line-delimited JSON server on a unix domain socket.
/// The Claude Code hook (this same binary, run with `--hook`) connects to it.
final class UnixConnection {
    let fd: Int32
    private var closed = false

    init(fd: Int32) { self.fd = fd }

    func reply(_ line: String) {
        guard !closed else { return }
        let payload = Array((line + "\n").utf8)
        var offset = 0
        while offset < payload.count {
            let written = payload.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return -1 }
                return Darwin.write(fd, base.advanced(by: offset), payload.count - offset)
            }
            if written <= 0 { break }
            offset += written
        }
        close()
    }

    func close() {
        guard !closed else { return }
        closed = true
        Darwin.close(fd)
    }
}

final class UnixSocketServer {
    /// Called on the main queue with each received line. Reply (possibly later)
    /// to answer the client; the connection stays open until it is closed.
    var handler: ((UnixConnection, String) -> Void)?

    private let path: String
    private var listenFD: Int32 = -1
    private var running = false
    private let queue = DispatchQueue(label: "dev.kmp.notch.socket", attributes: .concurrent)

    init(path: String) { self.path = path }

    func start() throws {
        stop()
        unlink(path)
        listenFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenFD >= 0 else { throw SocketError.open(errno) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            throw SocketError.pathTooLong
        }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: pathBytes)
        }

        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listenFD, $0, length) }
        }
        guard result == 0 else { throw SocketError.bind(errno) }
        guard listen(listenFD, 8) == 0 else { throw SocketError.listen(errno) }

        running = true
        queue.async { [weak self] in self?.acceptLoop() }
    }

    func stop() {
        running = false
        if listenFD >= 0 {
            Darwin.close(listenFD)
            listenFD = -1
        }
        unlink(path)
    }

    private func acceptLoop() {
        while running {
            let client = accept(listenFD, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                break
            }
            queue.async { [weak self] in self?.serve(client) }
        }
    }

    /// One connection: read until the first newline, then hand it to the app.
    private func serve(_ fd: Int32) {
        let connection = UnixConnection(fd: fd)
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 8192)
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        while !buffer.contains(0x0A) {
            let count = read(fd, &chunk, chunk.count)
            if count <= 0 { break }
            buffer.append(contentsOf: chunk[0..<count])
            if buffer.count > 128 * 1024 { break }
        }

        guard let text = String(data: buffer, encoding: .utf8),
              let line = text.split(separator: "\n").first.map(String.init),
              !line.isEmpty else {
            connection.close()
            return
        }

        DispatchQueue.main.async {
            guard let handler = self.handler else {
                connection.close()
                return
            }
            handler(connection, line)
        }
    }

    enum SocketError: Error {
        case open(Int32)
        case bind(Int32)
        case listen(Int32)
        case connect(Int32)
        case pathTooLong
    }

    /// Used by the hook CLI: send one line, optionally wait for one line back.
    static func send(_ line: String, to path: String, waitForReply: TimeInterval) -> String? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in raw.copyBytes(from: pathBytes) }

        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, length) }
        }
        guard result == 0 else { return nil }

        let payload = Array((line + "\n").utf8)
        var offset = 0
        while offset < payload.count {
            let written = payload.withUnsafeBytes { buffer -> Int in
                guard let base = buffer.baseAddress else { return -1 }
                return Darwin.write(fd, base.advanced(by: offset), payload.count - offset)
            }
            if written <= 0 { break }
            offset += written
        }

        guard waitForReply > 0 else { return nil }
        var timeout = timeval(tv_sec: Int(waitForReply), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var response = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while !response.contains(0x0A) {
            let count = read(fd, &chunk, chunk.count)
            if count <= 0 { break }
            response.append(contentsOf: chunk[0..<count])
        }
        return String(data: response, encoding: .utf8)?
            .split(separator: "\n").first.map(String.init)
    }
}
