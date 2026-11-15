import Darwin
import Foundation
import HookMeUpCore
import Testing

@testable import HookMeUpIPC

/// Short directory under /tmp: a socket path must fit in sun_path (104 bytes).
final class ShortTempDir {
    let url: URL

    init() throws {
        url = URL(fileURLWithPath: "/tmp/cpp-" + UUID().uuidString.prefix(8).lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        chmod(url.path, 0o700)
        try? FileManager.default.removeItem(at: url)
    }

    func child(_ name: String) -> URL { url.appendingPathComponent(name) }
}

/// Thread-safe value holder for callbacks that run on dispatch queues.
final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
    /// Changes the value in one step. `value.append(x)` would be a separate get and set,
    /// so two connections' threads could lose each other's change.
    func mutate(_ change: (inout T) -> Void) {
        lock.withLock { change(&stored) }
    }
}

func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        usleep(5_000)
    }
    return condition()
}

func mode(_ path: String) -> (type: mode_t, perms: mode_t, uid: uid_t)? {
    var info = stat()
    guard lstat(path, &info) == 0 else { return nil }
    return (info.st_mode & S_IFMT, info.st_mode & 0o777, info.st_uid)
}

/// Binds a Unix socket at `path` with raw Darwin calls (test-only peer).
func rawBind(_ path: String) -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
        raw.copyBytes(from: bytes)
        raw[bytes.count] = 0
    }
    let result = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    precondition(result == 0, "bind failed: \(errno)")
    return fd
}

/// What a crashed agent leaves behind: a socket file nobody listens on.
func makeStaleSocket(_ path: String) {
    let fd = rawBind(path)
    listen(fd, 1)
    close(fd)
}

/// A raw listener that accepts one connection and writes `bytes` to it.
func serveRawOnce(_ path: String, bytes: Data) -> Thread {
    let fd = rawBind(path)
    listen(fd, 1)
    let thread = Thread {
        let client = accept(fd, nil, nil)
        bytes.withUnsafeBytes { _ = write(client, $0.baseAddress, $0.count) }
        usleep(500_000)
        close(client)
        close(fd)
    }
    thread.start()
    return thread
}

private let sampleRequest = WireMessage.request(
    RequestEnvelope(
        id: UUID(), sessionID: "s", project: ProjectInfo(name: "p", gitRoot: nil, branch: nil, worktree: nil),
        summary: RequestSummary(kind: .permission, title: "t", description: "d", tags: [], origin: nil),
        input: .object([:]), terminal: TerminalHint(ancestorPIDs: [1], tty: nil)
    ))

@Suite(.serialized) struct SocketSecurityTests {
    @Test func directoryCreatedWith0700() throws {
        let temp = try ShortTempDir()
        let dir = temp.child("sock-dir")
        try SocketSecurity.prepareDirectory(dir)
        let info = try #require(mode(dir.path))
        #expect(info.type == S_IFDIR)
        #expect(info.perms == 0o700)
        #expect(info.uid == getuid())
    }

    @Test func wrongModeOwnedDirFixed() throws {
        let temp = try ShortTempDir()
        for perms: mode_t in [0o755, 0o777, 0o711, 0o500] {
            let dir = temp.child("d\(perms)")
            #expect(mkdir(dir.path, 0o700) == 0)
            #expect(chmod(dir.path, perms) == 0)
            try SocketSecurity.prepareDirectory(dir)
            #expect(mode(dir.path)?.perms == 0o700)
        }
    }

    @Test func symlinkDirRejected() throws {
        let temp = try ShortTempDir()
        let real = temp.child("real")
        #expect(mkdir(real.path, 0o755) == 0)
        let link = temp.child("link")
        #expect(symlink(real.path, link.path) == 0)
        #expect(throws: SocketError.self) { try SocketSecurity.prepareDirectory(link) }
        #expect(mode(real.path)?.perms == 0o755)  // target untouched
    }

