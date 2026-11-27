/// The hook protocol used by the calling CLI. Claude remains the default.
public enum HookClient: String, Sendable, Codable {
    case claude
    case codex

    /// Bundled PNG used only to identify the source of a notification.
    public var notificationImageName: String { "notification-" + rawValue }
}
