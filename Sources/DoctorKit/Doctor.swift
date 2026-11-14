import Foundation
import HookMeUpCore
import SetupKit

/// `hook-me-up-setup doctor`: checks an installation, from the app to the notification
/// settings, and says how to fix what is off. Reads through `DoctorProbe` only and
/// changes nothing.
public enum Doctor {
    /// The installer's LaunchAgent label.
    public static let installerLabel = "io.github.robertodf99.hook-me-up"
    /// The label `brew services` gives the Homebrew formula's service.
    public static let homebrewLabel = "homebrew.mxcl.hook-me-up"
    /// How long the agent has to connect and to answer.
    public static let agentTimeout: TimeInterval = 2
    static let installer = "curl -fsSL https://raw.githubusercontent.com/robertodf99/hook-me-up/main/install.sh | bash"
    static let uninstaller =
        "curl -fsSL https://raw.githubusercontent.com/robertodf99/hook-me-up/main/uninstall.sh | bash"
    static let notificationSettings = "System Settings > Notifications > Hook Me Up"
    static let notHome = "not checked: --home is not your home folder"

    /// What to check.
    public struct Options: Equatable, Sendable {
        /// The home folder whose LaunchAgents (and default settings) are checked.
        public var home: String
        /// Whether `home` is the user's own home: only then is launchd asked.
        public var isRealHome: Bool
        /// The app bundle to check.
        public var app: String
        /// The Claude Code settings file.
        public var settings: String
        /// The agent's socket; nil skips the checks that need the running agent.
        public var socket: String?
        /// The user id, for `launchctl` commands in fixes.
        public var uid: UInt32

        /// Creates options.
        public init(home: String, isRealHome: Bool, app: String, settings: String, socket: String?, uid: UInt32) {
            self.home = home
            self.isRealHome = isRealHome
            self.app = app
            self.settings = settings
            self.socket = socket
            self.uid = uid
        }

        /// Options from the command line; what isn't given is derived. The app is the
        /// one this program runs from (`executablePath`, symlinks resolved, so Homebrew's
        /// `bin` link counts), else `<home>/Applications/Hook Me Up.app`. The running
        /// agent is checked for the user's own home, or at an explicit `socket`.
        public static func resolve(
            home: String?, app: String?, settings: String?, socket: String?, executablePath: String?,
            realHome: String, uid: UInt32, probe: some DoctorProbe
        ) -> Options {
            let home = home ?? realHome
            let isRealHome = probe.canonicalPath(home) == probe.canonicalPath(realHome)
            let app =
                app ?? executablePath.flatMap { appContaining(probe.canonicalPath($0)) }
                ?? home + "/Applications/Hook Me Up.app"
            return Options(
                home: home, isRealHome: isRealHome, app: app, settings: settings ?? home + "/.claude/settings.json",
                socket: socket ?? (isRealHome ? HookMeUpPaths.socketURL(home: URL(fileURLWithPath: home)).path : nil),
                uid: uid)
        }

        /// The app bundle that has `executable` in its `Contents/MacOS`, if any.
        static func appContaining(_ executable: String) -> String? {
            let macOS = (executable as NSString).deletingLastPathComponent
            let contents = (macOS as NSString).deletingLastPathComponent
            let app = (contents as NSString).deletingLastPathComponent
            guard (macOS as NSString).lastPathComponent == "MacOS",
                (contents as NSString).lastPathComponent == "Contents",
                app.hasSuffix(".app")
            else { return nil }
            return app
        }
    }

    /// The app being checked, and how it was installed.
    struct Installation {
        let app: String
        /// Installed by the Homebrew formula (the app sits in a versioned keg).
        let isHomebrew: Bool
        /// The path to recommend: Homebrew's opt path (stable across upgrades), else `app`.
        let stableApp: String
        let version: String
        let build: String

        init(app: String, probe: some DoctorProbe) {
            self.app = app
            let canonical = probe.canonicalPath(app)
            if let keg = canonical.range(of: "/Cellar/hook-me-up/") {
                // <prefix>/Cellar/hook-me-up/<version>/Hook Me Up.app -> <prefix>/opt/hook-me-up/Hook Me Up.app
                let inKeg = canonical[keg.upperBound...].drop { $0 != "/" }
                let opt = String(canonical[..<keg.lowerBound]) + "/opt/hook-me-up" + inKeg
                isHomebrew = true
                stableApp = probe.exists(opt) ? opt : app
            } else {
                isHomebrew = false
                stableApp = app
            }
            let info =
                probe.contents(of: app + "/Contents/Info.plist").flatMap {
                    try? PropertyListSerialization.propertyList(from: $0, format: nil)
                } as? [String: Any]
            version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
            build = info?["CFBundleVersion"] as? String ?? "unknown"
        }

