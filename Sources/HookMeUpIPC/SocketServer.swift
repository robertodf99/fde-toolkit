import Darwin
import Foundation

/// What a check of the server's socket found, and what it did about it.
public enum SocketCheck: Equatable, Sendable {
    /// The socket at the path is still ours.
    case intact
    /// Ours was gone (removed, its folder removed, or a dead socket in its place): the
    /// folder is back to 0700 and the server listens on a new socket at the path.
    case rebound
    /// Another server answers at the path: this one stopped listening and removed nothing.
    case yielded
    /// Something at the path, or the folder, can't be used (not a socket, a symbolic link,
    /// another user's, a failing call); it was left as it is and is checked again later.
    case failed(SocketError)
    /// The server is not listening (never started, stopped, or yielded).
    case stopped
}

/// Listens on a Unix socket in a 0700 directory; the socket itself is 0600. Every
/// accepted connection whose peer UID is not ours is closed before anyone sees it.
///
/// While it runs, the server checks every few seconds that its socket is still at the
/// path (a cleanup tool or an old uninstaller may delete the folder) and listens again
/// when it was removed; see `SocketCheck`. The listener, the check and accepting run on
/// one private queue; state changes happen under a lock.
public final class SocketServer: @unchecked Sendable {
    /// How often a running server checks its socket, in seconds.
    public static let defaultCheckInterval: TimeInterval = 5

