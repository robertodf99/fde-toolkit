/// What the agent answers to a request.
public enum ResponseOutcome: Codable, Equatable, Sendable {
    /// The user decided; the hook turns this into its output.
    case decided(UserDecision)
    /// No decision (paused, or notifications are off): the hook prints nothing and
    /// Claude Code shows its terminal dialog.
    case paused
}
