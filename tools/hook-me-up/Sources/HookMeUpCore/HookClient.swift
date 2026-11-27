/// The hook protocol used by the calling CLI. Claude remains the default.
public enum HookClient: String, Sendable, Codable {
    case claude
    case codex
}
