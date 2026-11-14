import Darwin
import Foundation

/// The hook's side of the socket.
public enum SocketClient {
    /// Connects within `timeout` and verifies that the server runs as our own UID.
    /// A missing socket or one nobody listens on fails immediately.
    public static func connect(path: URL, timeout: TimeInterval) throws -> Connection {
        try connect(path: path, timeout: timeout, expectedUID: getuid())
    }

    static func connect(path: URL, timeout: TimeInterval, expectedUID: uid_t) throws -> Connection {
        let fd = try rawConnect(path: path.path, timeout: timeout)
        let uid: uid_t
        do {
            uid = try SocketSecurity.peerUID(fd: fd)
        } catch {
            Darwin.close(fd)
            throw error
        }
        guard uid == expectedUID else {
            Darwin.close(fd)
            throw SocketError.peerUIDMismatch(expected: expectedUID, actual: uid)
        }
        return Connection(fd: fd)
    }

    /// A connected descriptor (blocking mode), or an error. No UID check.
    static func rawConnect(path: String, timeout: TimeInterval) throws -> Int32 {
        var address = try SocketAddress.make(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw SocketError.system(call: "socket", code: errno) }
        var connected = false
        defer { if !connected { Darwin.close(fd) } }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if SocketAddress.connect(fd, &address) == 0 { break }
            let code = errno
            if code == EISCONN { break }
            if code == EINTR { continue }
            if code == EAGAIN {
                // Listen queue full: retry until the deadline.
                guard deadline.timeIntervalSinceNow > 0 else { throw SocketError.timedOut }
                usleep(10_000)
                continue
            }
            guard code == EINPROGRESS || code == EALREADY else {
                throw SocketError.system(call: "connect", code: code)
            }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw SocketError.timedOut }
            var descriptor = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            let ready = poll(&descriptor, 1, Int32((remaining * 1000).rounded(.up)))
            if ready < 0, errno == EINTR { continue }
            if ready == 0 { throw SocketError.timedOut }
            if ready < 0 { throw SocketError.system(call: "poll", code: errno) }
            var socketError: Int32 = 0
            var length = socklen_t(MemoryLayout<Int32>.size)
            _ = getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &length)
            guard socketError == 0 else { throw SocketError.system(call: "connect", code: socketError) }
            break
        }
        _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)
        connected = true
        return fd
    }
}
