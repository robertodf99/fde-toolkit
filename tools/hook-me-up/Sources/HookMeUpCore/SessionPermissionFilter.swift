import Foundation

/// Turns Claude Code's permission suggestions into what "Approve for session" may apply.
///
/// Only `addRules` (behavior "allow", at least one rule) and `addDirectories` (at least
/// one directory) survive, each rebuilt field by field with `destination: "session"`.
/// Everything else (setMode, replace/remove, deny/ask rules, unknown types) is dropped,
/// so nothing is ever written to userSettings/projectSettings/localSettings.
public enum SessionPermissionFilter {
    /// The session-only subset of `updates`, rebuilt with `destination: "session"`.
    public static func sessionOnly(_ updates: [PermissionUpdate]) -> [PermissionUpdate] {
        updates.compactMap { update in
            switch update.type {
            case "addRules":
                // Decision: "Allow for session" never adds deny/ask rules.
                guard update.behavior == "allow", let rules = update.rules, !rules.isEmpty else { return nil }
                return PermissionUpdate(type: "addRules", rules: rules, behavior: "allow", destination: "session")
            case "addDirectories":
                guard let directories = update.directories, !directories.isEmpty else { return nil }
                return PermissionUpdate(type: "addDirectories", directories: directories, destination: "session")
            default:
                return nil
            }
        }
    }
}
