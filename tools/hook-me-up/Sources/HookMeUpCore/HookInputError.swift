/// Why a hook's stdin was not understood. The hook then prints nothing.
public enum HookInputError: Error, Equatable, CustomStringConvertible {
    /// The input is JSON but not an object.
    case notAnObject
    /// A required field is missing or empty.
    case missingField(String)

    /// A sentence for diagnostics.
    public var description: String {
        switch self {
        case .notAnObject: "the hook input is not a JSON object"
        case .missingField(let key): "the hook input has no \(key)"
        }
    }
}
