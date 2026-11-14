import Foundation

/// A fire-and-forget heads-up (waiting for your reply, finished) from the hook.
public struct NotifyEnvelope: Codable, Equatable, Sendable {
    /// The Claude Code session.
    public var sessionID: String
    /// The session's project.
    public var project: ProjectInfo
    /// `.waiting` or `.finished`.
    public var kind: EntryKind
    /// The one-line text to show.
    public var message: String
    /// Where the session's terminal is.
    public var terminal: TerminalHint

    /// Creates a heads-up.
    public init(sessionID: String, project: ProjectInfo, kind: EntryKind, message: String, terminal: TerminalHint) {
        self.sessionID = sessionID
        self.project = project
        self.kind = kind
        self.message = message
        self.terminal = terminal
    }
}
