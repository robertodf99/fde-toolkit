/// What the running agent says about itself when asked (`WireMessage.statusQuery`), for
/// `hook-me-up-setup doctor` and the installer. Never any request content.
public struct AgentStatus: Codable, Equatable, Sendable {
    /// The agent's version (`CFBundleShortVersionString`), e.g. "0.2.0".
    public var version: String
    /// The agent's build (`CFBundleVersion`).
    public var build: String
    /// Whether macOS lets the agent show notifications, and how they appear.
    public var notifications: NotificationAuthorization
    /// Whether requests go to the terminal because of a pause.
    public var paused: Bool
    /// How many requests and heads-ups are waiting.
    public var pendingCount: Int

    /// Creates a status.
    public init(
        version: String, build: String, notifications: NotificationAuthorization, paused: Bool, pendingCount: Int
    ) {
        self.version = version
        self.build = build
        self.notifications = notifications
        self.paused = paused
        self.pendingCount = pendingCount
    }
}
