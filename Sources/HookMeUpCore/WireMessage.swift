import Foundation

/// Everything that travels over the hook ↔ agent socket, one framed JSON message each.
///
/// The cases are synthesized `Codable`: an agent that does not know a case cannot decode
/// it and closes the connection, which is how a client tells an older agent apart.
public enum WireMessage: Codable, Equatable, Sendable {
    /// Hook → agent: a request that waits for a decision.
    case request(RequestEnvelope)
    /// Hook → agent: a heads-up (waiting, finished). `finished` (the Stop hook) also
    /// releases the session's requests still waiting, with `.paused`: they were answered
    /// in the terminal, and Claude Code does not stop their hooks.
    case notify(NotifyEnvelope)
    /// Hook → agent: the session moved on (new prompt, session end); drop its heads-ups
    /// and release its requests still waiting, with `.paused`.
    case clear(sessionID: String)
    /// Hook → agent: the hook gave up waiting for request `id`.
    case timedOut(id: UUID)
    /// Agent → hook: the answer to a request.
    case response(ResponseEnvelope)
    /// `hook-me-up-setup` → agent: how are you? The agent answers with one `status` and
    /// closes the connection.
    case statusQuery
    /// Agent → `hook-me-up-setup`: the answer to `statusQuery`.
    case status(AgentStatus)
    /// `hook-me-up-setup notifications --test` → agent: show a test notification if
    /// notifications are allowed (never a request), then close the connection.
    case testNotification
}