        var hookPath: String { stableApp + "/Contents/MacOS/hook-me-up" }
        var setupPath: String { stableApp + "/Contents/MacOS/hook-me-up-setup" }
        var agentPath: String { app + "/Contents/MacOS/HookMeUp" }
        /// How to get the agent of this installation running again.
        var restart: String {
            isHomebrew
                ? "brew services restart hook-me-up" : "Run the installer again (it restarts the agent):\n\(installer)"
        }
    }

    /// Runs every check.
    public static func run(_ options: Options, probe: some DoctorProbe) -> DoctorReport {
        let install = Installation(app: options.app, probe: probe)
        var checks = [appCheck(install, probe)]
        let launchAgent = launchAgentChecks(install, options, probe)
        checks += launchAgent.checks
        checks.append(processCheck(launchAgent.plist, install, options, probe))
        let reply = options.socket.map { probe.queryAgent(socketPath: $0, timeout: agentTimeout) }
        checks.append(agentCheck(reply, options, install))
        var status: AgentStatus?
        if case .status(let answer)? = reply { status = answer }
        let noStatus = options.socket == nil ? notHome : "not checked: the agent didn't answer"
        checks.append(versionCheck(status, install, skipped: noStatus))
        checks += hookChecks(install, options, probe)
        checks += notificationChecks(status, install, skipped: noStatus)
        checks.append(pauseCheck(status, skipped: noStatus))
        return DoctorReport(checks: checks)
    }

    // MARK: Checks

    static func appCheck(_ install: Installation, _ probe: some DoctorProbe) -> DoctorCheck {
        let missing = ["HookMeUp", "hook-me-up", "hook-me-up-setup"].filter {
            !probe.isExecutable(install.app + "/Contents/MacOS/" + $0)
        }
        guard missing.isEmpty else {
            let detail =
                probe.exists(install.app)
                ? "\(install.app) is incomplete (no \(missing.joined(separator: ", ")))"
                : "no app at \(install.app)"
            let fix =
                install.isHomebrew
                ? "brew reinstall hook-me-up"
                : "Install it again:\n\(installer)\nor check another copy with --app <path>."
            return DoctorCheck("App", .fail, detail, fix: fix)
        }
        let source = install.isHomebrew ? ", installed with Homebrew" : ""
        return DoctorCheck("App", .pass, "Hook Me Up \(install.version) (\(install.build)) at \(install.app)\(source)")
    }

    struct LaunchAgentResult {
        var checks: [DoctorCheck]
        /// The LaunchAgent that starts this app: (label, plist path).
        var plist: (label: String, path: String)?
    }

    static func launchAgentChecks(
        _ install: Installation, _ options: Options, _ probe: some DoctorProbe
    ) -> LaunchAgentResult {
        let folder = options.home + "/Library/LaunchAgents"
        let found = [installerLabel, homebrewLabel].compactMap { label -> (label: String, path: String, data: Data)? in
            let path = "\(folder)/\(label).plist"
            return probe.contents(of: path).map { (label, path, $0) }
        }
        guard !found.isEmpty else {
            let fix = install.isHomebrew ? "brew services start hook-me-up" : "Run the installer again:\n\(installer)"
            return LaunchAgentResult(
                checks: [
                    DoctorCheck(
                        "LaunchAgent", .fail, "none in \(folder): the agent doesn't start at login", fix: fix)
                ], plist: nil)
        }
        var checks: [DoctorCheck] = []
        let agent = probe.canonicalPath(install.agentPath)
        let ours = found.first { programPath(in: $0.data).map(probe.canonicalPath) == agent }
        if let ours {
            checks.append(DoctorCheck("LaunchAgent", .pass, "\(ours.label) starts this app"))
        } else {
            let starts = found.map { "\($0.label) starts \(programPath(in: $0.data) ?? "nothing it can read")" }
            checks.append(
                DoctorCheck(
                    "LaunchAgent", .fail, starts.joined(separator: "; ") + ", not this app",
                    fix: install.isHomebrew
                        ? "brew services restart hook-me-up" : "Run the installer again:\n\(installer)"))
        }
        if found.count > 1 {
            checks.append(
                DoctorCheck(
                    "Two installations", .warn,
                    "both the installer's LaunchAgent and Homebrew's are present; only one agent can run",
                    fix: "Keep one. Remove the installer's with:\n\(uninstaller)\n"
                        + "or Homebrew's with: brew services stop hook-me-up && brew uninstall hook-me-up"))
        }
        return LaunchAgentResult(checks: checks, plist: ours.map { ($0.label, $0.path) })
    }