    @Test func regularFileInsteadOfDirectoryRejected() throws {
        let temp = try ShortTempDir()
        let file = temp.child("file")
        try Data("x".utf8).write(to: file)
        #expect(throws: SocketError.self) { try SocketSecurity.prepareDirectory(file) }
    }

    @Test func peerUIDMatchesSelf() throws {
        var fds: [Int32] = [-1, -1]
        #expect(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds) == 0)
        defer {
            close(fds[0])
            close(fds[1])
        }
        #expect(try SocketSecurity.peerUID(fd: fds[0]) == getuid())
        #expect(throws: SocketError.self) { try SocketSecurity.peerUID(fd: -1) }
    }
}

@Suite(.serialized) struct SocketServerTests {
    @Test func socketIs0600() throws {
        let temp = try ShortTempDir()
        let path = temp.child("run/agent.sock")
        let server = SocketServer(path: path)
        try server.start { _ in }
        defer { server.stop() }
        let info = try #require(mode(path.path))
        #expect(info.type == S_IFSOCK)
        #expect(info.perms == 0o600)
        #expect(info.uid == getuid())
        #expect(mode(path.deletingLastPathComponent().path)?.perms == 0o700)
    }

    @Test func pathTooLongThrows() throws {
        let temp = try ShortTempDir()
        let base = temp.url.path + "/"
        // sun_path is 104 bytes including the terminating NUL: 103 fits, 104 does not.
        let fits = URL(fileURLWithPath: base + String(repeating: "a", count: 103 - base.utf8.count))
        let tooLong = URL(fileURLWithPath: base + String(repeating: "b", count: 104 - base.utf8.count))
        #expect(fits.path.utf8.count == 103)
        #expect(tooLong.path.utf8.count == 104)

        let ok = SocketServer(path: fits)
        try ok.start { _ in }
        ok.stop()

        #expect(throws: SocketError.pathTooLong(104)) { try SocketServer(path: tooLong).start { _ in } }
        #expect(throws: SocketError.pathTooLong(104)) { try SocketClient.connect(path: tooLong, timeout: 0.3) }
    }

    @Test func requestResponseRoundTrip() throws {
        let temp = try ShortTempDir()
        let path = temp.child("agent.sock")
        let server = SocketServer(path: path)
        let received = Box<[WireMessage]>([])
        try server.start { connection in
            connection.startReading(queue: DispatchQueue(label: "test.reader")) { message in
                received.mutate { $0.append(message) }
                if case .request(let request) = message {
                    try? connection.send(.response(ResponseEnvelope(id: request.id, outcome: .decided(.approve))))
                }
            }
        }
        defer { server.stop() }

        let client = try SocketClient.connect(path: path, timeout: 0.3)
        defer { client.close() }
        try client.send(sampleRequest)
        let reply = try client.receive(timeout: 2)
        guard case .request(let sent) = sampleRequest else {
            Issue.record("fixture")
            return
        }
        #expect(reply == .response(ResponseEnvelope(id: sent.id, outcome: .decided(.approve))))
        #expect(received.value == [sampleRequest])
    }

    @Test func largeFrameRoundTrip() throws {
        let temp = try ShortTempDir()
        let path = temp.child("agent.sock")
        let server = SocketServer(path: path)
        let received = Box<WireMessage?>(nil)
        try server.start { connection in
            connection.startReading(queue: DispatchQueue(label: "test.reader")) { received.value = $0 }
        }
        defer { server.stop() }
        let client = try SocketClient.connect(path: path, timeout: 0.3)
        defer { client.close() }
        let big = WireMessage.clear(sessionID: String(repeating: "z", count: 900_000))
        try client.send(big)
        #expect(waitUntil { received.value == big })
    }

