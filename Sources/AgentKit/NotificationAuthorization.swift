/// Whether macOS lets the agent show notifications, as System Settings reports it.
public struct NotificationAuthorization: Equatable, Sendable, CustomStringConvertible {
    /// The user's answer to the permission prompt.
    public enum Status: String, Sendable {
        case notDetermined
        case denied
        case authorized
        case provisional
    }

    /// How notifications appear ("Alerts" stay on screen until answered).
    public enum AlertStyle: String, Sendable {
        case none
        case banner
        case alert
    }

    /// The user's answer to the permission prompt.
    public var status: Status
    /// How notifications appear.
    public var alertStyle: AlertStyle

    /// Creates an authorization value.
    public init(status: Status, alertStyle: AlertStyle) {
        self.status = status
        self.alertStyle = alertStyle
    }

    /// Whether requests can be shown as notifications. When false, every request goes
    /// to the terminal dialog (fail-open).
    public var allowsNotifications: Bool { status == .authorized || status == .provisional }

    /// For the log, e.g. "authorized, style alert".
    public var description: String { "\(status.rawValue), style \(alertStyle.rawValue)" }
}
