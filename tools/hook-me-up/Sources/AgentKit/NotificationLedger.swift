import HookMeUpCore

/// What the agent has posted, so only changes reach macOS and each entry plays its
/// sound once (follow-ups such as the next question or a hint are silent).
struct NotificationLedger {
    private(set) var posted: [NotificationSpec] = []
    private var announced: Set<String> = []
    private var actedOn: Set<String> = []

    /// Moves to `desired`: returns what to post (sound already decided) and what to remove.
    mutating func update(to desired: [NotificationSpec]) -> NotificationChanges {
        let changes = NativeNotification.changes(before: posted, after: desired)
        let changed = Set(changes.post.map(\.identifier))
        let post =
            desired
            .filter { changed.contains($0.identifier) || actedOn.contains($0.identifier) }
            .map { spec in
                var spec = spec
                spec.playsSound = spec.playsSound && !announced.contains(spec.identifier)
                announced.insert(spec.identifier)
                return spec
            }
        posted = desired
        actedOn.removeAll()
        for identifier in changes.remove { announced.remove(identifier) }
        return NotificationChanges(post: post, remove: changes.remove)
    }

    /// The user acted on the notification, and macOS may have taken it away: the next
    /// update posts it again if its entry is still waiting (and removes it otherwise).
    mutating func noteActedOn(_ identifier: String) {
        actedOn.insert(identifier)
    }
}