    @Test func serverSeesCloseWhenClientDies() throws {
        let temp = try ShortTempDir()
        let path = temp.child("agent.sock")
        let server = SocketServer(path: path)
        let gotRequest = Box(false)
        let closed = Box(0)
        try server.start { connection in
            connection.onClose = { closed.mutate { $0 += 1 } }
            connection.startReading(queue: DispatchQueue(label: "test.reader")) { _ in gotRequest.value = true }
        }
        defer { server.stop() }

        let client = try SocketClient.connect(path: path, timeout: 0.3)
        try client.send(sampleRequest)
        #expect(waitUntil { gotRequest.value })
        #expect(closed.value == 0)
        client.close()  // same as the hook being killed: the kernel closes its end
        #expect(waitUntil { closed.value == 1 })
        usleep(100_000)
        #expect(closed.value == 1)  // exactly once
    }

    @Test func serverSeesCloseWhenClientProcessIsKilled() throws {
        let temp = try ShortTempDir()
        let path = temp.child("agent.sock")
        let server = SocketServer(path: path)
        let closed = Box(false)
        let connected = Box(false)
        try server.start { connection in
            connected.value = true
            connection.onClose = { closed.value = true }
            connection.startReading(queue: DispatchQueue(label: "test.reader")) { _ in }
        }
        defer { server.stop() }

        // A real separate process holds the client end, then gets SIGTERM.
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
        child.arguments = ["-U", path.path]
        child.standardInput = Pipe()
        child.standardOutput = FileHandle.nullDevice
        try child.run()
        #expect(waitUntil { connected.value })
        #expect(!closed.value)
        child.terminate()
        child.waitUntilExit()
        #expect(waitUntil { closed.value })
    }

    @Test func staleSocketIsReplaced() throws {
        let temp = try ShortTempDir()
        let path = temp.child("agent.sock")
        makeStaleSocket(path.path)  // listener gone, socket file left behind (a crash)
        #expect(mode(path.path)?.type == S_IFSOCK)

        let second = SocketServer(path: path)
        try second.start { _ in }
        defer { second.stop() }
        let client = try SocketClient.connect(path: path, timeout: 0.3)
        client.close()
    }

    @Test func refusesToReplaceNonSocketOrLiveServer() throws {
        let temp = try ShortTempDir()
        let path = temp.child("agent.sock")
        try Data("keep me".utf8).write(to: path)
        #expect(throws: SocketError.self) { try SocketServer(path: path).start { _ in } }
        #expect(try Data(contentsOf: path) == Data("keep me".utf8))
        try FileManager.default.removeItem(at: path)

        let live = SocketServer(path: path)
        try live.start { _ in }
        defer { live.stop() }
        #expect(throws: SocketError.alreadyRunning) { try SocketServer(path: path).start { _ in } }
        let client = try SocketClient.connect(path: path, timeout: 0.3)  // still served by the first one
        client.close()
    }

    @Test func stopRemovesSocketFile() throws {
        let temp = try ShortTempDir()
        let path = temp.child("agent.sock")
        let server = SocketServer(path: path)
        try server.start { _ in }
        server.stop()
        #expect(mode(path.path) == nil)
        #expect(throws: SocketError.self) { try SocketClient.connect(path: path, timeout: 0.3) }
    }

    @Test func serverRejectsClientWithOtherUID() throws {
        let temp = try ShortTempDir()
        let path = temp.child("agent.sock")
        let server = SocketServer(path: path, expectedUID: getuid() &+ 1)
        let accepted = Box(false)
        try server.start { _ in accepted.value = true }
        defer { server.stop() }
        let client = try SocketClient.connect(path: path, timeout: 0.3)
        defer { client.close() }
        #expect(try client.receive(timeout: 2) == nil)  // server hung up
        #expect(!accepted.value)
    }
}

@Suite(.serialized) struct SocketClientTests {
    @Test func connectToMissingSocketThrowsFast() throws {
        let temp = try ShortTempDir()
        let start = Date()
        #expect(throws: SocketError.self) { try SocketClient.connect(path: temp.child("none.sock"), timeout: 0.3) }
        #expect(Date().timeIntervalSince(start) < 0.3)
    }

