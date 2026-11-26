import Foundation

/// What a request is about, in plain language: a functional title, a description and
/// warning tags.
public struct RequestSummary: Codable, Equatable, Sendable {
    /// What the entry asks for.
    public var kind: EntryKind
    /// What happens, e.g. "Run a command".
    public var title: String
    /// One line of detail, e.g. the command.
    public var description: String
    /// Rule-based warnings (network, deletes files…).
    public var tags: [EffectTag]
    /// Subagent or headless, when not the main session.
    public var origin: OriginTag?

    /// Creates a summary.
    public init(
        kind: EntryKind, title: String, description: String, tags: [EffectTag], origin: OriginTag?
    ) {
        self.kind = kind
        self.title = title
        self.description = description
        self.tags = tags
        self.origin = origin
    }
}
