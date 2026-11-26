import Foundation

/// The agent's single answer to one request, sent on that request's connection.
public struct ResponseEnvelope: Codable, Equatable, Sendable {
    /// The request id; the hook ignores an answer for any other id.
    public var id: UUID
    /// The decision, or `.paused`.
    public var outcome: ResponseOutcome

    /// Creates an answer.
    public init(id: UUID, outcome: ResponseOutcome) {
        self.id = id
        self.outcome = outcome
    }
}
