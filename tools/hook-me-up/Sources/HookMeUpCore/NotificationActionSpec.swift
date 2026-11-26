/// A notification action as UNNotificationAction / UNTextInputNotificationAction will
/// show it.
public struct NotificationActionSpec: Equatable, Sendable {
    /// How the button looks and behaves.
    public enum Style: Equatable, Sendable {
        /// A plain button.
        case normal
        /// Shown in red (Deny).
        case destructive
    }

    /// A button that opens a text field.
    public struct TextInput: Equatable, Sendable {
        /// The field's send button.
        public let buttonTitle: String
        /// The field's placeholder.
        public let placeholder: String

        /// Creates a text input.
        public init(buttonTitle: String, placeholder: String) {
            self.buttonTitle = buttonTitle
            self.placeholder = placeholder
        }
    }

    /// Reported back in the response.
    public let identifier: String
    /// The button's label.
    public let title: String
    /// How the button looks and behaves.
    public let style: Style
    /// Set for a button that asks for text.
    public let textInput: TextInput?
    /// The Mac must be unlocked to use it (every button that answers Claude).
    public let requiresAuthentication: Bool

    /// Creates an action.
    public init(
        identifier: String, title: String, style: Style = .normal, textInput: TextInput? = nil,
        requiresAuthentication: Bool = false
    ) {
        self.identifier = identifier
        self.title = title
        self.style = style
        self.textInput = textInput
        self.requiresAuthentication = requiresAuthentication
    }
}
