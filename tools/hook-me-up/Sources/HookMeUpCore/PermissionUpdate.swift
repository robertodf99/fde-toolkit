import Foundation

/// A permission update entry, as used by `permission_suggestions` (input) and
/// `updatedPermissions` (output). Only known fields are modelled, so re-encoding an
/// entry can never carry fields we did not inspect.
public struct PermissionUpdate: Codable, Equatable, Sendable {
    /// "addRules", "addDirectories", "setMode"…
    public var type: String
    /// The rules, for rule updates.
    public var rules: [PermissionRule]?
    /// "allow", "deny" or "ask", for rule updates.
    public var behavior: String?
    /// The permission mode, for "setMode".
    public var mode: String?
    /// The folders, for directory updates.
    public var directories: [String]?
    /// Where the update applies: "session", "localSettings", "projectSettings"…
    public var destination: String

    /// Creates an update.
    public init(
        type: String,
        rules: [PermissionRule]? = nil,
        behavior: String? = nil,
        mode: String? = nil,
        directories: [String]? = nil,
        destination: String
    ) {
        self.type = type
        self.rules = rules
        self.behavior = behavior
        self.mode = mode
        self.directories = directories
        self.destination = destination
    }

    /// Builds an entry from decoded JSON; nil when the shape is wrong (a missing
    /// `type`/`destination`, or a present field of the wrong type).
    init?(json: JSONValue) {
        guard let object = json.objectValue,
            let type = object["type"]?.stringValue,
            let destination = object["destination"]?.stringValue
        else { return nil }

        var rules: [PermissionRule]?
        if let rulesJSON = object["rules"] {
            guard let items = rulesJSON.arrayValue else { return nil }
            var parsed: [PermissionRule] = []
            for item in items {
                guard let rule = item.objectValue, let toolName = rule["toolName"]?.stringValue else { return nil }
                var content: String?
                if let contentJSON = rule["ruleContent"] {
                    guard let text = contentJSON.stringValue else { return nil }
                    content = text
                }
                parsed.append(PermissionRule(toolName: toolName, ruleContent: content))
            }
            rules = parsed
        }

        var directories: [String]?
        if let directoriesJSON = object["directories"] {
            guard let items = directoriesJSON.arrayValue else { return nil }
            let paths = items.compactMap(\.stringValue)
            guard paths.count == items.count else { return nil }
            directories = paths
        }

        func optionalString(_ key: String) -> (ok: Bool, value: String?) {
            guard let value = object[key] else { return (true, nil) }
            guard let text = value.stringValue else { return (false, nil) }
            return (true, text)
        }
        let behavior = optionalString("behavior")
        let mode = optionalString("mode")
        guard behavior.ok, mode.ok else { return nil }

        self.init(
            type: type, rules: rules, behavior: behavior.value, mode: mode.value,
            directories: directories, destination: destination)
    }
}
