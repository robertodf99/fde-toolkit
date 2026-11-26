import Darwin
import Foundation

/// Why a socket operation failed. The hook treats every one of these as "no decision"
/// (it prints nothing and Claude Code shows its own dialog).
public enum SocketError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The socket path does not fit in sun_path (104 bytes including the final NUL).
    case pathTooLong(Int)
    /// The socket path is empty or contains a NUL byte.
    case invalidPath
    /// The socket's folder exists but is not a directory.
    case notADirectory(String)
    /// The socket's folder is a symbolic link.
    case symlinkRefused(String)
    /// The socket or its folder belongs to another user.
    case wrongOwner(String)
    /// Something other than a socket exists at the socket path.
    case notASocket(String)
    /// Another agent is already listening on the socket path.
    case alreadyRunning
    /// The peer runs as another user.
    case peerUIDMismatch(expected: uid_t, actual: uid_t)
    /// A system call failed with this errno.
    case system(call: String, code: Int32)
    /// No reply in time.
    case timedOut
    /// The connection is closed.
    case closed

    /// A sentence for the log.
    public var description: String {
        switch self {
        case .pathTooLong(let length): "the socket path is too long (\(length) bytes)"
        case .invalidPath: "the socket path is empty or invalid"
        case .notADirectory(let path): "\(path) is not a directory"
        case .symlinkRefused(let path): "\(path) is a symbolic link"
        case .wrongOwner(let path): "\(path) belongs to another user"
        case .notASocket(let path): "\(path) is not a socket"
        case .alreadyRunning: "another agent is already listening"
        case .peerUIDMismatch(let expected, let actual): "the peer runs as uid \(actual), not \(expected)"
        case .system(let call, let code): "\(call) failed: \(String(cString: strerror(code)))"
        case .timedOut: "timed out"
        case .closed: "the connection is closed"
        }
    }
}