    /// The program a LaunchAgent property list starts (`ProgramArguments[0]`, else `Program`).
    static func programPath(in plist: Data) -> String? {
        guard let object = try? PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        else { return nil }
        if let arguments = object["ProgramArguments"] as? [String], let first = arguments.first { return first }
        return object["Program"] as? String
    }

    static func processCheck(
        _ plist: (label: String, path: String)?, _ install: Installation, _ options: Options,
        _ probe: some DoctorProbe
    ) -> DoctorCheck {
        guard options.isRealHome else { return DoctorCheck("Agent process", .skipped, notHome) }
        guard let plist else { return DoctorCheck("Agent process", .skipped, "no LaunchAgent starts this app") }
        let homebrew = plist.label == homebrewLabel
        let service = "gui/\(options.uid)/\(plist.label)"
        switch probe.launchAgentState(label: plist.label) {
        case .running(let pid):
            return DoctorCheck("Agent process", .pass, "running (pid \(pid))")
        case .notRunning:
            return DoctorCheck(
                "Agent process", .fail, "loaded but not running (quit from the menu, or it keeps stopping)",
                fix: homebrew ? "brew services restart hook-me-up" : "launchctl kickstart \(service)")
        case .notLoaded:
            return DoctorCheck(
                "Agent process", .fail, "\(plist.label) is not loaded, so the agent isn't running",
                fix: homebrew
                    ? "brew services start hook-me-up"
                    : "launchctl bootstrap gui/\(options.uid) \(quoted(plist.path))")
        case .unknown(let reason):
            return DoctorCheck("Agent process", .warn, "launchctl couldn't tell: \(reason)")
        }
    }

    static func agentCheck(_ reply: AgentReply?, _ options: Options, _ install: Installation) -> DoctorCheck {
        guard let reply, let socket = options.socket else {
            return DoctorCheck("Agent", .skipped, notHome + " (--socket <path> checks an agent)")
        }
        switch reply {
        case .status(let status):
            let waiting = status.pendingCount == 1 ? "1 request waiting" : "\(status.pendingCount) requests waiting"
            return DoctorCheck("Agent", .pass, "answers on its socket (\(waiting))")
        case .noSocket:
            return DoctorCheck("Agent", .fail, "not running: no socket at \(socket)", fix: install.restart)
        case .notListening:
            return DoctorCheck(
                "Agent", .fail, "not running: nothing listens on \(socket)", fix: install.restart)
        case .closedWithoutAnswer:
            return DoctorCheck(
                "Agent", .warn, "the agent that runs is too old to answer status questions",
                fix: "Restart it with the installed version. " + install.restart)
        case .timedOut:
            return DoctorCheck(
                "Agent", .fail, "didn't answer within \(Int(agentTimeout)) s", fix: install.restart)
        case .failed(let reason):
            return DoctorCheck("Agent", .fail, "couldn't ask it: \(reason)", fix: install.restart)
        }
    }

    static func versionCheck(_ status: AgentStatus?, _ install: Installation, skipped: String) -> DoctorCheck {
        guard let status else { return DoctorCheck("Agent version", .skipped, skipped) }
        guard status.version == install.version, status.build == install.build else {
            return DoctorCheck(
                "Agent version", .warn,
                "the agent that runs is \(status.version) (\(status.build)); the app is \(install.version) (\(install.build))",
                fix: install.restart)
        }
        return DoctorCheck("Agent version", .pass, "\(status.version) (\(status.build)), the same as the app")
    }

