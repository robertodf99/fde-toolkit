import Foundation
import HookMeUpCore
import Testing

@testable import DoctorKit

/// Replays agent answers; the clock moves only when the onboarding sleeps.
final class FakeOnboardingIO: OnboardingIO {
    var replies: [AgentReply]
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    var opens = true
    private(set) var lines: [String] = []
    private(set) var queries = 0
    private(set) var tests = 0
    private(set) var opened = 0
    private(set) var slept: TimeInterval = 0

    init(_ replies: [AgentReply]) {
        self.replies = replies
    }

    func sleep(_ seconds: TimeInterval) {
        slept += seconds
        now += seconds
    }

    /// The next answer; the last one repeats.
    func status() -> AgentReply {
        queries += 1
        return replies.count > 1 ? replies.removeFirst() : replies[0]
    }

    func sendTestNotification() -> Bool {
        tests += 1
        return true
    }

    func openNotificationSettings() -> Bool {
        opened += 1
        return opens
    }

    func say(_ line: String) {
        lines.append(line)
    }
}

private func agent(
    _ status: NotificationAuthorization.Status, _ style: NotificationAuthorization.AlertStyle = .alert
) -> AgentReply {
    .status(
        AgentStatus(
            version: "0.2.0", build: "0.2.0",
            notifications: NotificationAuthorization(status: status, alertStyle: style),
            paused: false, pendingCount: 0))
}

private func onboard(
    _ io: FakeOnboardingIO, wait: TimeInterval = 60, test: Bool = true,
    open: NotificationOnboarding.OpenSettings = .unlessAlerts
) -> NotificationOnboarding.Outcome {
    NotificationOnboarding.run(.init(wait: wait, test: test, openSettings: open), io: io)
}

@Suite struct NotificationOnboardingTests {
    @Test func allowedWithAlertsIsReadyAndGetsATestNotification() {
        let io = FakeOnboardingIO([agent(.authorized, .alert)])
        #expect(onboard(io) == .ready)
        #expect(io.tests == 1)
        #expect(io.opened == 0)
        #expect(io.queries == 1)
        #expect(io.lines.contains("Sent a test notification."))
        #expect(io.lines.last?.hasPrefix("Notifications are on, style Alerts") == true)
    }

    @Test func withoutTestNoTestNotification() {
        let io = FakeOnboardingIO([agent(.authorized, .alert)])
        #expect(onboard(io, test: false) == .ready)
        #expect(io.tests == 0)
    }

    @Test func itWaitsForTheAnswerToMacOSAndSaysSoOnce() {
        let io = FakeOnboardingIO([
            agent(.notDetermined, .none), agent(.notDetermined, .none), agent(.authorized, .alert),
        ])
        #expect(onboard(io) == .ready)
        #expect(io.queries == 3)
        #expect(io.lines.filter { $0.hasPrefix("Waiting up to 60 s") }.count == 1)
        #expect(io.tests == 1)
    }

    @Test func anUnansweredQuestionStopsWaitingAtTheLimit() {
        let io = FakeOnboardingIO([agent(.notDetermined, .none)])
        #expect(onboard(io, wait: 10) == .undecided)
        #expect(io.slept == 10)
        #expect(io.tests == 0)  // nothing can show yet
        #expect(io.opened == 1)
        #expect(io.lines.last == "Opened System Settings > Notifications.")
    }

    @Test func turnedOffOpensSettingsUnlessToldNot() {
        for (open, opened) in [(NotificationOnboarding.OpenSettings.unlessAlerts, 1), (.whenOff, 1), (.never, 0)] {
            let io = FakeOnboardingIO([agent(.denied, .none)])
            #expect(onboard(io, open: open) == .off)
            #expect(io.opened == opened)
            #expect(io.tests == 0)
            #expect(io.lines.contains { $0.hasPrefix("Notifications are off for Hook Me Up") })
        }
    }

    @Test func bannersOpenSettingsOnAFreshInstallOnlyAndAlwaysSaySo() {
        let fresh = FakeOnboardingIO([agent(.authorized, .banner)])
        #expect(onboard(fresh, open: .unlessAlerts) == .notAlerts)
        #expect(fresh.opened == 1)
        #expect(fresh.tests == 1)
        let upgrade = FakeOnboardingIO([agent(.authorized, .banner)])
        #expect(onboard(upgrade, open: .whenOff) == .notAlerts)
        #expect(upgrade.opened == 0)
        #expect(
            upgrade.lines.contains { $0.contains("Set it to Alerts in System Settings > Notifications > Hook Me Up") })
    }

    @Test func anAgentThatIsStartingIsWaitedFor() {
        let io = FakeOnboardingIO([.noSocket, .notListening, agent(.authorized, .alert)])
        #expect(onboard(io) == .ready)
        #expect(io.slept == 1)
    }

    @Test func anAgentThatNeverAnswersIsGivenUpOnAfterTenSeconds() {
        let io = FakeOnboardingIO([.noSocket])
        #expect(onboard(io, wait: 60) == .noAgent)
        #expect(io.slept == 10)
        #expect(io.opened == 0 && io.tests == 0)
        #expect(io.lines.last?.contains("hook-me-up-setup doctor") == true)
        let short = FakeOnboardingIO([.timedOut])
        #expect(onboard(short, wait: 3) == .noAgent)
        #expect(short.slept == 3)
    }

    @Test func theDoctorHintNamesThisProgram() {
        let io = FakeOnboardingIO([.noSocket])
        let setup = "'/Users/me/Applications/Hook Me Up.app/Contents/MacOS/hook-me-up-setup'"
        let outcome = NotificationOnboarding.run(
            .init(wait: 0, test: false, openSettings: .never, setupCommand: setup), io: io)
        #expect(outcome == .noAgent)
        #expect(io.lines.last == "  \(setup) doctor")
    }

    @Test func aStateFromANewerAgentIsTreatedAsUndecided() {
        let io = FakeOnboardingIO([agent(.unknown, .unknown)])
        #expect(onboard(io, open: .whenOff) == .undecided)
        #expect(io.queries == 1)  // nothing to wait for
        #expect(io.opened == 1)
    }

    @Test func anOlderAgentIsLeftAlone() {
        let io = FakeOnboardingIO([.closedWithoutAnswer])
        #expect(onboard(io) == .oldAgent)
        #expect(io.queries == 1)
        #expect(io.opened == 0 && io.tests == 0)
    }

    @Test func noWaitAsksOnce() {
        let io = FakeOnboardingIO([.noSocket, agent(.authorized, .alert)])
        #expect(onboard(io, wait: 0) == .noAgent)
        #expect(io.queries == 1)
        #expect(io.slept == 0)
    }

    @Test func aFailedOpenIsReported() {
        let io = FakeOnboardingIO([agent(.denied, .none)])
        io.opens = false
        #expect(onboard(io) == .off)
        #expect(io.lines.last == "Couldn't open System Settings.")
    }

    @Test func theSettingsLinkNamesTheApp() {
        #expect(
            NotificationOnboarding.settingsURLs.first
                == "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=io.github.robertodf99.hook-me-up"
        )
        #expect(NotificationOnboarding.Outcome.notAlerts.rawValue == "not-alerts")
    }
}
