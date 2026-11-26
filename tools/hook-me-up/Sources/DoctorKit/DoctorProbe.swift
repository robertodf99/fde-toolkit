import Foundation
import HookMeUpCore

/// Everything `Doctor` reads from the system, so its checks are pure and testable with a
/// fake. `SystemDoctorProbe` is the real one. Nothing here writes.
public protocol DoctorProbe {
    /// The contents of the file at `path`; nil when it doesn't exist or can't be read.
    func contents(of path: String) -> Data?
    /// Whether an executable file exists at `path`.
    func isExecutable(_ path: String) -> Bool
    /// Whether anything exists at `path`.
    func exists(_ path: String) -> Bool
    /// `path` with its symlinks resolved, so two spellings of one place compare equal.
    func canonicalPath(_ path: String) -> String
    /// What launchd knows about the LaunchAgent `label` in this user's GUI session.
    func launchAgentState(label: String) -> LaunchAgentState
    /// Asks the agent listening at `socketPath` for its status, within `timeout`.
    func queryAgent(socketPath: String, timeout: TimeInterval) -> AgentReply
}

/// A LaunchAgent as `launchctl print gui/<uid>/<label>` reports it.
public enum LaunchAgentState: Equatable, Sendable {
    /// launchd doesn't know the label: it was never loaded or was removed.
    case notLoaded
    /// Loaded, and the process runs.
    case running(pid: Int)
    /// Loaded, but no process runs (e.g. quit from the menu, or it keeps crashing).
    case notRunning
    /// `launchctl` itself failed; the text says why.
    case unknown(String)
}

/// The agent's answer to a status query, or why there was none.
public enum AgentReply: Equatable, Sendable {
    /// The agent answered.
    case status(AgentStatus)
    /// Nothing exists at the socket path: no agent has run since login, or it quit.
    case noSocket
    /// The socket exists but nobody listens on it (the agent crashed or was killed).
    case notListening
    /// The agent accepted the query and closed the connection without answering: an
    /// agent from before status queries, which can't decode them.
    case closedWithoutAnswer
    /// No answer in time.
    case timedOut
    /// Anything else (another user's socket, a path too long, an unexpected answer).
    case failed(String)
}