    static func hookChecks(_ install: Installation, _ options: Options, _ probe: some DoctorProbe) -> [DoctorCheck] {
        let settings = options.settings
        let fix = "Add them (shows the changes and asks first):\n" + installCommand(install, options)
        guard let data = probe.contents(of: settings) else {
            let detail =
                probe.exists(settings)
                ? "\(settings) can't be read" : "\(settings) doesn't exist, so there are no hooks"
            return [DoctorCheck("Hooks", .fail, detail, fix: fix)]
        }
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data), value.objectValue != nil else {
            return [
                DoctorCheck(
                    "Hooks", .fail, "\(settings) is not a valid JSON object",
                    fix: "Correct it by hand (Claude Code can't read it either), then run:\n"
                        + installCommand(install, options))
            ]
        }
        let found = SettingsMerger.inspect(
            settings: value, hookPath: install.hookPath, canonicalPath: probe.canonicalPath)
        var checks: [DoctorCheck] = []
        if found.installed.isEmpty {
            checks.append(DoctorCheck("Hooks", .fail, "\(settings) has none of Hook Me Up's hooks", fix: fix))
        } else if !found.missing.isEmpty {
            checks.append(
                DoctorCheck(
                    "Hooks", .fail, "missing for \(found.missing.joined(separator: ", ")) in \(settings)", fix: fix))
        } else {
            checks.append(DoctorCheck("Hooks", .pass, "all five events run \(install.hookPath)"))
        }
        if found.allHooksDisabled {
            checks.append(
                DoctorCheck(
                    "Hooks disabled", .fail, "\(settings) sets \"disableAllHooks\": true, so Claude Code runs no hooks",
                    fix: "Remove \"disableAllHooks\": true from \(settings)."))
        }
        if !found.duplicated.isEmpty {
            checks.append(
                DoctorCheck(
                    "Duplicate hooks", .warn,
                    "hook-me-up runs more than once for \(found.duplicated.joined(separator: ", ")), so their notifications show twice",
                    fix: "Keep one hook-me-up entry per event in \(settings)."))
        }
        if !found.otherPaths.isEmpty {
            let removals = found.otherPaths.map {
                "\(quoted(install.setupPath)) uninstall --settings \(quoted(settings)) --hook \(quoted($0))"
            }
            checks.append(
                DoctorCheck(
                    "Other installation", .warn,
                    "\(settings) also runs hook-me-up from \(found.otherPaths.joined(separator: ", "))",
                    fix: "If that copy is gone or unused, remove its hooks (shows the changes and asks first):\n"
                        + removals.joined(separator: "\n")))
        }
        return checks
    }

    static func notificationChecks(_ status: AgentStatus?, _ install: Installation, skipped: String) -> [DoctorCheck] {
        let openIt = "\nTo open it: \(quoted(install.setupPath)) notifications --open-settings"
        guard let authorization = status?.notifications else {
            return [
                DoctorCheck("Notifications", .skipped, skipped), DoctorCheck("Notification style", .skipped, skipped),
            ]
        }
        let allow: DoctorCheck =
            switch authorization.status {
            case .authorized: DoctorCheck("Notifications", .pass, "allowed")
            case .provisional: DoctorCheck("Notifications", .pass, "allowed quietly (provisional)")
            case .denied:
                DoctorCheck(
                    "Notifications", .fail, "turned off for Hook Me Up, so every request goes to the terminal",
                    fix: "Turn on Allow notifications in \(notificationSettings)." + openIt)
            case .notDetermined:
                DoctorCheck(
                    "Notifications", .warn, "macOS hasn't asked yet, or the question still waits for your answer",
                    fix: "Click Allow when macOS asks about Hook Me Up, or turn them on in \(notificationSettings)."
                        + openIt)
            }
        guard authorization.allowsNotifications else {
            return [allow, DoctorCheck("Notification style", .skipped, "notifications are not allowed")]
        }
        let toAlerts = "Set the style to Alerts in \(notificationSettings)." + openIt
        let style =
            switch authorization.alertStyle {
            case .alert: DoctorCheck("Notification style", .pass, "Alerts: requests stay on screen until you answer")
            case .banner:
                DoctorCheck(
                    "Notification style", .warn, "Banners: requests leave the screen after a few seconds",
                    fix: toAlerts)
            case .none:
                DoctorCheck(
                    "Notification style", .fail, "None: requests never show on screen, only in Notification Center",
                    fix: toAlerts)
            }
        return [allow, style]
    }

    static func pauseCheck(_ status: AgentStatus?, skipped: String) -> DoctorCheck {
        guard let status else { return DoctorCheck("Pause", .skipped, skipped) }
        guard status.paused else { return DoctorCheck("Pause", .pass, "not paused") }
        return DoctorCheck(
            "Pause", .info, "paused: requests go to the terminal until the pause ends",
            fix: "To end it now, choose Resume in the ✻ menu-bar item.")
    }

    // MARK: Commands in fixes

    /// The command that adds the hooks of `install` to the checked settings.
    static func installCommand(_ install: Installation, _ options: Options) -> String {
        var words = [quoted(install.setupPath), "install", "--settings", quoted(options.settings)]
        words += ["--hook", quoted(install.hookPath)]
        if !options.isRealHome {
            // Keep the installer's bookkeeping out of the real home too.
            let support = HookMeUpPaths.socketURL(home: URL(fileURLWithPath: options.home)).deletingLastPathComponent()
            words += ["--state", quoted(support.appendingPathComponent("setup-state.json").path)]
        }
        return words.joined(separator: " ")
    }

    /// `text` as one shell word: as is when it has no special characters, else single-quoted.
    public static func quoted(_ text: String) -> String {
        let plain = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789/._-+:@%=,")
        if !text.isEmpty, text.allSatisfy(plain.contains) { return text }
        return "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
