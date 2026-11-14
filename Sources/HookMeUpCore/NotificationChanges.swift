/// What to tell macOS: notifications to post (new or changed) and identifiers to remove.
public struct NotificationChanges: Equatable, Sendable {
    /// Notifications to post; one with an identifier already shown replaces it.
    public var post: [NotificationSpec]
    /// Identifiers of notifications to remove.
    public var remove: [String]

    /// Creates a change set.
    public init(post: [NotificationSpec], remove: [String]) {
        self.post = post
        self.remove = remove
    }
}