    private let path: URL
    private let expectedUID: uid_t
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "hook-me-up.socket-server")
    private var source: DispatchSourceRead?
    /// The listening descriptor `source` reads (closed by its cancel handler).
    private var listenerFD: Int32 = -1
    /// Identity of the socket file we created, so stop() never unlinks someone else's.
    private var socketID: (device: dev_t, inode: ino_t)?
    private var timer: DispatchSourceTimer?
    private var onConnection: (@Sendable (Connection) -> Void)?
    private var onCheck: (@Sendable (SocketCheck) -> Void)?
    /// Failures already reported since the socket was last fine: each one once.
    private var reportedFailures: Set<String> = []

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
    ///
    /// Every `checkInterval` seconds the socket is checked (`SocketCheck`); `onCheck` hears
    /// about each change, on the server's queue: `.rebound`, `.yielded`, and each kind of
    /// `.failed` once until the socket is back. Never `.intact`.
    public func start(
        checkInterval: TimeInterval = SocketServer.defaultCheckInterval,
        onCheck: @escaping @Sendable (SocketCheck) -> Void = { _ in },
        onConnection: @escaping @Sendable (Connection) -> Void
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard source == nil else { return }

        let socketPath = path.path
        _ = try SocketAddress.make(socketPath)  // a path that can't be a socket fails first
        try SocketSecurity.prepareDirectory(path.deletingLastPathComponent())
        try removeStaleSocket(socketPath)
        install(try makeListener(onConnection: onConnection))
        self.onConnection = onConnection
        self.onCheck = onCheck
        reportedFailures = []
        startTimer(interval: checkInterval)
    }

    /// Stops listening and checking, and removes the socket file if it is still the one we
    /// created (after a rebind, the new one; after yielding, none).
    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        timer?.cancel()
        timer = nil
        onConnection = nil
        onCheck = nil
        guard let source else { return }
        source.cancel()
        self.source = nil
        listenerFD = -1
        if isOurSocket() { unlink(path.path) }
        socketID = nil
    }

    // MARK: Checking the socket

    /// Checks that our socket is still at the path and repairs what it may (see
    /// `SocketCheck`): the folder is prepared as at start (created 0700, its mode fixed;
    /// symbolic links and other owners refused); a dead socket of ours is replaced; a live
    /// one is left to its server, and this one yields. Connections already accepted are
    /// not affected; ones the old listener had queued are handed over before it closes.
    func checkSocket() -> SocketCheck {
        lock.lock()
        let (result, queued, deliver) = checkLocked()
        lock.unlock()
        if let deliver { for connection in queued { deliver(connection) } }
        return result
    }

    private func checkLocked() -> (SocketCheck, [Connection], (@Sendable (Connection) -> Void)?) {
        guard source != nil, let onConnection else { return (.stopped, [], nil) }
        if isOurSocket() { return (.intact, [], nil) }
        do {
            try SocketSecurity.prepareDirectory(path.deletingLastPathComponent())
        } catch {
            return (.failed(Self.socketError(error, call: "mkdir")), [], nil)
        }
        // Only the folder's mode needed fixing: ours is still there.
        if isOurSocket() { return (.intact, [], nil) }
        for attempt in 1...2 {
            do {
                try removeStaleSocket(path.path)
            } catch SocketError.alreadyRunning {
                yieldLocked()
                return (.yielded, [], nil)
            } catch {
                return (.failed(Self.socketError(error, call: "unlink")), [], nil)
            }
            let listener: Listener
            do {
                listener = try makeListener(onConnection: onConnection)
            } catch SocketError.alreadyRunning where attempt == 1 {
                continue  // someone bound the path in between: look at it again
            } catch SocketError.alreadyRunning {
                return (.failed(.system(call: "bind", code: EADDRINUSE)), [], nil)
            } catch {
                return (.failed(Self.socketError(error, call: "bind")), [], nil)
            }
            var queued: [Connection] = []
            Self.acceptPending(listenerFD, expectedUID: expectedUID) { queued.append($0) }
            source?.cancel()  // closes the old descriptor
            install(listener)
            return (.rebound, queued, onConnection)
        }
        return (.failed(.system(call: "bind", code: EADDRINUSE)), [], nil)
    }

    /// The periodic check: reports what changed to `onCheck`, outside the lock.
    private func periodicCheck() {
        let result = checkSocket()
        let report: (@Sendable (SocketCheck) -> Void)? = lock.withLock {
            switch result {
            case .intact, .stopped:
                return nil
            case .rebound:
                reportedFailures = []
                return onCheck
            case .yielded:
                return onCheck
            case .failed(let error):
                return reportedFailures.insert(error.description).inserted ? onCheck : nil
            }
        }
        report?(result)
    }

    private func startTimer(interval: TimeInterval) {
        let nanoseconds = max(1, Int((interval * 1_000_000_000).rounded()))
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + .nanoseconds(nanoseconds), repeating: .nanoseconds(nanoseconds),
            leeway: .nanoseconds(max(1, nanoseconds / 10)))
        timer.setEventHandler { [weak self] in self?.periodicCheck() }
        self.timer = timer
        timer.resume()
    }

    /// Stops listening without touching the path: it belongs to the server that answers there.
    private func yieldLocked() {
        timer?.cancel()
        timer = nil
        source?.cancel()
        source = nil
        listenerFD = -1
        socketID = nil
    }

    /// Whether the file at the path is the socket we created.
    private func isOurSocket() -> Bool {
        var info = stat()
        guard let socketID, lstat(path.path, &info) == 0 else { return false }
        return info.st_dev == socketID.device && info.st_ino == socketID.inode
    }

    // MARK: Listening

    private struct Listener {
        let fd: Int32
        let source: DispatchSourceRead
        let id: (device: dev_t, inode: ino_t)
    }

    /// Binds a new socket at the path (0600), listens, and makes a read source that
    /// accepts on the queue (not resumed yet). Throws `.alreadyRunning` when the path is
    /// taken (EADDRINUSE).
    private func makeListener(onConnection: @escaping @Sendable (Connection) -> Void) throws -> Listener {
        let socketPath = path.path
        var address = try SocketAddress.make(socketPath)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system(call: "socket", code: errno) }
        var made = false
        defer { if !made { Darwin.close(fd) } }
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
        made = true
        return Listener(fd: fd, source: source, id: (info.st_dev, info.st_ino))
    }

    /// Makes `listener` the one the server reads, and starts reading it.
    private func install(_ listener: Listener) {
        source = listener.source
        listenerFD = listener.fd
        socketID = listener.id
        listener.source.resume()
    }

    private static func acceptPending(_ fd: Int32, expectedUID: uid_t, _ deliver: (Connection) -> Void) {
        guard fd >= 0 else { return }
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
            deliver(Connection(fd: client))
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

    /// `error` as a `SocketError` (a Foundation error becomes the failing call and its errno).
    private static func socketError(_ error: Error, call: String) -> SocketError {
        if let error = error as? SocketError { return error }
        let error = error as NSError
        if error.domain == NSPOSIXErrorDomain { return .system(call: call, code: Int32(error.code)) }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSPOSIXErrorDomain {
            return .system(call: call, code: Int32(underlying.code))
        }
        return .system(call: call, code: EIO)
    }
}
