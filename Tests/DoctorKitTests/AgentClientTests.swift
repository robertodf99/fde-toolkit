import Darwin
import Foundation
import HookMeUpCore
import HookMeUpIPC
import Testing

@testable import DoctorKit

/// Short folder under /tmp: a socket path must fit in sun_path (104 bytes).
private final class ShortDir {
    let url: URL

    init() throws {
        url = URL(fileURLWithPath: "/tmp/hmd-" + UUID().uuidString.prefix(8).lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    var socket: URL { url.appendingPathComponent("run/agent.sock") }
}

private let sample = AgentStatus(
    version: "0.2.0", build: "0.2.0",
    notifications: NotificationAuthorization(status: .authorized, alertStyle: .banner),
    paused: false, pendingCount: 2)

/// The real client against a real socket server, answering like a current agent, like
/// an agent from before status queries, or not at all.
@Suite(.serialized) struct AgentClientTests {
    @Test func aCurrentAgentAnswersWithItsStatus() throws {
        let dir = try ShortDir()
        let server = SocketServer(path: dir.socket)
        try server.start { connection in
            connection.startReading(queue: .global()) { message in
                if message == .statusQuery { try? connection.send(.status(sample)) }
                connection.close()
            }
        }
        defer { server.stop() }
        #expect(AgentClient.status(socketPath: dir.socket, timeout: 2) == .status(sample))
    }

    @Test func anOlderAgentClosesWithoutAnswering() throws {
        // An agent that can't decode the query closes the connection (as Connection does
        // with a frame it can't read).
        let dir = try ShortDir()
        let server = SocketServer(path: dir.socket)
        try server.start { connection in
            connection.startReading(queue: .global()) { _ in connection.close() }
        }
        defer { server.stop() }
        #expect(AgentClient.status(socketPath: dir.socket, timeout: 2) == .closedWithoutAnswer)
    }

    @Test func anAgentThatNeverAnswersTimesOut() throws {
        let dir = try ShortDir()
        let server = SocketServer(path: dir.socket)
        let held = HeldConnections()
        try server.start { connection in held.keep(connection) }
        defer { server.stop() }
        let started = Date()
        #expect(AgentClient.status(socketPath: dir.socket, timeout: 0.3) == .timedOut)
        #expect(Date().timeIntervalSince(started) < 2)
    }

    @Test func noSocketAndAStaleSocketAreToldApart() throws {
        let dir = try ShortDir()
        #expect(AgentClient.status(socketPath: dir.socket, timeout: 1) == .noSocket)

        // What a killed agent leaves behind: a socket file nobody listens on.
        try FileManager.default.createDirectory(
            at: dir.socket.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(dir.socket.path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        #expect(bound == 0)
        close(fd)
        #expect(AgentClient.status(socketPath: dir.socket, timeout: 1) == .notListening)
    }
}

/// Keeps accepted connections open without reading them.
private final class HeldConnections: @unchecked Sendable {
    private let lock = NSLock()
    private var connections: [Connection] = []

    func keep(_ connection: Connection) {
        lock.withLock { connections.append(connection) }
    }
}
