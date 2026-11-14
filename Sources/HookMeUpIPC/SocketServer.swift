import Darwin
import Foundation

/// Listens on a Unix socket in a 0700 directory; the socket itself is 0600. Every
/// accepted connection whose peer UID is not ours is closed before anyone sees it.
public final class SocketServer: @unchecked Sendable {
    private let path: URL
    private let expectedUID: uid_t
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "hook-me-up.socket-server")
    private var source: DispatchSourceRead?
    /// Identity of the socket file we created, so stop() never unlinks someone else's.
    private var socketID: (device: dev_t, inode: ino_t)?

    /// A server for the socket at `path` that accepts only peers running as this user.
    public convenience init(path: URL) {
        self.init(path: path, expectedUID: getuid())
    }

    init(path: URL, expectedUID: uid_t) {
        self.path = path
        self.expectedUID = expectedUID
    }

    deinit { stop() }

    /// Creates the socket and starts accepting; `onConnection` gets each UID-checked
    /// connection. Throws `SocketError.alreadyRunning` when another agent listens.
    public func start(onConnection: @escaping @Sendable (Connection) -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        guard source == nil else { return }

        let socketPath = path.path
        var address = try SocketAddress.make(socketPath)
        try SocketSecurity.prepareDirectory(path.deletingLastPathComponent())
        try removeStaleSocket(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system(call: "socket", code: errno) }
        var started = false
        defer { if !started { Darwin.close(fd) } }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)

        guard SocketAddress.bind(fd, &address) == 0 else {
            throw errno == EADDRINUSE ? SocketError.alreadyRunning : SocketError.system(call: "bind", code: errno)
        }
        // The directory is 0700, so nobody else can reach the socket before this chmod.
        var info = stat()
        guard chmod(socketPath, 0o600) == 0, lstat(socketPath, &info) == 0 else {
            let code = errno
            unlink(socketPath)
            throw SocketError.system(call: "chmod", code: code)
        }
        guard listen(fd, 64) == 0 else {
            let code = errno
            unlink(socketPath)
            throw SocketError.system(call: "listen", code: code)
        }
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        let expected = expectedUID
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { Self.acceptPending(fd, expectedUID: expected, onConnection) }
        source.setCancelHandler { Darwin.close(fd) }
        self.source = source
        socketID = (info.st_dev, info.st_ino)
        started = true
        source.resume()
    }

    /// Stops listening and removes the socket file if it is still the one we created.
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard let source else { return }
        source.cancel()
        self.source = nil
        var info = stat()
        if let socketID, lstat(path.path, &info) == 0,
            info.st_dev == socketID.device, info.st_ino == socketID.inode
        {
            unlink(path.path)
        }
        socketID = nil
    }

    private static func acceptPending(_ fd: Int32, expectedUID: uid_t, _ onConnection: @Sendable (Connection) -> Void) {
        while true {
            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return  // EAGAIN: nothing more pending
            }
            guard let uid = try? SocketSecurity.peerUID(fd: client), uid == expectedUID else {
                Darwin.close(client)
                continue
            }
            onConnection(Connection(fd: client))
        }
    }

    /// Removes a leftover socket from a crashed agent. Refuses anything that is not a
    /// socket owned by us, and never removes the socket of an agent that still answers.
    private func removeStaleSocket(_ socketPath: String) throws {
        var info = stat()
        guard lstat(socketPath, &info) == 0 else {
            if errno == ENOENT { return }
            throw SocketError.system(call: "lstat", code: errno)
        }
        guard info.st_mode & S_IFMT == S_IFSOCK else { throw SocketError.notASocket(socketPath) }
        guard info.st_uid == getuid() else { throw SocketError.wrongOwner(socketPath) }
        if let probe = try? SocketClient.rawConnect(path: socketPath, timeout: 0.2) {
            Darwin.close(probe)
            throw SocketError.alreadyRunning
        }
        guard unlink(socketPath) == 0 || errno == ENOENT else { throw SocketError.system(call: "unlink", code: errno) }
    }
}
