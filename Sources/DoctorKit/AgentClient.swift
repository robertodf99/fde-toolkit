import Darwin
import Foundation
import HookMeUpCore
import HookMeUpIPC

/// `hook-me-up-setup`'s side of the agent socket: the same client, UID check and framing
/// as the hook.
public enum AgentClient {
    /// Asks the agent for its status: connect, send `statusQuery`, wait for `status`.
    /// Each step gets at most `timeout`.
    public static func status(socketPath: URL, timeout: TimeInterval) -> AgentReply {
        let connection: Connection
        switch connect(socketPath, timeout: timeout) {
        case .connected(let connected): connection = connected
        case .failed(let reply): return reply
        }
        defer { connection.close() }
        do {
            try connection.send(.statusQuery)
            switch try connection.receive(timeout: timeout) {
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
