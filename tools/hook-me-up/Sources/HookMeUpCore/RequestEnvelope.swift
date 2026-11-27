import Foundation

/// A blocking request from `hook-me-up permission`. `input` is the hook's
/// `tool_input`, for display only (question options, plan text): the hook never takes
/// tool input back from the agent.
public struct RequestEnvelope: Codable, Equatable, Sendable {
    /// Fresh per request; the answer must carry it.
    public var id: UUID
    /// The Claude Code session.
    public var sessionID: String
    /// The session's project.
    public var project: ProjectInfo
    /// The request in plain language.
    public var summary: RequestSummary
    /// The hook's `tool_input`, for display only.
    public var input: JSONValue
    /// Where the session's terminal is.
    public var terminal: TerminalHint
    /// What "Approve for session" would add (the hook's session-only suggestions), for
    /// display only: the hook re-derives it from its own input when it answers.
    public var sessionPermissions: [PermissionUpdate]
    /// The folder Claude Code was started in (`CLAUDE_PROJECT_DIR`, else the hook's cwd):
    /// what a click opens in an editor. Optional on the wire, for older hooks.
    public var sessionFolder: String?
    /// Optional source label; absent for Claude and older hooks.
    public var client: HookClient?

    /// Creates a request.
    public init(
        id: UUID, sessionID: String, project: ProjectInfo, summary: RequestSummary, input: JSONValue,
        terminal: TerminalHint, sessionPermissions: [PermissionUpdate] = [], sessionFolder: String? = nil,
        client: HookClient? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.project = project
        self.summary = summary
        self.input = input
        self.terminal = terminal
        self.sessionPermissions = sessionPermissions
        self.sessionFolder = sessionFolder
        self.client = client
    }
}
