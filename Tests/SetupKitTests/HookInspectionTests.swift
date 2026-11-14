import Foundation
import HookMeUpCore
import Testing

@testable import SetupKit

private let hook = "/Users/me/Applications/Hook Me Up.app/Contents/MacOS/hook-me-up"
private let allEvents = ["PermissionRequest", "Notification", "Stop", "UserPromptSubmit", "SessionEnd"]

private func json(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

private func installed(at path: String = hook, into settings: JSONValue = .object([:])) throws -> JSONValue {
    try SettingsMerger.install(into: settings, hookPath: path, permissionTimeout: 600)
}

/// Removes the handlers of `event` from `settings`.
private func dropping(_ event: String, from settings: JSONValue) -> JSONValue {
    guard var root = settings.objectValue, var hooks = root["hooks"]?.objectValue else { return settings }
    hooks[event] = nil
    root["hooks"] = .object(hooks)
    return .object(root)
}

@Suite struct HookInspectionTests {
    @Test func allFiveEventsInstalled() throws {
        let result = SettingsMerger.inspect(settings: try installed(), hookPath: hook)
        #expect(result.installed == allEvents)
        #expect(result.missing.isEmpty)
        #expect(result.duplicated.isEmpty)
        #expect(result.otherPaths.isEmpty)
        #expect(!result.allHooksDisabled)
    }

    @Test func nothingInstalled() throws {
        let result = SettingsMerger.inspect(settings: try json(#"{"model": "opus"}"#), hookPath: hook)
        #expect(result.installed.isEmpty)
        #expect(result.missing == allEvents)
    }

    @Test func aMissingEventIsReported() throws {
        let result = SettingsMerger.inspect(settings: dropping("Stop", from: try installed()), hookPath: hook)
        #expect(result.missing == ["Stop"])
        #expect(result.installed == ["PermissionRequest", "Notification", "UserPromptSubmit", "SessionEnd"])
    }

    @Test func wrongArgumentsDoNotCount() throws {
        let settings = try json(
            #"{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "'\#(hook)' clear"}]}]}}"#)
        let result = SettingsMerger.inspect(settings: settings, hookPath: hook)
        #expect(result.missing.contains("Stop"))
        #expect(result.otherPaths.isEmpty)
    }

    @Test func anyPermissionTimeoutCounts() throws {
        let settings = try SettingsMerger.install(into: .object([:]), hookPath: hook, permissionTimeout: 120)
        #expect(SettingsMerger.inspect(settings: settings, hookPath: hook).missing.isEmpty)
    }

    @Test func hooksAtAnotherPathAreReportedNotCounted() throws {
        let other = "/opt/homebrew/opt/hook-me-up/Hook Me Up.app/Contents/MacOS/hook-me-up"
        let result = SettingsMerger.inspect(settings: try installed(at: other), hookPath: hook)
        #expect(result.installed.isEmpty)
        #expect(result.missing == allEvents)
        #expect(result.otherPaths == [other])
        #expect(result.duplicated.isEmpty)
    }

    @Test func twoInstallationsAreDuplicates() throws {
        let other = "/Users/me/old/HookMeUp.app/Contents/MacOS/hook-me-up"
        let both = try installed(at: hook, into: try installed(at: other))
        let result = SettingsMerger.inspect(settings: both, hookPath: hook)
        #expect(result.missing.isEmpty)
        #expect(result.otherPaths == [other])
        #expect(result.duplicated == allEvents.sorted())
    }

    @Test func theSameHookTwiceInOneEventIsADuplicate() throws {
        let settings = try json(
            #"""
            {"hooks": {"Stop": [
              {"hooks": [{"type": "command", "command": "'\#(hook)' finished"}]},
              {"hooks": [{"type": "command", "command": "\"\#(hook)\" finished"}]}
            ]}}
            """#)
        let result = SettingsMerger.inspect(settings: settings, hookPath: hook)
        #expect(result.duplicated == ["Stop"])
        #expect(result.installed == ["Stop"])
    }

    @Test func pathsAreComparedThroughTheCanonicalPath() throws {
        // Homebrew: settings name the stable opt path, which links to the versioned keg.
        let opt = "/opt/homebrew/opt/hook-me-up/Hook Me Up.app/Contents/MacOS/hook-me-up"
        let keg = "/opt/homebrew/Cellar/hook-me-up/0.2.0/Hook Me Up.app/Contents/MacOS/hook-me-up"
        let resolve: (String) -> String = {
            $0.replacingOccurrences(of: "/opt/hook-me-up/", with: "/Cellar/hook-me-up/0.2.0/")
        }
        let result = SettingsMerger.inspect(settings: try installed(at: opt), hookPath: keg, canonicalPath: resolve)
        #expect(result.missing.isEmpty)
        #expect(result.otherPaths.isEmpty)
        // Without resolving, the same settings point elsewhere.
        #expect(SettingsMerger.inspect(settings: try installed(at: opt), hookPath: keg).otherPaths == [opt])
    }

    @Test func aRealSymlinkResolves() throws {
        let tree = try TempTree()
        try tree.file("keg/Hook Me Up.app/Contents/MacOS/hook-me-up", "#!/bin/sh\n")
        try FileManager.default.createSymbolicLink(
            atPath: tree.path("opt"), withDestinationPath: tree.path("keg"))
        let viaLink = tree.path("opt/Hook Me Up.app/Contents/MacOS/hook-me-up")
        let real = tree.path("keg/Hook Me Up.app/Contents/MacOS/hook-me-up")
        let resolve: (String) -> String = { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
        let result = SettingsMerger.inspect(
            settings: try installed(at: viaLink), hookPath: real, canonicalPath: resolve)
        #expect(result.missing.isEmpty)
        #expect(result.otherPaths.isEmpty)
    }

    @Test func disableAllHooksIsReported() throws {
        guard var root = try installed().objectValue else { throw CocoaError(.coderInvalidValue) }
        root["disableAllHooks"] = .bool(true)
        let result = SettingsMerger.inspect(settings: .object(root), hookPath: hook)
        #expect(result.allHooksDisabled)
        #expect(result.missing.isEmpty)
        #expect(
            !SettingsMerger.inspect(settings: try json(#"{"disableAllHooks": false}"#), hookPath: hook).allHooksDisabled
        )
    }

    @Test func foreignHooksAndOddShapesAreIgnored() throws {
        let settings = try json(
            #"""
            {"hooks": {
              "Stop": [{"hooks": [{"type": "command", "command": "say done"}, {"type": "prompt", "prompt": "x"}]}],
              "PreToolUse": "not an array",
              "SessionEnd": [{"matcher": "x"}, 3, {"hooks": [{"command": "'unterminated"}]}]
            }}
            """#)
        let result = SettingsMerger.inspect(settings: settings, hookPath: hook)
        #expect(result.missing == allEvents)
        #expect(result.otherPaths.isEmpty)
        #expect(result.duplicated.isEmpty)
    }

    @Test func aHandlerSetUpDifferentlyIsReportedButCounts() throws {
        let q = "'\(hook)'"
        let settings = try json(
            #"""
            {"hooks": {
              "PermissionRequest": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "\#(q) permission --timeout 600"}]}],
              "Notification": [{"matcher": "", "hooks": [{"type": "command", "command": "\#(q) notify"}]}],
              "Stop": [{"hooks": [{"type": "prompt", "command": "\#(q) finished"}]}],
              "UserPromptSubmit": [{"matcher": "*", "hooks": [{"type": "command", "command": "\#(q) clear"}]}],
              "SessionEnd": [{"matcher": "logout", "hooks": [{"command": "\#(q) clear"}]}]
            }}
            """#)
        let result = SettingsMerger.inspect(settings: settings, hookPath: hook)
        #expect(result.missing.isEmpty)
        #expect(
            result.differences == [
                .init(event: "PermissionRequest", detail: #"matcher "Bash", not "" (every tool)"#),
                .init(event: "Notification", detail: #"matcher "", not "elicitation_dialog""#),
                .init(event: "Stop", detail: #"type "prompt", not "command""#),
                .init(event: "SessionEnd", detail: #"type missing, not "command""#),
            ])
        // As install writes them, or "*" / no matcher for the match-everything events: no differences.
        #expect(SettingsMerger.inspect(settings: try installed(), hookPath: hook).differences.isEmpty)
    }

    @Test func aCorrectCopyOfAnEventHidesAnOddOne() throws {
        var settings = try installed()
        let odd = try json(
            #"{"matcher": "", "hooks": [{"type": "command", "command": "'\#(hook)' notify"}]}"#)
        if var root = settings.objectValue, var hooks = root["hooks"]?.objectValue,
            var groups = hooks["Notification"]?.arrayValue
        {
            groups.append(odd)
            hooks["Notification"] = .array(groups)
            root["hooks"] = .object(hooks)
            settings = .object(root)
        }
        let result = SettingsMerger.inspect(settings: settings, hookPath: hook)
        #expect(result.differences.isEmpty)
        #expect(result.duplicated == ["Notification"])
    }

    @Test func installReplacesOurHookSpelledThroughASymlink() throws {
        let opt = "/opt/homebrew/opt/hook-me-up/Hook Me Up.app/Contents/MacOS/hook-me-up"
        let keg = "/opt/homebrew/Cellar/hook-me-up/0.2.0/Hook Me Up.app/Contents/MacOS/hook-me-up"
        let resolve: (String) -> String = {
            $0.replacingOccurrences(of: "/opt/hook-me-up/", with: "/Cellar/hook-me-up/0.2.0/")
        }
        let viaOpt = try installed(at: opt)
        let again = try SettingsMerger.install(
            into: viaOpt, hookPath: keg, permissionTimeout: 600, canonicalPath: resolve)
        let result = SettingsMerger.inspect(settings: again, hookPath: keg, canonicalPath: resolve)
        #expect(result.duplicated.isEmpty)
        #expect(result.missing.isEmpty)
        #expect(!again.pretty().contains("/opt/hook-me-up/"))
        // Without the canonicalizer they are different hooks, and both stay.
        let both = try SettingsMerger.install(into: viaOpt, hookPath: keg, permissionTimeout: 600)
        #expect(SettingsMerger.inspect(settings: both, hookPath: keg).duplicated.count == 5)
    }

    @Test func uninstallRemovesOurHookHoweverItIsQuoted() throws {
        let other = "/Users/me/Old Copy/HookMeUp.app/Contents/MacOS/hook-me-up"
        let settings = try json(
            #"""
            {"hooks": {
              "Stop": [{"hooks": [
                {"type": "command", "command": "\"\#(other)\" finished"},
                {"type": "command", "command": "say done"}
              ]}],
              "SessionEnd": [{"hooks": [{"type": "command", "command": "/Users/me/Old\\ Copy/HookMeUp.app/Contents/MacOS/hook-me-up clear"}]}],
              "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "'\#(other)'"}]}]
            }}
            """#)
        let removed = SettingsMerger.uninstall(from: settings, hookPath: other)
        #expect(
            removed
                == (try json(
                    #"{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "say done"}]}]}}"#)))
        // A program that only starts with the same path is someone else's.
        let longer = try json(
            #"{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "'\#(other)-wrapper' finished"}]}]}}"#)
        #expect(SettingsMerger.uninstall(from: longer, hookPath: other) == longer)
    }

    @Test func commandsSplitLikeTheShell() {
        #expect(SettingsMerger.splitCommand("'/a b/hook-me-up' notify")! == ("/a b/hook-me-up", "notify"))
        #expect(SettingsMerger.splitCommand(#"'/it'\''s/hook-me-up' clear"#)! == ("/it's/hook-me-up", "clear"))
        #expect(
            SettingsMerger.splitCommand(#""/a \"b\"/hook-me-up"  finished "#)! == (#"/a "b"/hook-me-up"#, "finished"))
        #expect(SettingsMerger.splitCommand(#"/a\ b/hook-me-up"#)! == ("/a b/hook-me-up", ""))
        #expect(SettingsMerger.splitCommand("  ") == nil)
        #expect(SettingsMerger.splitCommand("'open") == nil)
        #expect(SettingsMerger.splitCommand(#""open"#) == nil)
    }

    /// Unquoting follows bash: inside double quotes a backslash goes only before $, `,
    /// ", \ or a newline; outside quotes before anything; backslash-newline continues.
    @Test func commandsUnquoteExactlyLikeBash() {
        func program(_ command: String) -> String? { SettingsMerger.splitCommand(command)?.program }
        #expect(program(#""/a/MacOS/hook\-me-up" x"#) == #"/a/MacOS/hook\-me-up"#)  // kept inside quotes
        #expect(program(#"/a/MacOS/hook\-me-up x"#) == "/a/MacOS/hook-me-up")  // removed outside
        #expect(program(#""/a/\$HOME/\`x\`/\\/\"q\"""#) == #"/a/$HOME/`x`/\/"q""#)
        #expect(program("\"/a/hoo\\\nk-me-up\" x") == "/a/hook-me-up")  // continuation in quotes
        #expect(program("/a/hoo\\\nk-me-up x") == "/a/hook-me-up")  // and outside
        #expect(program("\\\n /a/b x") == "/a/b")  // before the word
        #expect(program(#"/a/b\"#) == "/a/b")  // bash drops a backslash at the very end
        #expect(program("/a/b;echo x") == "/a/b")
        #expect(program("/a/b|cat") == "/a/b")
        #expect(program("# /a/b finished") == nil)
        #expect(program("; /a/b") == nil)
        #expect(program(#""""#) == nil)
        #expect(SettingsMerger.splitCommand("/a/b \\\n  finished\n")?.arguments == "finished")
    }

    @Test func aBackslashKeptInsideDoubleQuotesIsAnotherProgram() throws {
        let escaped = hook.replacingOccurrences(of: "hook-me-up", with: #"hook\\-me-up"#)
        let settings = try json(
            #"{"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "\"\#(escaped)\" finished"}]}]}}"#)
        let result = SettingsMerger.inspect(settings: settings, hookPath: hook)
        #expect(result.installed.isEmpty)
        #expect(result.otherPaths.isEmpty)  // not even a hook-me-up handler
        #expect(SettingsMerger.uninstall(from: settings, hookPath: hook) == settings)
    }

    @Test func aProgramThatIsNotAnAbsolutePathIsNeverOurs() throws {
        let everythingIsOurs: (String) -> String = { _ in hook }
        let relative = try json(
            #"""
            {"hooks": {
              "Stop": [{"hooks": [{"type": "command", "command": "hook-me-up finished"}]}],
              "SessionEnd": [{"hooks": [{"type": "command", "command": "Hook\\ Me\\ Up.app/Contents/MacOS/hook-me-up clear"}]}]
            }}
            """#)
        #expect(SettingsMerger.uninstall(from: relative, hookPath: hook, canonicalPath: everythingIsOurs) == relative)
        let result = SettingsMerger.inspect(settings: relative, hookPath: hook, canonicalPath: everythingIsOurs)
        #expect(result.installed.isEmpty)
        #expect(result.otherPaths == ["Hook Me Up.app/Contents/MacOS/hook-me-up"])
        // install adds ours next to them and leaves them alone.
        let added = try SettingsMerger.install(
            into: relative, hookPath: hook, permissionTimeout: 600, canonicalPath: everythingIsOurs)
        #expect(added["hooks"]?["Stop"]?.arrayValue?.count == 2)
    }

    @Test func aPathWithAQuoteRoundTrips() throws {
        let odd = "/Users/o'brien/Applications/Hook Me Up.app/Contents/MacOS/hook-me-up"
        #expect(SettingsMerger.inspect(settings: try installed(at: odd), hookPath: odd).missing.isEmpty)
    }
}
