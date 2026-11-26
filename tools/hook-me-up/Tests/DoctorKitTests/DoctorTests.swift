import Foundation
import HookMeUpCore
import Testing

@testable import DoctorKit

private let home = "/Users/me"
private let app = "/Users/me/Applications/Hook Me Up.app"
private let settingsPath = "/Users/me/.claude/settings.json"
private let socketPath = "/Users/me/Library/Application Support/hook-me-up/agent.sock"
private let installerPlist = "/Users/me/Library/LaunchAgents/io.github.robertodf99.hook-me-up.plist"
private let installerCommand =
    "curl -fsSL https://raw.githubusercontent.com/robertodf99/fde-toolkit/main/install.sh | bash"

/// Files, links, launchd and the agent, all made up.
final class FakeProbe: DoctorProbe {
    var files: [String: Data] = [:]
    var executables: Set<String> = []
    var folders: Set<String> = []
    /// Symlinks: path prefix -> what it resolves to.
    var links: [String: String] = [:]
    var launchStates: [String: LaunchAgentState] = [:]
    var reply: AgentReply = .noSocket
    private(set) var queried: [String] = []

    func contents(of path: String) -> Data? { files[path] }
    func isExecutable(_ path: String) -> Bool { executables.contains(path) }
    func exists(_ path: String) -> Bool {
        files[path] != nil || folders.contains(path) || executables.contains(path)
            || executables.contains { $0.hasPrefix(path + "/") }
    }
    func canonicalPath(_ path: String) -> String {
        for (link, target) in links where path == link || path.hasPrefix(link + "/") {
            return target + path.dropFirst(link.count)
        }
        return path
    }
    func launchAgentState(label: String) -> LaunchAgentState { launchStates[label] ?? .notLoaded }
    func queryAgent(socketPath: String, timeout: TimeInterval) -> AgentReply {
        queried.append(socketPath)
        return reply
    }
}

private func plist(_ object: [String: Any]) -> Data {
    // A fixed dictionary of property-list types always serializes.
    (try? PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)) ?? Data()
}

private func launchAgent(starting program: String) -> Data {
    plist(["Label": Doctor.installerLabel, "ProgramArguments": [program], "RunAtLoad": true])
}

private func hooks(at hook: String) -> Data {
    let q = "'" + hook + "'"
    let text = """
        {"model": "opus", "hooks": {
          "PermissionRequest": [{"matcher": "", "hooks": [{"type": "command", "command": "\(q) permission --timeout 600"}]}],
          "Notification": [{"matcher": "elicitation_dialog", "hooks": [{"type": "command", "command": "\(q) notify"}]}],
          "Stop": [{"hooks": [{"type": "command", "command": "\(q) finished"}]}],
          "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "\(q) clear"}]}],
          "SessionEnd": [{"hooks": [{"type": "command", "command": "\(q) clear"}]}]
        }}
        """
    return Data(text.utf8)
}

private func status(
    _ authorization: NotificationAuthorization.Status = .authorized,
    _ style: NotificationAuthorization.AlertStyle = .alert, version: String = "0.2.0", build: String = "0.2.0",
    paused: Bool = false
) -> AgentStatus {
    AgentStatus(
        version: version, build: build,
        notifications: NotificationAuthorization(status: authorization, alertStyle: style), paused: paused,
        pendingCount: 0)
}

