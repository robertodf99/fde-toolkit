import HookMeUpCore

/// Posts and removes native notifications; in the app, UNUserNotificationCenter.
@MainActor
public protocol NotificationPresenting: AnyObject {
    /// Asks the user for permission when macOS has not asked yet, then reports the
    /// result. Called once at launch.
    func requestAuthorization() async -> NotificationAuthorization
    /// The current authorization. The agent asks before every request, so turning
    /// notifications on or off in System Settings takes effect at once.
    func authorization() async -> NotificationAuthorization
    /// Shows `spec`, replacing any notification with the same identifier.
    func post(_ spec: NotificationSpec)
    /// Removes the notifications with these identifiers, delivered or not yet shown.
    func remove(identifiers: [String])
}
