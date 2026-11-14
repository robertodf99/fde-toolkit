import Foundation

/// Everything that travels over the hook ↔ agent socket, one framed JSON message each.
public enum WireMessage: Codable, Equatable, Sendable {
    /// Hook → agent: a request that waits for a decision.
    case request(RequestEnvelope)
    /// Hook → agent: a heads-up (waiting, finished).
    case notify(NotifyEnvelope)
    /// Hook → agent: the session moved on; drop its heads-ups.
    case clear(sessionID: String)
    /// Hook → agent: the hook gave up waiting for request `id`.
    case timedOut(id: UUID)
    /// Agent → hook: the answer to a request.
    case response(ResponseEnvelope)
}
