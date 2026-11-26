import Foundation
import HookMeUpCore
import Testing

@testable import SetupKit

private let hook = "/home/me/Applications/HookMeUp.app/Contents/MacOS/hook-me-up"

private func json(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

/// Settings with foreign hooks and keys, shaped like a real ~/.claude/settings.json.
private let foreign = #"""
    {
      "model": "opus",
      "env": {"FOO": "bar"},
      "permissions": {"allow": ["Bash(git status)"], "defaultMode": "auto"},
      "hooks": {
        "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "/usr/local/bin/audit.sh"}]}],
        "Stop": [{"hooks": [{"type": "command", "command": "say done", "timeout": 5}]}]
      },
      "statusLine": {"type": "command", "command": "~/.claude/status.sh"}
    }
    """#

@Suite struct SettingsMergerTests {
    @Test func installIntoEmptyAddsAllFiveEvents() throws {
        let result = try SettingsMerger.install(into: .object([:]), hookPath: hook, permissionTimeout: 600)
        let q = "'\(hook)'"
        #expect(
            result
                == (try json(
                    #"""
                    {"hooks": {
                      "PermissionRequest": [{"matcher": "", "hooks": [{"type": "command", "command": "\#(q) permission --timeout 600", "timeout": 600}]}],
                      "Notification": [{"matcher": "elicitation_dialog", "hooks": [{"type": "command", "command": "\#(q) notify", "timeout": 10}]}],
                      "Stop": [{"hooks": [{"type": "command", "command": "\#(q) finished", "timeout": 10}]}],
                      "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "\#(q) clear", "timeout": 10}]}],
                      "SessionEnd": [{"hooks": [{"type": "command", "command": "\#(q) clear", "timeout": 10}]}]
                    }}
                    """#)))
        // No idle_prompt, no permission_prompt (would duplicate), no SubagentStop.
        #expect(!result.pretty().contains("idle_prompt"))
        #expect(!result.pretty().contains("permission_prompt"))
        #expect(result["hooks"]?["SubagentStop"] == nil)
    }

    @Test func installPreservesForeignHooksAndKeys() throws {
        let original = try json(foreign)
        let result = try SettingsMerger.install(into: original, hookPath: hook, permissionTimeout: 600)
        for key in ["model", "env", "permissions", "statusLine"] {
            #expect(result[key] == original[key], "\(key)")
        }
        #expect(result["hooks"]?["PreToolUse"] == original["hooks"]?["PreToolUse"])
        let stop = try #require(result["hooks"]?["Stop"]?.arrayValue)
        #expect(stop.count == 2)
        #expect(stop.first == original["hooks"]?["Stop"]?.arrayValue?.first)  // foreign group untouched, first
        #expect(stop.last?["hooks"]?.arrayValue?.first?["command"] == .string("'\(hook)' finished"))
    }

    @Test func installTwiceIsIdempotent() throws {
        let original = try json(foreign)
        let once = try SettingsMerger.install(into: original, hookPath: hook, permissionTimeout: 600)
        let twice = try SettingsMerger.install(into: once, hookPath: hook, permissionTimeout: 600)
        #expect(twice == once)
        // Re-installing with another timeout replaces ours instead of adding a second set.
        let changed = try SettingsMerger.install(into: once, hookPath: hook, permissionTimeout: 300)
        #expect(changed["hooks"]?["PermissionRequest"]?.arrayValue?.count == 1)
    }

    @Test func uninstallRemovesOnlyOurs() throws {
        let original = try json(foreign)
        let installed = try SettingsMerger.install(into: original, hookPath: hook, permissionTimeout: 600)
        #expect(SettingsMerger.uninstall(from: installed, hookPath: hook) == original)  // exact restore
        #expect(
            SettingsMerger.uninstall(
                from: try SettingsMerger.install(into: .object([:]), hookPath: hook, permissionTimeout: 600),
                hookPath: hook) == .object([:]))

        // A group shared with a foreign handler keeps the foreign one.
        let mixed = try json(
            #"""
            {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "say done"},
                                           {"type": "command", "command": "'\#(hook)' finished", "timeout": 10}]}]}}
            """#)
        #expect(
            SettingsMerger.uninstall(from: mixed, hookPath: hook)
                == (try json(
                    #"""
                    {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "say done"}]}]}}
                    """#)))
    }

    @Test func uninstallKeepsAnOriginallyEmptyHooksObject() throws {
        // exact restore of `"hooks": {}` (install records that it existed).
        let original = try json(#"{"model": "opus", "hooks": {}}"#)
        #expect(SettingsMerger.hasHooksObject(original))
        let installed = try SettingsMerger.install(into: original, hookPath: hook, permissionTimeout: 600)
        #expect(SettingsMerger.uninstall(from: installed, hookPath: hook, keepEmptyHooks: true) == original)
        // Without "hooks" originally, the emptied object goes away as before.
        let bare = try json(#"{"model": "opus"}"#)
        #expect(!SettingsMerger.hasHooksObject(bare))
        let installedBare = try SettingsMerger.install(into: bare, hookPath: hook, permissionTimeout: 600)
        #expect(SettingsMerger.uninstall(from: installedBare, hookPath: hook, keepEmptyHooks: false) == bare)
    }

    @Test func uninstallOnCleanIsNoop() throws {
        let original = try json(foreign)
        #expect(SettingsMerger.uninstall(from: original, hookPath: hook) == original)
        let emptyContainers = try json(#"{"hooks": {"Stop": [], "PreToolUse": [{"hooks": []}]}}"#)
        #expect(SettingsMerger.uninstall(from: emptyContainers, hookPath: hook) == emptyContainers)
        // Another copy of the hook at a different path is not ours.
        let other = try json(
            #"{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "'/opt/hook-me-up' finished"}]}]}}"#)
        #expect(SettingsMerger.uninstall(from: other, hookPath: hook) == other)
    }

    @Test func invalidJSONRefused() throws {
        let tree = try TempTree()
        for (name, text) in [("bad.json", "{ not json"), ("array.json", "[1, 2]"), ("empty.json", "")] {
            try tree.file(name, text)
            #expect(throws: (any Error).self) { try SettingsFile.load(URL(fileURLWithPath: tree.path(name))) }
        }
        #expect(throws: SettingsMergerError.self) {
            try SettingsMerger.install(into: try json(#"{"hooks": []}"#), hookPath: hook, permissionTimeout: 600)
        }
        #expect(throws: SettingsMergerError.self) {
            try SettingsMerger.install(
                into: try json(#"{"hooks": {"Stop": {"oops": 1}}}"#), hookPath: hook, permissionTimeout: 600)
        }
        // A missing file is an empty configuration.
        #expect(try SettingsFile.load(URL(fileURLWithPath: tree.path("missing.json"))) == .object([:]))
    }

    @Test func timeoutWrittenFromConfig() throws {
        let result = try SettingsMerger.install(into: .object([:]), hookPath: hook, permissionTimeout: 900)
        let handler = result["hooks"]?["PermissionRequest"]?.arrayValue?.first?["hooks"]?.arrayValue?.first
        #expect(handler?["timeout"] == .number(900))
        #expect(handler?["command"] == .string("'\(hook)' permission --timeout 900"))
    }

    @Test func pathWithSpacesQuoted() throws {
        let spaced = "/home/me/My Apps/Hook Me Up.app/Contents/MacOS/hook-me-up"
        let quoted = "/home/me/it's here/hook-me-up"
        let result = try SettingsMerger.install(into: .object([:]), hookPath: spaced, permissionTimeout: 600)
        #expect(
            result["hooks"]?["Stop"]?.arrayValue?.first?["hooks"]?.arrayValue?.first?["command"]
                == .string("'/home/me/My Apps/Hook Me Up.app/Contents/MacOS/hook-me-up' finished"))
        #expect(SettingsMerger.shellQuote(quoted) == #"'/home/me/it'\''s here/hook-me-up'"#)
        let withQuote = try SettingsMerger.install(into: .object([:]), hookPath: quoted, permissionTimeout: 600)
        #expect(SettingsMerger.uninstall(from: withQuote, hookPath: quoted) == .object([:]))
    }

    @Test func diffShowsAddedEntries() throws {
        let original = try json(foreign)
        let installed = try SettingsMerger.install(into: original, hookPath: hook, permissionTimeout: 600)
        let diff = SettingsMerger.diff(old: original, new: installed)
        let added = diff.split(separator: "\n").filter { $0.hasPrefix("+ ") }
        let removed = diff.split(separator: "\n").filter { $0.hasPrefix("- ") }
        #expect(removed.isEmpty)
        #expect(added.contains { $0.contains(#""PermissionRequest" : ["#) })
        #expect(added.contains { $0.contains("permission --timeout 600") })
        #expect(added.contains { $0.contains(#""elicitation_dialog""#) })
        #expect(!added.contains { $0.contains("audit.sh") })  // unchanged foreign hook is not "added"
        #expect(SettingsMerger.diff(old: original, new: original) == "")
        let back = SettingsMerger.diff(old: installed, new: original)
        #expect(back.split(separator: "\n").contains { $0.hasPrefix("- ") && $0.contains("permission --timeout 600") })
    }
}
