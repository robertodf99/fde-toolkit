import Foundation
import HookMeUpCore

/// A settings file as read: its exact bytes (nil when it does not exist) and its content.
public struct SettingsDocument: Sendable {
    /// The file's bytes as read, for the as-is diff and the "changed since read" check.
    public let original: Data?
    /// The parsed content (`{}` for a missing file).
    public let value: JSONValue
}
