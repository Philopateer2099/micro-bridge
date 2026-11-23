import Foundation

public struct SocketError: Error, CustomStringConvertible {
    public let description: String

    static func errno(_ what: String) -> SocketError {
        SocketError(description: "\(what): \(String(cString: strerror(Foundation.errno)))")
    }
}

private func address(_ path: String) throws(SocketError) -> sockaddr_un {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    let capacity = MemoryLayout.size(ofValue: addr.sun_path)
    guard bytes.count < capacity else { throw SocketError(description: "socket path too long: \(path)") }
    withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
    return addr
}

private func withSockaddr<R>(_ addr: sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> R) -> R {
    var addr = addr
    return withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
}

/// A line-based Unix socket server on the main queue. The socket lives in a directory only
/// this user can enter, and is itself mode 0600.
@MainActor
public final class SocketServer {
    @MainActor
    public final class Client {
        fileprivate let fd: Int32
        fileprivate var source: DispatchSourceRead?
        fileprivate var buffer: [UInt8] = []
        public var subscribed = false
        public private(set) var isOpen = true

        fileprivate init(fd: Int32) { self.fd = fd }

        /// Sends one line. A client that cannot take it right now is dropped, so a stuck
        /// reader never stalls the daemon.
        public func send(_ line: String) {
            guard isOpen else { return }
            let bytes = Array((line + "\n").utf8)
            let sent = bytes.withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, MSG_DONTWAIT) }
            if sent != bytes.count { close() }
        }

        public func close() {
            guard isOpen else { return }
            isOpen = false
            source?.cancel() // the cancel handler closes the fd
            source = nil
        }
    }

    /// Longest accepted request line.
    static let maxLine = 4096

    public var onLine: ((Client, String) -> Void)?
    public private(set) var clients: [Client] = []

    private let listener: Int32
    private var acceptSource: DispatchSourceRead?
    private var lock: Int32 = -1

    /// Binds `directory/daemon.sock`. Fails if another daemon holds the lock.
    public init(directory: String, socket path: String) throws(SocketError) {
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            throw SocketError(description: "cannot create \(directory): \(error.localizedDescription)")
        }
        guard chmod(directory, 0o700) == 0 else { throw .errno("chmod \(directory)") }

        lock = open(directory + "/daemon.lock", O_CREAT | O_RDWR, 0o600)
        guard lock >= 0 else { throw .errno("open lock") }
        guard flock(lock, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(lock)
            throw SocketError(description: "another micro daemon is already running")
        }

        unlink(path)
        listener = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw .errno("socket") }
        let addr = try address(path)
        // Not umask: it is the whole process's, and a folder another thread makes meanwhile would
        // come out 0600, which nothing can be written into. The folder is already 0700.
        guard withSockaddr(addr, { bind(listener, $0, $1) }) == 0 else { throw .errno("bind \(path)") }
        guard chmod(path, 0o600) == 0 else { throw .errno("chmod \(path)") }
        guard listen(listener, 16) == 0 else { throw .errno("listen") }
        _ = fcntl(listener, F_SETFL, O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.acceptClients() }
        }
        source.resume()
        acceptSource = source
    }

    public func broadcast(_ line: String) {
        for client in clients where client.subscribed { client.send(line) }
        clients.removeAll { !$0.isOpen }
    }

    private func acceptClients() {
        while true {
            let fd = accept(listener, nil, nil)
            guard fd >= 0 else { return }
            var on: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
            let client = Client(fd: fd)
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
            source.setEventHandler { [weak self, weak client] in
                MainActor.assumeIsolated {
                    guard let self, let client else { return }
                    self.read(client)
                }
            }
            source.setCancelHandler { Darwin.close(fd) }
            client.source = source
            clients.append(client)
            source.resume()
        }
    }

    private func read(_ client: Client) {
        var chunk = [UInt8](repeating: 0, count: 4096)
        let count = chunk.withUnsafeMutableBytes { recv(client.fd, $0.baseAddress, $0.count, MSG_DONTWAIT) }
        if count == 0 || (count < 0 && errno != EAGAIN && errno != EINTR) {
            client.close()
            clients.removeAll { $0 === client }
            return
        }
        guard count > 0 else { return }
        client.buffer.append(contentsOf: chunk[..<count])
        while client.isOpen, let newline = client.buffer.firstIndex(of: 0x0A) {
            let line = String(decoding: client.buffer[..<newline], as: UTF8.self).trimmingWhitespace()
            client.buffer.removeSubrange(...newline)
            if !line.isEmpty { onLine?(client, line) }
        }
        if client.buffer.count > Self.maxLine {
            client.send(Reply.error("line too long"))
            client.close()
        }
        clients.removeAll { !$0.isOpen }
    }
}

/// A blocking client for the daemon's socket.
public enum SocketClient {
    /// Sends one line and hands each reply line to `onLine` until it returns false or the
    /// daemon closes the connection.
    /// `timeout` bounds each read and write, for callers that must never hang.
    public static func send(_ line: String, to path: String = BridgePaths.socket, timeout: TimeInterval? = nil,
                            onLine: (String) -> Bool) throws(SocketError) {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw .errno("socket") }
        defer { close(fd) }
        if let timeout {
            var limit = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - Double(Int(timeout))) * 1_000_000))
            let size = socklen_t(MemoryLayout<timeval>.size)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &limit, size)
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &limit, size)
        }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        let addr = try address(path)
        guard withSockaddr(addr, { connect(fd, $0, $1) }) == 0 else {
            throw SocketError(description: "micro daemon is not running (no socket at \(path))")
        }
        let bytes = Array((line + "\n").utf8)
        guard bytes.withUnsafeBytes({ write(fd, $0.baseAddress, $0.count) }) == bytes.count else {
            throw .errno("write")
        }
        var buffer: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            guard count > 0 else { return }
            buffer.append(contentsOf: chunk[..<count])
            while let newline = buffer.firstIndex(of: 0x0A) {
                let reply = String(decoding: buffer[..<newline], as: UTF8.self)
                buffer.removeSubrange(...newline)
                if !onLine(reply) { return }
            }
        }
    }
}
