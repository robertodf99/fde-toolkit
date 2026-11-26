/// What the agent answers to a request.
public enum ResponseOutcome: Codable, Equatable, Sendable {
    /// The user decided; the hook turns this into its output.
    case decided(UserDecision)
    /// No decision: the hook prints nothing. Sent while paused or with notifications off
    /// (Claude Code then shows its terminal dialog), and when the session moved on after
    /// the request was answered in the terminal.
    case paused
}
