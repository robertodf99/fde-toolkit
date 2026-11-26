/// What the user did with a notification (UNNotificationResponse, simplified).
public enum NotificationResponse: Equatable, Sendable {
    /// Clicked the notification body.
    case defaultClick
    /// Closed the notification without answering.
    case dismissed
    /// Chose the action button with this identifier.
    case action(String)
    /// Typed `text` into the text-input action with identifier `action`.
    case text(action: String, text: String)
}