    @Test func connectToStaleSocketThrowsFast() throws {
        let temp = try ShortTempDir()
        let path = temp.child("agent.sock")
        makeStaleSocket(path.path)
        let start = Date()
        #expect(throws: SocketError.self) { try SocketClient.connect(path: path, timeout: 0.3) }
        #expect(Date().timeIntervalSince(start) < 0.3)
    }

    @Test func clientRejectsServerWithOtherUID() throws {
        let temp = try ShortTempDir()
        let path = temp.child("agent.sock")
        let server = SocketServer(path: path)
        try server.start { _ in }
        defer { server.stop() }
        #expect(throws: SocketError.peerUIDMismatch(expected: getuid() &+ 1, actual: getuid())) {
            try SocketClient.connect(path: path, timeout: 0.3, expectedUID: getuid() &+ 1)
        }
    }

    @Test func receiveTimesOutAndReturnsNilOnEOF() throws {
        let temp = try ShortTempDir()
        let path = temp.child("agent.sock")
        let server = SocketServer(path: path)
        let held = Box<Connection?>(nil)
        try server.start { held.value = $0 }
        defer { server.stop() }

        let client = try SocketClient.connect(path: path, timeout: 0.3)
        defer { client.close() }
        let start = Date()
        #expect(throws: SocketError.timedOut) { try client.receive(timeout: 0.2) }
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed >= 0.19 && elapsed < 1)

        #expect(waitUntil { held.value != nil })
        held.value?.close()
        #expect(try client.receive(timeout: 2) == nil)
    }

    @Test func garbageFromPeerThrows() throws {
        let temp = try ShortTempDir()
        let path = temp.child("agent.sock")
        _ = serveRawOnce(path.path, bytes: Data([0, 0, 0, 3]) + Data("abc".utf8))
        let client = try SocketClient.connect(path: path, timeout: 0.3)
        defer { client.close() }
        #expect(throws: (any Error).self) { try client.receive(timeout: 2) }
    }

    @Test func sendAfterCloseThrows() throws {
        let temp = try ShortTempDir()
        let path = temp.child("agent.sock")
        let server = SocketServer(path: path)
        try server.start { _ in }
        defer { server.stop() }
        let client = try SocketClient.connect(path: path, timeout: 0.3)
        client.close()
        #expect(throws: SocketError.self) { try client.send(.clear(sessionID: "s")) }
    }
}

/// A server that echoes a request with an approval, and the checks it reported.
private final class RecoveringServer {
    let server: SocketServer
    let events = Box<[SocketCheck]>([])

    init(path: URL, checkInterval: TimeInterval = 3600) throws {
        server = SocketServer(path: path)
        let events = events
        try server.start(
            checkInterval: checkInterval, onCheck: { result in events.mutate { $0.append(result) } },
            onConnection: { connection in
                connection.startReading(queue: DispatchQueue(label: "test.reader")) { message in
                    if case .request(let request) = message {
                        try? connection.send(.response(ResponseEnvelope(id: request.id, outcome: .decided(.approve))))
                    }
                }
            })
    }

    deinit { server.stop() }
}

/// Sends a request and expects the approval back.
private func roundTrip(_ client: Connection) throws -> Bool {
    guard case .request(let sent) = sampleRequest else { return false }
    try client.send(sampleRequest)
    return try client.receive(timeout: 2) == .response(ResponseEnvelope(id: sent.id, outcome: .decided(.approve)))
}

private func roundTrip(at path: URL) throws -> Bool {
    let client = try SocketClient.connect(path: path, timeout: 0.3)
    defer { client.close() }
    return try roundTrip(client)
}

private func inode(_ path: String) -> ino_t? {
    var info = stat()
    return lstat(path, &info) == 0 ? info.st_ino : nil
}