/// An installer install that works: app, LaunchAgent, running agent, hooks, Alerts.
private func healthy(app: String = app) -> FakeProbe {
    let probe = FakeProbe()
    for executable in ["HookMeUp", "hook-me-up", "hook-me-up-setup"] {
        probe.executables.insert("\(app)/Contents/MacOS/\(executable)")
    }
    probe.files["\(app)/Contents/Info.plist"] = plist(
        ["CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "0.2.0"])
    probe.files[installerPlist] = launchAgent(starting: "\(app)/Contents/MacOS/HookMeUp")
    probe.files[settingsPath] = hooks(at: "\(app)/Contents/MacOS/hook-me-up")
    probe.launchStates[Doctor.installerLabel] = .running(pid: 4242)
    probe.reply = .status(status())
    return probe
}

private let realHome = Doctor.Options(
    home: home, isRealHome: true, app: app, settings: settingsPath, socket: socketPath, uid: 501)

private func run(_ probe: FakeProbe, _ options: Doctor.Options = realHome) -> DoctorReport {
    Doctor.run(options, probe: probe)
}

@Suite struct DoctorTests {
    @Test func aHealthyInstallPassesEverything() {
        let probe = healthy()
        let report = run(probe)
        #expect(
            report.checks.map(\.name) == [
                "App", "LaunchAgent", "Agent process", "Agent", "Agent version", "Hooks", "Notifications",
                "Notification style", "Pause", "Editor extension",
            ])
        #expect(report.checks.dropLast().allSatisfy { $0.result == .pass }, "\(report.rendered())")
        #expect(report.check("Editor extension")?.result == .info)
        #expect(report.exitCode == 0)
        #expect(probe.queried == [socketPath])
        #expect(report.check("App")?.detail == "Hook Me Up 0.2.0 (0.2.0) at \(app)")
        #expect(report.check("Agent process")?.detail == "running (pid 4242)")
        #expect(report.rendered().hasSuffix("\nNo problems found."))
    }

    // MARK: App and LaunchAgent

    @Test func aMissingAppFailsWithTheInstaller() {
        let probe = healthy()
        probe.executables = []
        let check = run(probe).check("App")
        #expect(check?.result == .fail)
        #expect(check?.detail == "no app at \(app)")
        #expect(check?.fix?.contains(installerCommand) == true)
        #expect(run(probe).exitCode == 1)
    }

    @Test func anIncompleteAppNamesWhatIsMissing() {
        let probe = healthy()
        probe.executables.remove("\(app)/Contents/MacOS/hook-me-up")
        #expect(run(probe).check("App")?.detail == "\(app) is incomplete (no hook-me-up)")
    }

    @Test func noLaunchAgentFails() {
        let probe = healthy()
        probe.files[installerPlist] = nil
        let report = run(probe)
        #expect(report.check("LaunchAgent")?.result == .fail)
        #expect(report.check("LaunchAgent")?.fix?.contains(installerCommand) == true)
        #expect(report.check("Agent process")?.result == .skipped)
        #expect(report.exitCode == 1)
    }

    @Test func aLaunchAgentForAnotherCopyFails() {
        let probe = healthy()
        probe.files[installerPlist] = launchAgent(starting: "/Applications/HookMeUp.app/Contents/MacOS/HookMeUp")
        let check = run(probe).check("LaunchAgent")
        #expect(check?.result == .fail)
        #expect(check?.detail.contains("starts /Applications/HookMeUp.app/Contents/MacOS/HookMeUp") == true)
    }

    @Test func anUnreadableLaunchAgentFails() {
        let probe = healthy()
        probe.files[installerPlist] = Data("not a plist".utf8)
        #expect(run(probe).check("LaunchAgent")?.result == .fail)
    }

    /// The app is checked at its real path, while the LaunchAgent and the hooks name it
    /// through a link to its folder: both still count as this app's.
    @Test func theLaunchAgentAndHooksMayNameTheAppThroughALink() {
        let real = "/Volumes/X/Applications/Hook Me Up.app"
        let probe = healthy(app: real)
        probe.links["/Users/me/Applications"] = "/Volumes/X/Applications"
        probe.files[installerPlist] = launchAgent(starting: "\(app)/Contents/MacOS/HookMeUp")
        probe.files[settingsPath] = hooks(at: "\(app)/Contents/MacOS/hook-me-up")
        var options = realHome
        options.app = real
        let report = run(probe, options)
        #expect(report.check("LaunchAgent")?.result == .pass, "\(report.rendered())")
        #expect(report.check("LaunchAgent")?.detail == "io.github.robertodf99.hook-me-up starts this app")
        #expect(report.check("Hooks")?.result == .pass, "\(report.rendered())")
        #expect(report.check("Hooks")?.detail == "all five events run \(real)/Contents/MacOS/hook-me-up")
        #expect(report.check("Other installation") == nil)
        #expect(report.exitCode == 0)
    }

    @Test func anUnloadedAgentFailsWithTheBootstrapCommand() {
        let probe = healthy()
        probe.launchStates = [:]
        let check = run(probe).check("Agent process")
        #expect(check?.result == .fail)
        #expect(check?.fix == "launchctl bootstrap gui/501 \(installerPlist)")
    }

    @Test func aLoadedAgentThatDoesNotRunFailsWithKickstart() {
        let probe = healthy()
        probe.launchStates[Doctor.installerLabel] = .notRunning
        let check = run(probe).check("Agent process")
        #expect(check?.result == .fail)
        #expect(check?.fix == "launchctl kickstart gui/501/io.github.robertodf99.hook-me-up")
    }

    @Test func launchctlTroubleOnlyWarns() {
        let probe = healthy()
        probe.launchStates[Doctor.installerLabel] = .unknown("launchctl print exited with 5")
        #expect(run(probe).check("Agent process")?.result == .warn)
    }

    // MARK: The running agent

    @Test func noAgentFailsAndSkipsWhatNeedsIt() {
        for reply in [AgentReply.noSocket, .notListening, .timedOut, .failed("the peer runs as uid 0, not 501")] {
            let probe = healthy()
            probe.reply = reply
            let report = run(probe)
            #expect(report.check("Agent")?.result == .fail, "\(reply)")
            #expect(report.check("Agent")?.fix?.contains(installerCommand) == true)
            for name in ["Agent version", "Notifications", "Notification style", "Pause"] {
                #expect(report.check(name)?.result == .skipped)
                #expect(report.check(name)?.detail == "not checked: the agent didn't answer")
            }
            #expect(report.exitCode == 1)
        }
    }

    @Test func anOlderAgentThatClosesWarnsToRestartIt() {
        let probe = healthy()
        probe.reply = .closedWithoutAnswer
        let report = run(probe)
        let check = report.check("Agent")
        #expect(check?.result == .warn)
        #expect(check?.detail == "the agent that runs is too old to answer status questions")
        #expect(check?.fix?.contains("Run the installer again") == true)
        #expect(report.exitCode == 0)
    }

    @Test func anotherAgentVersionWarns() {
        let probe = healthy()
        probe.reply = .status(status(version: "0.1.9", build: "0.1.9"))
        let check = run(probe).check("Agent version")
        #expect(check?.result == .warn)
        #expect(check?.detail == "the agent that runs is 0.1.9 (0.1.9); the app is 0.2.0 (0.2.0)")
    }

    // MARK: Hooks

    @Test func missingSettingsFailWithTheInstallCommand() {
        let probe = healthy()
        probe.files[settingsPath] = nil
        let check = run(probe).check("Hooks")
        #expect(check?.result == .fail)
        #expect(check?.detail == "\(settingsPath) doesn't exist, so there are no hooks")
        #expect(
            check?.fix?.hasSuffix(
                "'\(app)/Contents/MacOS/hook-me-up-setup' install --settings \(settingsPath)"
                    + " --hook '\(app)/Contents/MacOS/hook-me-up'") == true)
    }

    @Test func settingsWithoutOurHooksFail() {
        let probe = healthy()
        probe.files[settingsPath] = Data(#"{"model": "opus"}"#.utf8)
        let report = run(probe)
        #expect(report.check("Hooks")?.detail == "\(settingsPath) has none of Hook Me Up's hooks")
        #expect(report.exitCode == 1)
    }

    @Test func aMissingEventIsNamed() throws {
        let probe = healthy()
        let text = String(decoding: hooks(at: "\(app)/Contents/MacOS/hook-me-up"), as: UTF8.self)
        probe.files[settingsPath] = Data(
            text.replacingOccurrences(of: "\"Stop\"", with: "\"SubagentStop\"").utf8)
        let check = run(probe).check("Hooks")
        #expect(check?.result == .fail)
        #expect(check?.detail == "missing for Stop in \(settingsPath)")
    }

    @Test func invalidSettingsFail() {
        let probe = healthy()
        probe.files[settingsPath] = Data("{ not json".utf8)
        let check = run(probe).check("Hooks")
        #expect(check?.result == .fail)
        #expect(check?.detail == "\(settingsPath) is not a valid JSON object")
    }

    @Test func hooksOfAnotherCopyWarnWithHowToRemoveThem() {
        let probe = healthy()
        let other = "/Users/me/Downloads/HookMeUp.app/Contents/MacOS/hook-me-up"
        let ours = String(decoding: hooks(at: "\(app)/Contents/MacOS/hook-me-up"), as: UTF8.self)
        let theirs = #""Stop": [{"hooks": [{"type": "command", "command": "'\#(other)' finished"}]}, "#
        probe.files[settingsPath] = Data(
            ours.replacingOccurrences(of: #""Stop": ["#, with: theirs + "{\"x\": 1},").utf8)
        let report = run(probe)
        #expect(report.check("Hooks")?.result == .pass)
        let duplicate = report.check("Duplicate hooks")
        #expect(duplicate?.result == .warn)
        #expect(duplicate?.detail == "hook-me-up runs more than once for Stop, so their notifications show twice")
        let otherCopy = report.check("Other installation")
        #expect(otherCopy?.result == .warn)
        #expect(otherCopy?.detail == "\(settingsPath) also runs hook-me-up from \(other)")
        #expect(
            otherCopy?.fix?.hasSuffix(
                "'\(app)/Contents/MacOS/hook-me-up-setup' uninstall --settings \(settingsPath) --hook \(other)") == true
        )
        #expect(report.exitCode == 0)
    }

    /// Settings whose Stop event also runs each of `commands` (JSON-escaped), next to ours.
    private func withOtherStopHooks(_ commands: [String]) -> Data {
        let ours = String(decoding: hooks(at: "\(app)/Contents/MacOS/hook-me-up"), as: UTF8.self)
        let theirs = commands.map { #"{"hooks": [{"type": "command", "command": "\#($0)"}]}, "# }.joined()
        return Data(ours.replacingOccurrences(of: #""Stop": ["#, with: #""Stop": ["# + theirs).utf8)
    }

    /// A relative path, `~/…` or `$HOME/…`: the settings don't name a file, so `uninstall`
    /// (which takes an absolute path) can't remove them; the fix says to remove them by hand.
    @Test func hooksAtAPathThatIsNotAbsoluteCanOnlyBeRemovedByHand() {
        let relative = "HookMeUp.app/Contents/MacOS/hook-me-up"
        let tilde = "~/Applications/Hook Me Up.app/Contents/MacOS/hook-me-up"
        let home = "$HOME/Applications/Hook Me Up.app/Contents/MacOS/hook-me-up"
        let probe = healthy()
        probe.files[settingsPath] = withOtherStopHooks([
            "\(relative) finished", #"~/Applications/Hook\\ Me\\ Up.app/Contents/MacOS/hook-me-up finished"#,
            #"\"$HOME/Applications/Hook Me Up.app/Contents/MacOS/hook-me-up\" finished"#,
        ])
        let check = run(probe).check("Other installation")
        #expect(check?.result == .warn)
        #expect(check?.detail == "\(settingsPath) also runs hook-me-up from \(home), \(relative), \(tilde)")
        #expect(
            check?.fix == """
                If that copy is gone or unused, remove by hand from \(settingsPath):
                the entries that run \(home), which is not an absolute path
                the entries that run \(relative), which is not an absolute path
                the entries that run \(tilde), which is not an absolute path
                """)
    }

    /// An absolute path gets the uninstall command; the rest are removed by hand.
    @Test func otherHooksAtAbsoluteAndOtherPathsGetBothFixes() {
        let other = "/Users/me/Downloads/HookMeUp.app/Contents/MacOS/hook-me-up"
        let tilde = "~/Applications/Hook Me Up.app/Contents/MacOS/hook-me-up"
        let probe = healthy()
        probe.files[settingsPath] = withOtherStopHooks([
            "'\(other)' finished", #"~/Applications/Hook\\ Me\\ Up.app/Contents/MacOS/hook-me-up finished"#,
        ])
        let check = run(probe).check("Other installation")
        #expect(
            check?.fix == """
                If that copy is gone or unused, remove its hooks (shows the changes and asks first):
                '\(app)/Contents/MacOS/hook-me-up-setup' uninstall --settings \(settingsPath) --hook \(other)
                Remove by hand from \(settingsPath):
                the entries that run \(tilde), which is not an absolute path
                """)
    }

    @Test func disabledHooksFail() {
        let probe = healthy()
        let text = String(decoding: hooks(at: "\(app)/Contents/MacOS/hook-me-up"), as: UTF8.self)
        probe.files[settingsPath] = Data(
            text.replacingOccurrences(of: "{\"model\"", with: "{\"disableAllHooks\": true, \"model\"").utf8)
        let report = run(probe)
        let check = report.check("Hooks disabled")
        #expect(check?.result == .fail)
        #expect(check?.fix == "Remove \"disableAllHooks\": true from \(settingsPath).")
        #expect(report.exitCode == 1)
    }

    @Test func hooksSetUpDifferentlyWarnWithTheInstallCommand() {
        let probe = healthy()
        let text = String(decoding: hooks(at: "\(app)/Contents/MacOS/hook-me-up"), as: UTF8.self)
        probe.files[settingsPath] = Data(
            text.replacingOccurrences(of: #""matcher": "elicitation_dialog""#, with: #""matcher": """#).utf8)
        let report = run(probe)
        #expect(report.check("Hooks")?.result == .pass)
        let check = report.check("Hooks set up differently")
        #expect(check?.result == .warn)
        #expect(check?.detail.hasPrefix(#"Notification: matcher "", not "elicitation_dialog""#) == true)
        #expect(check?.fix?.contains("hook-me-up-setup' install --settings") == true)
        #expect(report.exitCode == 0)
    }

    // MARK: Notifications and pause

    @Test func stateFromANewerAgentWarns() {
        let probe = healthy()
        probe.reply = .status(status(.unknown, .unknown))
        let report = run(probe)
        #expect(report.check("Notifications")?.result == .warn)
        #expect(report.check("Notification style")?.result == .skipped)
        probe.reply = .status(status(.authorized, .unknown))
        #expect(run(probe).check("Notification style")?.result == .warn)
    }

    @Test func notificationsTurnedOffFail() {
        let probe = healthy()
        probe.reply = .status(status(.denied, .none))
        let report = run(probe)
        let check = report.check("Notifications")
        #expect(check?.result == .fail)
        #expect(check?.fix?.contains("System Settings > Notifications > Hook Me Up") == true)
        #expect(report.check("Notification style")?.result == .skipped)
        #expect(report.exitCode == 1)
    }

    @Test func anUnansweredPermissionPromptWarns() {
        let probe = healthy()
        probe.reply = .status(status(.notDetermined, .none))
        let report = run(probe)
        #expect(report.check("Notifications")?.result == .warn)
        #expect(report.check("Notifications")?.fix?.hasPrefix("Click Allow") == true)
        #expect(report.exitCode == 0)
    }

    @Test func provisionalCountsAsAllowed() {
        let probe = healthy()
        probe.reply = .status(status(.provisional, .alert))
        #expect(run(probe).check("Notifications")?.result == .pass)
    }

    @Test func bannersWarnAndNoStyleFails() {
        let probe = healthy()
        probe.reply = .status(status(.authorized, .banner))
        let banner = run(probe).check("Notification style")
        #expect(banner?.result == .warn)
        #expect(
            banner?.fix == "Set the style to Alerts in System Settings > Notifications > Hook Me Up.\n"
                + "To open it: '\(app)/Contents/MacOS/hook-me-up-setup' notifications --open-settings")
        #expect(run(probe).exitCode == 0)
        probe.reply = .status(status(.authorized, .none))
        #expect(run(probe).check("Notification style")?.result == .fail)
        #expect(run(probe).exitCode == 1)
    }

    @Test func aPauseIsInformationOnly() {
        let probe = healthy()
        probe.reply = .status(status(paused: true))
        let report = run(probe)
        #expect(report.check("Pause")?.result == .info)
        #expect(report.exitCode == 0)
        #expect(report.rendered().contains("INFO  Pause: paused"))
        #expect(report.rendered().contains("      Note: To end it now"))
    }

    // MARK: Editor extension

    private func registry(_ ids: [String]) -> Data {
        Data(
            ("[" + ids.map { #"{"identifier": {"id": "\#($0)"}, "version": "0.1.0"}"# }.joined(separator: ", ") + "]")
                .utf8)
    }

    private let vsix = "\(app)/Contents/Resources/hook-me-up.vsix"

    @Test func noEditorIsInformationOnly() {
        let report = run(healthy())
        let check = report.check("Editor extension")
        #expect(check?.result == .info)
        #expect(check?.detail == "none of VS Code, VS Code Insiders, Cursor or Windsurf has an extensions folder")
        #expect(check?.fix == nil)
        #expect(report.exitCode == 0)
        #expect(report.rendered().hasSuffix("\nNo problems found."))
    }

    @Test func editorsWithTheExtensionAreNamed() {
        let probe = healthy()
        probe.files["/Users/me/.vscode/extensions/extensions.json"] = registry([
            "ms-python.python", "hook-me-up.hook-me-up",
        ])
        probe.folders.insert("/Users/me/.vscode/extensions")
        probe.files["/Users/me/.cursor/extensions/extensions.json"] = registry(["Hook-Me-Up.Hook-Me-Up"])
        probe.folders.insert("/Users/me/.cursor/extensions")
        let check = run(probe).check("Editor extension")
        #expect(check?.result == .info)
        #expect(check?.detail == "installed in VS Code, Cursor")
        #expect(check?.fix == nil)
    }

    /// An editor without it (no registry, or one that can't be read, counts as without):
    /// still only information, with the command that adds it from this app.
    @Test func editorsWithoutTheExtensionGetTheCommandThatAddsIt() {
        let probe = healthy()
        probe.files[vsix] = Data("zip".utf8)
        probe.files["/Users/me/.vscode/extensions/extensions.json"] = registry(["hook-me-up.hook-me-up"])
        probe.folders.insert("/Users/me/.vscode/extensions")
        probe.folders.insert("/Users/me/.windsurf/extensions")
        probe.files["/Users/me/.cursor/extensions/extensions.json"] = Data("not json".utf8)
        probe.folders.insert("/Users/me/.cursor/extensions")
        let report = run(probe)
        let check = report.check("Editor extension")
        #expect(check?.result == .info)
        #expect(check?.detail == "installed in VS Code; not in Cursor, Windsurf")
        #expect(
            check?.fix == """
                Without it, a click focuses the editor's window but not the session's terminal. To add it:
                cursor --install-extension '\(vsix)'
                windsurf --install-extension '\(vsix)'
                then reload the editor's open windows.
                """)
        #expect(report.exitCode == 0)
        #expect(report.rendered().hasSuffix("\nNo problems found."))
    }

    @Test func anAppWithoutTheExtensionSaysSo() {
        let probe = healthy()
        probe.folders.insert("/Users/me/.vscode-insiders/extensions")
        let check = run(probe).check("Editor extension")
        #expect(check?.result == .info)
        #expect(check?.detail == "not in VS Code Insiders")
        #expect(check?.fix == "This app has no editor extension to add (\(vsix) is missing); update Hook Me Up.")
    }

    /// An oversized registry isn't read.
    @Test func anOversizedRegistryCountsAsWithout() {
        let probe = healthy()
        var big = registry(["hook-me-up.hook-me-up"])
        big.append(Data(repeating: 0x20, count: EditorExtension.maxRegistryBytes))
        probe.files["/Users/me/.vscode/extensions/extensions.json"] = big
        probe.folders.insert("/Users/me/.vscode/extensions")
        #expect(run(probe).check("Editor extension")?.detail == "not in VS Code")
    }

    // MARK: Another home (tests, the install harness)

    @Test func anotherHomeSkipsLaunchdAndTheAgent() {
        let probe = healthy()
        let options = Doctor.Options(
            home: home, isRealHome: false, app: app, settings: settingsPath, socket: nil, uid: 501)
        let report = run(probe, options)
        #expect(report.check("Agent process")?.result == .skipped)
        #expect(report.check("Agent")?.result == .skipped)
        #expect(report.check("Notifications")?.detail == "not checked: --home is not your home folder")
        #expect(probe.queried.isEmpty)
        #expect(report.exitCode == 0)
        // The fix keeps the installer's bookkeeping in that home too.
        probe.files[settingsPath] = nil
        #expect(
            run(probe, options).check("Hooks")?.fix?.hasSuffix(
                "--state '/Users/me/Library/Application Support/hook-me-up/setup-state.json'") == true)
    }

    // MARK: Options and parsing

    @Test func optionsComeFromTheAppThisProgramRunsFrom() {
        let probe = FakeProbe()
        // Run through a link: the app it links into (not the default app in the home).
        probe.links["/Users/me/bin/hook-me-up-setup"] = "/Applications/Hook Me Up.app/Contents/MacOS/hook-me-up-setup"
        let linked = Doctor.Options.resolve(
            home: nil, app: nil, settings: nil, socket: nil, executablePath: "/Users/me/bin/hook-me-up-setup",
            realHome: home, uid: 501, probe: probe)
        #expect(linked.app == "/Applications/Hook Me Up.app")
        #expect(linked.isRealHome)
        #expect(linked.settings == settingsPath)
        #expect(linked.socket == socketPath)

        let loose = Doctor.Options.resolve(
            home: "/tmp/fake", app: nil, settings: nil, socket: nil,
            executablePath: "/repo/.build/debug/hook-me-up-setup",
            realHome: home, uid: 501, probe: probe)
        #expect(loose.app == "/tmp/fake/Applications/Hook Me Up.app")
        #expect(!loose.isRealHome)
        #expect(loose.socket == nil)
        #expect(loose.settings == "/tmp/fake/.claude/settings.json")

        let explicit = Doctor.Options.resolve(
            home: "/tmp/fake", app: "/x/HookMeUp.app", settings: "/x/s.json", socket: "/x/agent.sock",
            executablePath: nil, realHome: home, uid: 501, probe: probe)
        #expect(explicit.app == "/x/HookMeUp.app" && explicit.settings == "/x/s.json")
        #expect(explicit.socket == "/x/agent.sock")
    }

    @Test func launchctlPrintIsRead() {
        let running =
            "gui/501/x = {\n\tactive count = 1\n\tstate = running\n\n\tprogram = /a\n\tpid = 812\n"
            + "\tendpoints = {\n\t\tstate = waiting\n\t}\n}\n"
        #expect(LaunchAgentState(launchctlStatus: 0, output: running) == .running(pid: 812))
        let stopped = "gui/501/x = {\n\tstate = not running\n\tlast exit code = 0\n}\n"
        #expect(LaunchAgentState(launchctlStatus: 0, output: stopped) == .notRunning)
        #expect(LaunchAgentState(launchctlStatus: 113, output: "") == .notLoaded)
        #expect(LaunchAgentState(launchctlStatus: 1, output: "") == .unknown("launchctl print exited with 1"))
        #expect(LaunchAgentState(launchctlStatus: 0, output: "{}") == .unknown("launchctl print showed no state"))
    }

    @Test func fixesAreIndentedUnderTheirCheck() {
        let report = DoctorReport(checks: [
            DoctorCheck("A", .pass, "fine"),
            DoctorCheck("B", .fail, "broken", fix: "Do this:\nrun that"),
            DoctorCheck("C", .warn, "meh", fix: "Maybe."),
        ])
        #expect(
            report.rendered() == """
                PASS  A: fine
                FAIL  B: broken
                      Fix: Do this:
                        run that
                WARN  C: meh
                      Fix: Maybe.

                1 problem, 1 warning.
                """)
        #expect(report.exitCode == 1)
    }

    @Test func wordsAreQuotedOnlyWhenNeeded() {
        #expect(Doctor.quoted("/Users/me/.claude/settings.json") == "/Users/me/.claude/settings.json")
        #expect(Doctor.quoted("/a b/c") == "'/a b/c'")
        #expect(Doctor.quoted("/it's") == #"'/it'\''s'"#)
        #expect(Doctor.quoted("") == "''")
    }
}
