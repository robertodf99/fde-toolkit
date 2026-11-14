import Foundation
import HookMeUpCore

/// What `NotificationOnboarding` needs from the system, so its decisions are testable.
public protocol OnboardingIO {
    /// The current time.
    var now: Date { get }
    /// Waits `seconds`.
    func sleep(_ seconds: TimeInterval)
    /// Asks the agent for its status.
    func status() -> AgentReply
    /// Asks the agent to show its test notification; false when that couldn't be sent.
    func sendTestNotification() -> Bool
    /// Opens System Settings at Notifications; false when it couldn't.
    func openNotificationSettings() -> Bool
    /// Prints a line for the user.
    func say(_ line: String)
}

/// `hook-me-up-setup notifications`: right after the installer starts the agent, waits
/// for it, waits while macOS's notification question is unanswered, says what the
/// settings are and what to change, and optionally shows a test notification and opens
/// System Settings. Never asks anything on the terminal.
public enum NotificationOnboarding {
    /// The app's bundle identifier, which System Settings keys its notification settings by.
    public static let bundleIdentifier = "io.github.robertodf99.hook-me-up"
    /// System Settings at Hook Me Up's notification settings, then at Notifications.
    public static let settingsURLs = [
        "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleIdentifier)",
        "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
    ]
    /// The longest wait for an agent that was just started to listen.
    static let agentStartWait: TimeInterval = 10
    static let settings = "System Settings > Notifications > Hook Me Up"

    /// When to open System Settings.
    public enum OpenSettings: Sendable {
        /// Never.
        case never
        /// When notifications are not allowed.
        case whenOff
        /// When notifications are not allowed or the style is not Alerts (a fresh install).
        case unlessAlerts
    }

    /// What to do.
    public struct Options: Sendable {
        /// How long to wait for an answer to macOS's notification question.
        public var wait: TimeInterval
        /// Show a test notification when notifications are allowed.
        public var test: Bool
        /// When to open System Settings.
        public var openSettings: OpenSettings
        /// How to run this `hook-me-up-setup` (its full path, quoted), for the hints.
        public var setupCommand: String

        /// Creates options.
        public init(
            wait: TimeInterval, test: Bool, openSettings: OpenSettings, setupCommand: String = "hook-me-up-setup"
        ) {
            self.wait = wait
            self.test = test
            self.openSettings = openSettings
            self.setupCommand = setupCommand
        }
    }

    /// How it ended (the installer adapts its next steps to it).
    public enum Outcome: String, Sendable {
        /// Allowed, style Alerts.
        case ready
        /// Allowed, but the style isn't Alerts.
        case notAlerts = "not-alerts"
        /// Turned off.
        case off
        /// macOS's question is still unanswered.
        case undecided
        /// The agent runs but is too old to say.
        case oldAgent = "old-agent"
        /// The agent didn't answer.
        case noAgent = "no-agent"
    }

    /// Runs the onboarding and returns how it ended.
    public static func run(_ options: Options, io: some OnboardingIO) -> Outcome {
        let start = io.now
        var waitingAnnounced = false
        var reply = io.status()
        while true {
            let elapsed = io.now.timeIntervalSince(start)
            switch reply {
            case .status(let status) where status.notifications.status == .notDetermined && elapsed < options.wait:
                if !waitingAnnounced {
                    waitingAnnounced = true
                    io.say(
                        "Waiting up to \(Int(options.wait)) s for your answer to macOS: allow notifications from Hook Me Up."
                    )
                }
                io.sleep(1)
            case .noSocket, .notListening, .timedOut, .failed:
                // Just started: give it a moment to listen.
                guard elapsed < min(options.wait, agentStartWait) else { return finish(reply, options, io) }
                io.sleep(0.5)
            default:
                return finish(reply, options, io)
            }
            reply = io.status()
        }
    }

    private static func finish(_ reply: AgentReply, _ options: Options, _ io: some OnboardingIO) -> Outcome {
        guard case .status(let status) = reply else {
            if reply == .closedWithoutAnswer {
                io.say("The agent that runs is too old to report its notification settings.")
                return .oldAgent
            }
            io.say("The agent didn't answer, so notifications weren't checked. Check with:")
            io.say("  \(options.setupCommand) doctor")
            return .noAgent
        }
        let authorization = status.notifications
        let outcome: Outcome
        switch authorization.status {
        case .authorized, .provisional:
            if options.test, io.sendTestNotification() { io.say("Sent a test notification.") }
            if authorization.alertStyle == .alert {
                io.say("Notifications are on, style Alerts: requests stay on screen until you answer them.")
                outcome = .ready
            } else {
                let style =
                    switch authorization.alertStyle {
                    case .banner: "Banners"
                    case .none: "None"
                    case .alert, .unknown: "not Alerts"
                    }
                io.say(
                    "Notifications are on, but their style is \(style): requests won't stay on screen. "
                        + "Set it to Alerts in \(settings).")
                outcome = .notAlerts
            }
        case .denied:
            io.say("Notifications are off for Hook Me Up, so requests go to the terminal. Turn them on in \(settings).")
            outcome = .off
        case .notDetermined, .unknown:
            io.say(
                "macOS is still waiting for your answer: allow notifications from Hook Me Up, or turn them on in \(settings)."
            )
            outcome = .undecided
        }
        let open =
            switch options.openSettings {
            case .never: false
            case .whenOff: outcome == .off || outcome == .undecided
            case .unlessAlerts: outcome != .ready
            }
        if open {
            io.say(
                io.openNotificationSettings()
                    ? "Opened System Settings > Notifications." : "Couldn't open System Settings.")
        }
        return outcome
    }
}

/// The real `OnboardingIO`: the clock, the agent's socket, `open` and stdout.
public struct SystemOnboardingIO: OnboardingIO {
    let socket: URL

    /// Talks to the agent at `socket`.
    public init(socket: URL) {
        self.socket = socket
    }

    /// The current time.
    public var now: Date { Date() }

    /// Waits.
    public func sleep(_ seconds: TimeInterval) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// The agent's status, within `Doctor.agentTimeout`.
    public func status() -> AgentReply {
        AgentClient.status(socketPath: socket, timeout: Doctor.agentTimeout)
    }

    /// Asks the agent for its test notification.
    public func sendTestNotification() -> Bool {
        AgentClient.sendTestNotification(socketPath: socket, timeout: Doctor.agentTimeout)
    }

    /// `open` with Hook Me Up's notification settings, else the Notifications pane.
    /// `open` is looked up on PATH, so the install tests can stand in for it.
    public func openNotificationSettings() -> Bool {
        NotificationOnboarding.settingsURLs.contains { url in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["open", url]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return false }
            process.waitUntilExit()
            return process.terminationStatus == 0
        }
    }

    /// Prints `line` at once (the installer shows it while it waits).
    public func say(_ line: String) {
        print(line)
        fflush(stdout)
    }
}