/// The agent's socket comes back when it (or its folder) is removed, and the agent gives
/// way to another agent that took the path.
@Suite(.serialized) struct SocketRecoveryTests {
    @Test func aRemovedSocketIsBoundAgainAt0600() throws {
        let temp = try ShortTempDir()
        let path = temp.child("run/agent.sock")
        let agent = try RecoveringServer(path: path)
        #expect(agent.server.checkSocket() == .intact)
        #expect(unlink(path.path) == 0)
        #expect(agent.server.checkSocket() == .rebound)
        let info = try #require(mode(path.path))
        #expect(info.type == S_IFSOCK && info.perms == 0o600 && info.uid == getuid())
        #expect(try roundTrip(at: path))
        #expect(agent.server.checkSocket() == .intact)
    }

    @Test func aRemovedFolderComesBackAt0700() throws {
        let temp = try ShortTempDir()
        let folder = temp.child("run")
        let path = folder.appendingPathComponent("agent.sock")
        let agent = try RecoveringServer(path: path)
        try FileManager.default.removeItem(at: folder)
        #expect(agent.server.checkSocket() == .rebound)
        #expect(mode(folder.path)?.perms == 0o700)
        #expect(mode(path.path)?.type == S_IFSOCK)
        #expect(try roundTrip(at: path))
    }

    @Test func aFolderRecreatedOpenIsMadePrivateAgain() throws {
        let temp = try ShortTempDir()
        let folder = temp.child("run")
        let path = folder.appendingPathComponent("agent.sock")
        let agent = try RecoveringServer(path: path)
        try FileManager.default.removeItem(at: folder)
        #expect(mkdir(folder.path, 0o755) == 0)
        #expect(chmod(folder.path, 0o755) == 0)  // whatever the umask
        #expect(agent.server.checkSocket() == .rebound)
        #expect(mode(folder.path)?.perms == 0o700)
        #expect(try roundTrip(at: path))
    }

    /// The timer finds the change on its own and reports it once.
    @Test func thePeriodicCheckRebindsAndReportsIt() throws {
        let temp = try ShortTempDir()
        let path = temp.child("agent.sock")
        let agent = try RecoveringServer(path: path, checkInterval: 0.05)
        usleep(200_000)
        #expect(agent.events.value.isEmpty)  // nothing changed: no event
        #expect(unlink(path.path) == 0)
        #expect(waitUntil { agent.events.value == [.rebound] })
        usleep(200_000)
        #expect(agent.events.value == [.rebound])
        #expect(try roundTrip(at: path))
    }

    /// Another server took the path after ours was removed: this one gives way, and its
    /// stop() leaves the other's socket alone.
    @Test func anotherLiveServerAtThePathMakesThisOneYield() throws {
        let temp = try ShortTempDir()
        let path = temp.child("agent.sock")
        let first = try RecoveringServer(path: path)
        #expect(unlink(path.path) == 0)
        let second = try RecoveringServer(path: path)
        let secondInode = inode(path.path)
        #expect(first.server.checkSocket() == .yielded)
        #expect(first.server.checkSocket() == .stopped)
        #expect(inode(path.path) == secondInode)
        #expect(try roundTrip(at: path))  // served by the second
        first.server.stop()
        #expect(inode(path.path) == secondInode)
        #expect(try roundTrip(at: path))
        #expect(second.server.checkSocket() == .intact)
    }

    /// The timer notices a live socket put in place of ours (atomically, by rename) and
    /// reports the yield.
    @Test func thePeriodicCheckYieldsToALiveSocketAndReportsIt() throws {
        let temp = try ShortTempDir()
        let path = temp.child("agent.sock")
        let first = try RecoveringServer(path: path, checkInterval: 0.05)
        let other = temp.child("other.sock")
        let listener = rawBind(other.path)
        defer { close(listener) }
        #expect(listen(listener, 4) == 0)
        let otherInode = inode(other.path)
        #expect(rename(other.path, path.path) == 0)
        #expect(waitUntil { first.events.value == [.yielded] })
        first.server.stop()
        #expect(inode(path.path) == otherInode)
        let client = try SocketClient.connect(path: path, timeout: 0.3)  // the other one's backlog
        client.close()
    }

