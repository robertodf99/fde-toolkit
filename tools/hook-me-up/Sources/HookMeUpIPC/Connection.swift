import Darwin
import Foundation
import HookMeUpCore

/// One connected, UID-checked Unix socket carrying framed `WireMessage`s.
///
/// Use either `receive(timeout:)` (blocking, one caller thread: the hook) or
/// `startReading(queue:onMessage:)` (asynchronous: the agent), not both. While reading
/// asynchronously the connection keeps itself alive until the peer closes or `close()`
/// is called.
public final class Connection: @unchecked Sendable {
    /// A peer that stops reading cannot block a sender for longer than this.
    static let sendTimeoutSeconds = 5

    private let lock = NSLock()
    private let fd: Int32
    private var isClosed = false
    private var closeHandler: (() -> Void)?
    private var readSource: DispatchSourceRead?
    /// Bytes not yet decoded; used by `receive` (sync) or by the read source (async).
    private var pending = Data()

    init(fd: Int32) {
        self.fd = fd
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        // Accepted sockets inherit O_NONBLOCK from the listener on Darwin: use blocking I/O.
        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) }
        var one: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        var timeout = timeval(tv_sec: Self.sendTimeoutSeconds, tv_usec: 0)
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    deinit {
        if !isClosed { Darwin.close(fd) }
    }

    /// Called once when the peer closes the connection (or it fails) while reading
    /// asynchronously. Not called for a local `close()`.
    public var onClose: (() -> Void)? {
        get { lock.withLock { closeHandler } }
        set { lock.withLock { closeHandler = newValue } }
    }

    /// Sends one framed message; blocks at most `sendTimeoutSeconds`.
    public func send(_ message: WireMessage) throws {
        let frame = try Framing.encode(message)
        // The lock is held for the whole write, so the descriptor cannot be closed (and
        // its number reused) underneath it.
        try lock.withLock {
            guard !isClosed else { throw SocketError.closed }
            try frame.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                guard let base = raw.baseAddress else { return }
                var offset = 0
                while offset < raw.count {
                    let written = Darwin.write(fd, base + offset, raw.count - offset)
                    if written > 0 {
                        offset += written
                        continue
                    }
                    let code = errno
                    if written < 0, code == EINTR { continue }
                    if code == EAGAIN || code == EWOULDBLOCK { throw SocketError.timedOut }
                    if code == EPIPE || code == ECONNRESET || code == ENOTCONN { throw SocketError.closed }
                    throw SocketError.system(call: "write", code: code)
                }
            }
        }
    }

    /// Waits for the next message. Returns nil when the peer closed the connection
    /// cleanly; throws `.timedOut` after `timeout` seconds (nil waits forever) and an
    /// error for a garbage frame or a connection cut mid-frame.
    public func receive(timeout: TimeInterval?) throws -> WireMessage? {
        let deadline = timeout.map { Date().addingTimeInterval($0) }
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            if let message = try Framing.decode(&pending) { return message }
            try lock.withLock { if isClosed { throw SocketError.closed } }

            var waitMilliseconds: Int32 = -1
            if let deadline {
                let remaining = deadline.timeIntervalSinceNow
                guard remaining > 0 else { throw SocketError.timedOut }
                waitMilliseconds = Int32(min((remaining * 1000).rounded(.up), Double(Int32.max)))
            }
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, waitMilliseconds)
            if ready < 0 {
                if errno == EINTR { continue }
                throw SocketError.system(call: "poll", code: errno)
            }
            if ready == 0 { throw SocketError.timedOut }

            let count = recv(fd, &chunk, chunk.count, 0)
            if count > 0 {
                pending.append(contentsOf: chunk[0..<count])
                continue
            }
            if count < 0, errno == EINTR || errno == EAGAIN { continue }
            if count == 0 || errno == ECONNRESET {
                if pending.isEmpty { return nil }
                throw SocketError.closed  // cut in the middle of a frame
            }
            throw SocketError.system(call: "recv", code: errno)
        }
    }

    /// Reads asynchronously on `queue`: each complete message goes to `onMessage`; at
    /// EOF, on a read error or a garbage frame the connection closes and `onClose` runs.
    public func startReading(queue: DispatchQueue, onMessage: @escaping @Sendable (WireMessage) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !isClosed, readSource == nil else { return }
        let fd = self.fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        // Strong capture on purpose: the connection lives while it is being read.
        // finish() cancels the source, which releases this handler and the cycle.
        source.setEventHandler { [self] in
            var chunk = [UInt8](repeating: 0, count: 64 * 1024)
            let count = recv(fd, &chunk, chunk.count, MSG_DONTWAIT)
            if count > 0 {
                pending.append(contentsOf: chunk[0..<count])
                do {
                    while let message = try Framing.decode(&pending) { onMessage(message) }
                } catch {
                    finish(notify: true)
                }
                return
            }
            if count < 0, errno == EAGAIN || errno == EINTR { return }
            finish(notify: true)
        }
        source.setCancelHandler { Darwin.close(fd) }
        readSource = source
        source.resume()
    }

    /// Shuts the socket down without closing the descriptor: a `receive` blocked in
    /// another thread returns nil at once, and the peer sees the connection end.
    public func interrupt() {
        lock.withLock {
            if !isClosed { _ = Darwin.shutdown(fd, SHUT_RDWR) }
        }
    }

    /// Closes the connection (idempotent). Does not call `onClose`.
    public func close() {
        finish(notify: false)
    }

    private func finish(notify: Bool) {
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            return
        }
        isClosed = true
        let handler = notify ? closeHandler : nil
        closeHandler = nil
        if let source = readSource {
            readSource = nil
            source.cancel()  // the cancel handler closes the descriptor
        } else {
            Darwin.close(fd)
        }
        lock.unlock()
        handler?()
    }
}
