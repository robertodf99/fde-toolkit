import Foundation
import HookMeUpCore
import Testing

@testable import DoctorKit

private let home = "/Users/me"
private let app = "/Users/me/Applications/Hook Me Up.app"
private let settingsPath = "/Users/me/.claude/settings.json"
private let socketPath = "/Users/me/Library/Application Support/hook-me-up/agent.sock"
private let installerPlist = "/Users/me/Library/LaunchAgents/io.github.robertodf99.hook-me-up.plist"
private let homebrewPlist = "/Users/me/Library/LaunchAgents/homebrew.mxcl.hook-me-up.plist"
private let installerCommand =
    "curl -fsSL https://raw.githubusercontent.com/robertodf99/hook-me-up/main/install.sh | bash"

/// Files, links, launchd and the agent, all made up.
final class FakeProbe: DoctorProbe {
    var files: [String: Data] = [:]
    var executables: Set<String> = []
    /// Symlinks: path prefix -> what it resolves to.
    var links: [String: String] = [:]
    var launchStates: [String: LaunchAgentState] = [:]
    var reply: AgentReply = .noSocket
    private(set) var queried: [String] = []

    func contents(of path: String) -> Data? { files[path] }
    func isExecutable(_ path: String) -> Bool { executables.contains(path) }
    func exists(_ path: String) -> Bool {
        files[path] != nil || executables.contains(path) || executables.contains { $0.hasPrefix(path + "/") }
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

private func launchAgent(starting program: String, label: String = Doctor.installerLabel) -> Data {
    plist(["Label": label, "ProgramArguments": [program], "RunAtLoad": true])
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
                "Notification style", "Pause",
            ])
        #expect(report.checks.allSatisfy { $0.result == .pass }, "\(report.rendered())")
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

    @Test func bothLaunchAgentsWarn() {
        let probe = healthy()
        probe.files[homebrewPlist] = launchAgent(
            starting: "/opt/homebrew/opt/hook-me-up/Hook Me Up.app/Contents/MacOS/HookMeUp", label: Doctor.homebrewLabel
        )
        let report = run(probe)
        #expect(report.check("LaunchAgent")?.result == .pass)
        let both = report.check("Two installations")
        #expect(both?.result == .warn)
        #expect(both?.fix?.contains("brew uninstall hook-me-up") == true)
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

    // MARK: Homebrew

    @Test func aHomebrewInstallIsCheckedThroughItsOptPath() {
        let keg = "/opt/homebrew/Cellar/hook-me-up/0.2.0/Hook Me Up.app"
        let opt = "/opt/homebrew/opt/hook-me-up/Hook Me Up.app"
        let probe = healthy(app: keg)
        probe.links["/opt/homebrew/opt/hook-me-up"] = "/opt/homebrew/Cellar/hook-me-up/0.2.0"
        probe.files[installerPlist] = nil
        probe.files[homebrewPlist] = launchAgent(
            starting: "\(opt)/Contents/MacOS/HookMeUp", label: Doctor.homebrewLabel)
        probe.launchStates = [Doctor.homebrewLabel: .running(pid: 7)]
        probe.files[settingsPath] = hooks(at: "\(opt)/Contents/MacOS/hook-me-up")
        probe.executables.insert("\(opt)/Contents/MacOS/hook-me-up")  // the opt link exists
        var options = realHome
        options.app = keg
        let report = run(probe, options)
        #expect(report.checks.allSatisfy { $0.result == .pass }, "\(report.rendered())")
        #expect(report.check("App")?.detail.hasSuffix("installed with Homebrew") == true)
        #expect(report.check("LaunchAgent")?.detail == "homebrew.mxcl.hook-me-up starts this app")
        #expect(report.check("Hooks")?.detail == "all five events run \(opt)/Contents/MacOS/hook-me-up")

        // Fixes name Homebrew's commands and the stable opt path.
        probe.files[settingsPath] = nil
        probe.launchStates = [:]
        probe.reply = .noSocket
        let broken = run(probe, options)
        #expect(
            broken.check("Hooks")?.fix?.hasSuffix(
                "'\(opt)/Contents/MacOS/hook-me-up-setup' install --settings \(settingsPath)"
                    + " --hook '\(opt)/Contents/MacOS/hook-me-up'") == true)
        #expect(broken.check("Agent process")?.fix == "brew services start hook-me-up")
        #expect(broken.check("Agent")?.fix == "brew services restart hook-me-up")
    }

    // MARK: Options and parsing

    @Test func optionsComeFromTheAppThisProgramRunsFrom() {
        let probe = FakeProbe()
        probe.links["/opt/homebrew/bin/hook-me-up-setup"] =
            "/opt/homebrew/Cellar/hook-me-up/0.2.0/Hook Me Up.app/Contents/MacOS/hook-me-up-setup"
        let brew = Doctor.Options.resolve(
            home: nil, app: nil, settings: nil, socket: nil, executablePath: "/opt/homebrew/bin/hook-me-up-setup",
            realHome: home, uid: 501, probe: probe)
        #expect(brew.app == "/opt/homebrew/Cellar/hook-me-up/0.2.0/Hook Me Up.app")
        #expect(brew.isRealHome)
        #expect(brew.settings == settingsPath)
        #expect(brew.socket == socketPath)

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