    /// Something that isn't a socket is never removed (reported once, however many checks
    /// run); once it is gone, the socket comes back.
    @Test func aFileAtThePathIsKeptAndReportedOnce() throws {
        let temp = try ShortTempDir()
        let path = temp.child("agent.sock")
        let agent = try RecoveringServer(path: path, checkInterval: 0.05)
        let file = temp.child("file")
        try Data("keep me".utf8).write(to: file)
        #expect(rename(file.path, path.path) == 0)  // in place of the socket, in one step
        #expect(waitUntil { !agent.events.value.isEmpty })
        usleep(200_000)  // several more checks
        #expect(agent.events.value == [.failed(.notASocket(path.path))])
        #expect(try Data(contentsOf: path) == Data("keep me".utf8))
        #expect(agent.server.checkSocket() == .failed(.notASocket(path.path)))
        try FileManager.default.removeItem(at: path)
        #expect(waitUntil { agent.events.value.last == .rebound })
        #expect(try roundTrip(at: path))
    }

    @Test func aSymbolicLinkInPlaceOfTheFolderIsRefusedAndLeftAlone() throws {
        let temp = try ShortTempDir()
        let folder = temp.child("run")
        let path = folder.appendingPathComponent("agent.sock")
        let agent = try RecoveringServer(path: path)
        try FileManager.default.removeItem(at: folder)
        let elsewhere = temp.child("elsewhere")
        #expect(mkdir(elsewhere.path, 0o755) == 0)
        #expect(symlink(elsewhere.path, folder.path) == 0)
        #expect(agent.server.checkSocket() == .failed(.symlinkRefused(folder.path)))
        #expect(mode(folder.path)?.type == S_IFLNK)
        #expect(try FileManager.default.contentsOfDirectory(atPath: elsewhere.path).isEmpty)
        #expect(mode(elsewhere.path)?.perms == 0o755)
    }

    @Test func aStaleSocketInItsPlaceIsReplaced() throws {
        let temp = try ShortTempDir()
        let path = temp.child("agent.sock")
        let agent = try RecoveringServer(path: path)
        #expect(unlink(path.path) == 0)
        makeStaleSocket(path.path)
        let stale = inode(path.path)
        #expect(agent.server.checkSocket() == .rebound)
        #expect(inode(path.path) != stale)
        #expect(try roundTrip(at: path))
    }

    @Test func aConnectionFromBeforeTheRebindStillWorks() throws {
        let temp = try ShortTempDir()
        let path = temp.child("agent.sock")
        let agent = try RecoveringServer(path: path)
        let early = try SocketClient.connect(path: path, timeout: 0.3)
        defer { early.close() }
        #expect(unlink(path.path) == 0)
        #expect(agent.server.checkSocket() == .rebound)
        #expect(try roundTrip(early))
        #expect(try roundTrip(at: path))
    }

    /// After a rebind, stop() removes the new socket.
    @Test func stopAfterARebindRemovesTheNewSocket() throws {
        let temp = try ShortTempDir()
        let path = temp.child("agent.sock")
        let agent = try RecoveringServer(path: path)
        #expect(unlink(path.path) == 0)
        #expect(agent.server.checkSocket() == .rebound)
        agent.server.stop()
        #expect(mode(path.path) == nil)
    }

    @Test func stopEndsTheChecks() throws {
        let temp = try ShortTempDir()
        let path = temp.child("agent.sock")
        let agent = try RecoveringServer(path: path, checkInterval: 0.05)
        agent.server.stop()
        #expect(mode(path.path) == nil)
        usleep(200_000)
        #expect(mode(path.path) == nil)  // not bound again
        #expect(agent.events.value.isEmpty)
        #expect(agent.server.checkSocket() == .stopped)
        #expect(SocketServer(path: path).checkSocket() == .stopped)  // never started
    }
}
