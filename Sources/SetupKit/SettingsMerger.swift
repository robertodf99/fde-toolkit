import Foundation
import HookMeUpCore

/// Adds or removes our hooks in a Claude Code settings document, leaving everything
/// else as it was. Our handlers are recognised only by their exact (quoted) hook path.
public enum SettingsMerger {
    /// Timeout (s) for the fire-and-forget hooks: they finish in milliseconds.
    static let fireAndForgetTimeout = 10

    private struct Spec {
        let event: String
        let matcher: String?
        let arguments: String
        let timeout: Int
    }

    /// PermissionRequest (all tools), Notification elicitation_dialog (no idle_prompt,
    /// no permission_prompt), Stop -> finished, UserPromptSubmit / SessionEnd -> clear.
    private static func specs(permissionTimeout: Int) -> [Spec] {
        [
            Spec(
                event: "PermissionRequest", matcher: "", arguments: "permission --timeout \(permissionTimeout)",
                timeout: permissionTimeout),
            Spec(
                event: "Notification", matcher: "elicitation_dialog", arguments: "notify", timeout: fireAndForgetTimeout
            ),
            Spec(event: "Stop", matcher: nil, arguments: "finished", timeout: fireAndForgetTimeout),
            Spec(event: "UserPromptSubmit", matcher: nil, arguments: "clear", timeout: fireAndForgetTimeout),
            Spec(event: "SessionEnd", matcher: nil, arguments: "clear", timeout: fireAndForgetTimeout),
        ]
    }

    /// Single-quoted for the shell: a path with spaces or quotes stays one word.
    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// Settings with our hooks (re-installing replaces ours, so it is idempotent).
    public static func install(into settings: JSONValue, hookPath: String, permissionTimeout: Int) throws -> JSONValue {
        guard var root = uninstall(from: settings, hookPath: hookPath).objectValue else {
            throw SettingsMergerError.notAnObject
        }
        var hooks: [String: JSONValue] = [:]
        if let existing = root["hooks"] {
            guard let object = existing.objectValue else { throw SettingsMergerError.unexpectedShape("hooks") }
            hooks = object
        }
        for spec in specs(permissionTimeout: permissionTimeout) {
            var groups: [JSONValue] = []
            if let existing = hooks[spec.event] {
                guard let array = existing.arrayValue else {
                    throw SettingsMergerError.unexpectedShape("hooks.\(spec.event)")
                }
                groups = array
            }
            var group: [String: JSONValue] = [
                "hooks": .array([
                    .object([
                        "type": "command",
                        "command": .string(shellQuote(hookPath) + " " + spec.arguments),
                        "timeout": .number(Double(spec.timeout)),
                    ])
                ])
            ]
            if let matcher = spec.matcher { group["matcher"] = .string(matcher) }
            groups.append(.object(group))
            hooks[spec.event] = .array(groups)
        }
        root["hooks"] = .object(hooks)
        return .object(root)
    }

    /// True when the settings have a `hooks` object (install records this, so uninstall
    /// can restore an originally empty `"hooks": {}` exactly).
    public static func hasHooksObject(_ settings: JSONValue) -> Bool {
        settings["hooks"]?.objectValue != nil
    }

    /// Settings without our hooks. Only containers that our removal emptied are
    /// dropped; anything with an unexpected shape is left exactly as it is. An emptied
    /// `hooks` object is kept when `keepEmptyHooks` (it existed before install).
    public static func uninstall(from settings: JSONValue, hookPath: String, keepEmptyHooks: Bool = false) -> JSONValue
    {
        guard var root = settings.objectValue, let hooks = root["hooks"]?.objectValue else { return settings }
        let prefix = shellQuote(hookPath) + " "
        func isOurs(_ handler: JSONValue) -> Bool {
            handler["command"]?.stringValue?.hasPrefix(prefix) == true
        }

        var newHooks = hooks
        var changedAny = false
        for (event, value) in hooks {
            guard let groups = value.arrayValue else { continue }
            var newGroups: [JSONValue] = []
            var changed = false
            for group in groups {
                guard var object = group.objectValue, let handlers = object["hooks"]?.arrayValue else {
                    newGroups.append(group)
                    continue
                }
                let kept = handlers.filter { !isOurs($0) }
                if kept.count == handlers.count {
                    newGroups.append(group)
                    continue
                }
                changed = true
                if !kept.isEmpty {
                    object["hooks"] = .array(kept)
                    newGroups.append(.object(object))
                }
            }
            guard changed else { continue }
            changedAny = true
            if newGroups.isEmpty { newHooks[event] = nil } else { newHooks[event] = .array(newGroups) }
        }
        guard changedAny else { return settings }
        root["hooks"] = newHooks.isEmpty && !keepEmptyHooks ? nil : .object(newHooks)
        return .object(root)
    }

    /// Line diff of the two documents as they would be written ("+ " added, "- "
    /// removed, "  " context, two lines around each change). A comma that only appears
    /// because a sibling was added is not shown as a change.
    public static func diff(old: JSONValue, new: JSONValue, context: Int = 2) -> String {
        diff(oldText: old.pretty(), newText: new.pretty(), context: context)
    }

    /// Line diff of two texts as they are (e.g. the settings file on disk and what would
    /// be written), same format as `diff(old:new:)`.
    public static func diff(oldText: String, newText: String, context: Int = 2) -> String {
        func lines(_ text: String) -> [String] {
            var result = text.components(separatedBy: "\n")
            if result.last == "" { result.removeLast() }  // final newline
            return result
        }
        let a = lines(oldText)
        let b = lines(newText)
        func key(_ line: String) -> String { line.hasSuffix(",") ? String(line.dropLast()) : line }
        let ka = a.map(key)
        let kb = b.map(key)

        // Longest common subsequence table.
        var table = Array(repeating: Array(repeating: 0, count: kb.count + 1), count: ka.count + 1)
        for i in stride(from: ka.count - 1, through: 0, by: -1) {
            for j in stride(from: kb.count - 1, through: 0, by: -1) {
                table[i][j] = ka[i] == kb[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        enum Op {
            case same(String)
            case add(String)
            case remove(String)
        }
        var ops: [Op] = []
        var i = 0
        var j = 0
        while i < ka.count || j < kb.count {
            if i < ka.count, j < kb.count, ka[i] == kb[j] {
                ops.append(.same(b[j]))
                i += 1
                j += 1
            } else if j < kb.count, i == ka.count || table[i][j + 1] >= table[i + 1][j] {
                ops.append(.add(b[j]))
                j += 1
            } else {
                ops.append(.remove(a[i]))
                i += 1
            }
        }

        let changed = ops.indices.filter { if case .same = ops[$0] { return false } else { return true } }
        guard !changed.isEmpty else { return "" }
        var show = Set<Int>()
        for index in changed {
            for k in max(0, index - context)...min(ops.count - 1, index + context) { show.insert(k) }
        }
        var lines: [String] = []
        var previous: Int?
        for index in show.sorted() {
            if let previous, index != previous + 1 { lines.append("…") }
            switch ops[index] {
            case .same(let line): lines.append("  " + line)
            case .add(let line): lines.append("+ " + line)
            case .remove(let line): lines.append("- " + line)
            }
            previous = index
        }
        return lines.joined(separator: "\n")
    }
}
