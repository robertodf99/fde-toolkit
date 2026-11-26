/// Everything the app needs to post one native notification for an entry.
public struct NotificationSpec: Equatable, Sendable {
    /// The entry id: re-posting with it replaces the notification; removal uses it.
    public var identifier: String
    /// The project: macOS groups notifications per thread.
    public var threadIdentifier: String
    /// Names the set of buttons; macOS keys buttons by it, so a category always means
    /// the same buttons.
    public var categoryIdentifier: String
    /// "project · kind".
    public var title: String
    /// The request in plain language.
    public var body: String
    /// The buttons, in order.
    public var actions: [NotificationActionSpec]
    /// Whether to play the default sound.
    public var playsSound: Bool

    /// Creates a notification.
    public init(
        identifier: String, threadIdentifier: String, categoryIdentifier: String, title: String, body: String,
        actions: [NotificationActionSpec], playsSound: Bool = true
    ) {
        self.identifier = identifier
        self.threadIdentifier = threadIdentifier
        self.categoryIdentifier = categoryIdentifier
        self.title = title
        self.body = body
        self.actions = actions
        self.playsSound = playsSound
    }
}
