/// What the agent should do about a notification response.
public enum NotificationOutcome: Equatable, Sendable {
    /// Send this decision to the hook.
    case decide(UserDecision)
    /// Bring the session's terminal forward (and let the terminal dialog answer).
    case openSession
    /// The current question (step) was answered with these labels (or free text).
    case answer(step: Int, labels: [String])
    /// A reply that could not be understood: re-post the question with this hint.
    case invalidReply(step: Int, hint: String)
    /// Nothing decided, but keep the request answerable (e.g. empty feedback).
    case repost
    /// Nothing to do (a stale or unknown action).
    case ignore
}
