/// Why the installer refused to change a settings document.
public enum SettingsMergerError: Error, Equatable, CustomStringConvertible {
    /// The settings document is not a JSON object.
    case notAnObject
    /// A key the installer must edit (e.g. `hooks`) has an unexpected type.
    case unexpectedShape(String)

    /// A sentence for the installer's output.
    public var description: String {
        switch self {
        case .notAnObject: "the settings are not a JSON object"
        case .unexpectedShape(let key): "\(key) does not have the shape Claude Code uses; edit it by hand first"
        }
    }
}
