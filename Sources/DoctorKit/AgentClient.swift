import Darwin
import Foundation
import HookMeUpCore
import HookMeUpIPC

/// `hook-me-up-setup`'s side of the agent socket: the same client, UID check and framing
/// as the hook.
public enum AgentClient {
    /// Asks the agent for its status: connect, send `statusQuery`, wait for `status`, all
    /// within `timeout`.
    public static func status(socketPath: URL, timeout: TimeInterval) -> AgentReply {
        let deadline = Date().addingTimeInterval(timeout)
        let connection: Connection
        switch connect(socketPath, timeout: timeout) {
        case .connected(let connected): connection = connected
        case .failed(let reply): return reply
        }
        defer { connection.close() }
        do {
            try connection.send(.statusQuery)
            switch try connection.receive(timeout: max(0, deadline.timeIntervalSinceNow)) {
            case .status(let status)?: return .status(status)
            case nil: return .closedWithoutAnswer
            case .some: return .failed("the agent answered something else")
            }
        } catch SocketError.timedOut {
            return .timedOut
        } catch SocketError.closed {
            return .closedWithoutAnswer
        } catch {
            return .failed(String(describing: error))
        }
    }

    /// Asks the agent to show its test notification and waits until it closes the
    /// connection (it has then posted it, or decided not to), all within `timeout`. False
    /// when the message couldn't be delivered or nothing came back in time.
    public static func sendTestNotification(socketPath: URL, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        guard case .connected(let connection) = connect(socketPath, timeout: timeout) else { return false }
        defer { connection.close() }
        do {
            try connection.send(.testNotification)
            _ = try connection.receive(timeout: max(0, deadline.timeIntervalSinceNow))  // nil: closed once handled
            return true
        } catch {
            return false
        }
    }

    enum Connected {
        case connected(Connection)
        case failed(AgentReply)
    }

    /// Connects, mapping the usual failures to what they mean for the user.
    static func connect(_ socketPath: URL, timeout: TimeInterval) -> Connected {
        do {
            return .connected(try SocketClient.connect(path: socketPath, timeout: timeout))
        } catch SocketError.system(_, let code) where code == ENOENT {
            return .failed(.noSocket)
        } catch SocketError.system(_, let code) where code == ECONNREFUSED {
            return .failed(.notListening)
        } catch SocketError.timedOut {
            return .failed(.timedOut)
        } catch {
            return .failed(.failed(String(describing: error)))
        }
    }
}
