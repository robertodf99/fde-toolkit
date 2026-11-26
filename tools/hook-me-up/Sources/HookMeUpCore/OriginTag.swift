/// Where a request comes from, when it is not the main interactive session.
public enum OriginTag: String, Codable, Sendable {
    /// A subagent of the session.
    case subagent
    /// A headless run (`claude -p`, the SDK).
    case headless
}
