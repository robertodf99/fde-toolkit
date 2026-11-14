import Foundation
import HookMeUpCore
import Testing

@testable import AgentKit

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let acme = ProjectInfo(name: "acme-api", gitRoot: nil, branch: nil, worktree: nil)
private let hint = TerminalHint(ancestorPIDs: [42], tty: "ttys001")

final class FakeConnection: AgentConnection {
    private(set) var sent: [WireMessage] = []
    private(set) var isClosed = false

    func send(_ message: WireMessage) throws {
        sent.append(message)
    }

    func close() {
        isClosed = true
    }
}

@MainActor
final class FakeTerminal: TerminalActivating {
    private(set) var opened: [SessionPlace] = []

    func open(_ place: SessionPlace) {
        opened.append(place)
    }
}

/// Stands in for UNUserNotificationCenter: records posts and removals, and suspends on
/// every authorization check like the real (asynchronous) settings call.
@MainActor
final class FakePresenter: NotificationPresenting {
    var current = NotificationAuthorization(status: .authorized, alertStyle: .alert)
    private(set) var posted: [NotificationSpec] = []
    private(set) var removed: [String] = []
    private(set) var authorizationChecks = 0
    /// What macOS would show now, by identifier.
    private(set) var visible: [String: NotificationSpec] = [:]

    func requestAuthorization() async -> NotificationAuthorization {
        await authorization()
    }

    func authorization() async -> NotificationAuthorization {
        authorizationChecks += 1
        await Task.yield()
        return current
    }

    func post(_ spec: NotificationSpec) {
        posted.append(spec)
        visible[spec.identifier] = spec
    }

    func remove(identifiers: [String]) {
        removed += identifiers
        for identifier in identifiers { visible[identifier] = nil }
    }
}

@MainActor
final class LogRecorder {
    private(set) var lines: [String] = []

    func record(_ line: String) {
        lines.append(line)
    }
}

struct FixedClock: WallClock {
    var now: Date
}

private func request(
    kind: EntryKind = .permission, input: JSONValue = .object(["command": "ls"]),
    session: String = "s1", sessionRule: Bool = false
) -> RequestEnvelope {
    let rules =
        sessionRule
        ? [
            PermissionUpdate(
                type: "addRules", rules: [PermissionRule(toolName: "Bash", ruleContent: "ls")], behavior: "allow",
                destination: "session")
        ] : []
    return RequestEnvelope(
        id: UUID(), sessionID: session, project: acme,
        summary: RequestSummary(
            kind: kind, title: kind == .plan ? "Add a cache" : "Run a command",
            description: "List files", tags: [], origin: nil),
        input: input, terminal: hint, sessionPermissions: rules)
}

private let twoQuestions: JSONValue = .object([
    "questions": .array([
        .object([
            "question": "Which colour?", "multiSelect": .bool(false),
            "options": .array([.object(["label": "Blue"]), .object(["label": "Orange"])]),
        ]),
        .object([
            "question": "Which do you like?", "multiSelect": .bool(true),
            "options": .array([.object(["label": "Blue"]), .object(["label": "Orange"]), .object(["label": "Green"])]),
        ]),
    ])
])

private func decided(_ id: UUID, _ decision: UserDecision) -> WireMessage {
    .response(ResponseEnvelope(id: id, outcome: .decided(decision)))
}

@MainActor
private struct Harness {
    let presenter = FakePresenter()
    let terminal = FakeTerminal()
    let log = LogRecorder()
    let controller: AgentController

    init(version: String = "1.0", build: String = "7") {
        let log = self.log
        controller = AgentController(
            presenter: presenter, terminal: terminal, clock: FixedClock(now: t0), version: version, build: build,
            log: { log.record($0) })
    }

    /// Sends `message` on a new connection and waits until the agent has handled it.
    func send(_ message: WireMessage) async -> (FakeConnection, ConnectionID) {
        let connection = FakeConnection()
        let id = controller.register(connection)
        controller.received(message, from: id)
        await controller.settle()
        return (connection, id)
    }

    func respond(_ response: NotificationResponse, to id: UUID) async {
        let category = presenter.visible[id.uuidString]?.categoryIdentifier ?? ""
        controller.handle(response, identifier: id.uuidString, categoryIdentifier: category)
        await controller.settle()
    }
}

@MainActor
@Suite struct AgentControllerTests {
    @Test func aRequestIsPostedWithSoundAndApprovingItAnswersTheHookOnceAndRemovesIt() async {
        let h = Harness()
        let r = request()
        let (connection, _) = await h.send(.request(r))
        #expect(h.presenter.posted.map(\.title) == ["acme-api · Needs permission"])
        #expect(h.presenter.posted.first?.playsSound == true)
        #expect(h.presenter.posted.first?.threadIdentifier == "acme-api")  // no folder in this fixture

        await h.respond(.action("approve"), to: r.id)
        h.controller.handle(.action("deny"), identifier: r.id.uuidString, categoryIdentifier: "permission")
        await h.controller.settle()
        #expect(connection.sent == [decided(r.id, .approve)])
        #expect(connection.isClosed)
        #expect(h.presenter.visible.isEmpty)
        #expect(h.controller.store.entries.isEmpty)
    }

    @Test func denyAndApproveForSessionReachTheHook() async {
        let h = Harness()
        for (action, decision) in [("deny", UserDecision.deny), ("approve-session", .approveForSession)] {
            let r = request(sessionRule: true)
            let (connection, _) = await h.send(.request(r))
            await h.respond(.action(action), to: r.id)  // under the category the notification was posted with
            #expect(connection.sent == [decided(r.id, decision)])
        }
    }

    @Test func approveForSessionUnderAnotherCategoryIsIgnored() async {
        let h = Harness()
        let r = request(sessionRule: true)
        let (connection, _) = await h.send(.request(r))
        h.controller.handle(.action("approve-session"), identifier: r.id.uuidString, categoryIdentifier: "permission")
        await h.controller.settle()
        #expect(connection.sent.isEmpty)
        #expect(h.presenter.visible[r.id.uuidString] != nil)  // still answerable
    }

    @Test func withoutNotificationPermissionRequestsGoToTheTerminalAndTheHowToIsLoggedOnce() async {
        let h = Harness()
        h.presenter.current = NotificationAuthorization(status: .denied, alertStyle: .none)
        let first = request()
        let second = request()
        let (connection1, _) = await h.send(.request(first))
        let (connection2, _) = await h.send(.request(second))
        #expect(connection1.sent == [.response(ResponseEnvelope(id: first.id, outcome: .paused))])
        #expect(connection2.sent == [.response(ResponseEnvelope(id: second.id, outcome: .paused))])
        #expect(connection1.isClosed && connection2.isClosed)
        _ = await h.send(
            .notify(
                NotifyEnvelope(
                    sessionID: "s1", project: acme, kind: .finished, message: "Done.",
                    terminal: hint)))
        #expect(h.presenter.posted.isEmpty)
        #expect(h.controller.store.entries.isEmpty)
        #expect(h.log.lines.filter { $0.contains("System Settings") }.count == 1)

        // Turned on in System Settings: checked again on the next request.
        h.presenter.current = NotificationAuthorization(status: .authorized, alertStyle: .alert)
        let third = request()
        let (connection3, _) = await h.send(.request(third))
        #expect(connection3.sent.isEmpty)
        #expect(h.presenter.visible[third.id.uuidString] != nil)
        #expect(h.presenter.authorizationChecks == 4)
    }

    @Test func turningNotificationsOffReleasesWaitingRequests() async {
        let h = Harness()
        let waiting = request()
        let (connection, _) = await h.send(.request(waiting))
        _ = await h.send(
            .notify(NotifyEnvelope(sessionID: "s2", project: acme, kind: .finished, message: "Done.", terminal: hint)))
        #expect(h.presenter.visible[waiting.id.uuidString] != nil)

        h.presenter.current = NotificationAuthorization(status: .denied, alertStyle: .none)
        let next = request()
        let (nextConnection, _) = await h.send(.request(next))  // the check that notices
        #expect(connection.sent == [.response(ResponseEnvelope(id: waiting.id, outcome: .paused))])
        #expect(connection.isClosed)
        #expect(nextConnection.sent == [.response(ResponseEnvelope(id: next.id, outcome: .paused))])
        #expect(h.presenter.visible.isEmpty)
        #expect(h.presenter.removed.contains(waiting.id.uuidString))
        #expect(h.controller.store.entries.isEmpty)
        // Only hooks that were answered count (the Finished heads-up had none).
        #expect(h.log.lines.contains { $0.hasSuffix("released 1 waiting request to the terminal") })
    }

    /// The app also re-checks every minute, so a waiting request is released even when
    /// no new request arrives.
    @Test func aPeriodicCheckReleasesRequestsWhenNotificationsWereTurnedOff() async {
        let h = Harness()
        let waiting = request()
        let (connection, _) = await h.send(.request(waiting))
        h.presenter.current = NotificationAuthorization(status: .denied, alertStyle: .none)
        h.controller.recheckAuthorization()
        await h.controller.settle()
        #expect(connection.sent == [.response(ResponseEnvelope(id: waiting.id, outcome: .paused))])
        #expect(h.presenter.visible.isEmpty)
    }

    @Test func thePeriodicCheckAsksNothingWhileNothingWaits() async {
        let h = Harness()
        h.controller.recheckAuthorization()
        await h.controller.settle()
        #expect(h.presenter.authorizationChecks == 0)
    }

    @Test func aTerminalAnswerQueuedBehindTheAuthorizationCheckStillRemovesTheRequest() async {
        let h = Harness()
        let r = request()
        let connection = FakeConnection()
        let id = h.controller.register(connection)
        h.controller.received(.request(r), from: id)
        h.controller.closed(id)  // arrives while the authorization check is suspended
        await h.controller.settle()
        #expect(h.controller.store.entries.isEmpty)
        #expect(h.presenter.visible.isEmpty)
        #expect(connection.sent.isEmpty)
    }

    @Test func questionsAreAskedOneAtATimeAndTheHookIsAnsweredOnceAfterTheLast() async {
        let h = Harness()
        let r = request(kind: .question, input: twoQuestions)
        let (connection, _) = await h.send(.request(r))
        #expect(h.presenter.visible[r.id.uuidString]?.title == "acme-api · Question 1 of 2")

        await h.respond(.action("option-1"), to: r.id)  // Orange
        let second = h.presenter.visible[r.id.uuidString]
        #expect(second?.title == "acme-api · Question 2 of 2")
        #expect(second?.playsSound == false)  // a follow-up, not a new request
        #expect(connection.sent.isEmpty)

        await h.respond(.text(action: "reply", text: "1, 9"), to: r.id)
        #expect(h.presenter.visible[r.id.uuidString]?.body.hasPrefix("⚠︎ Reply with option numbers, e.g. 1, 3") == true)
        #expect(connection.sent.isEmpty)

        await h.respond(.text(action: "reply", text: "1, 3"), to: r.id)
        #expect(
            connection.sent == [
                decided(r.id, .answer(["Which colour?": "Orange", "Which do you like?": "Blue, Green"]))
            ])
        #expect(h.presenter.visible.isEmpty)
    }

    @Test func requestChangesNeedsFeedback() async {
        let h = Harness()
        let r = request(kind: .plan, input: .object(["plan": "# Add a cache\n1. Measure\n2. Cache"]))
        let (connection, _) = await h.send(.request(r))
        #expect(h.presenter.visible[r.id.uuidString]?.title == "acme-api · Plan to approve")

        let postsBefore = h.presenter.posted.count
        await h.respond(.text(action: "request-changes", text: "   "), to: r.id)
        #expect(connection.sent.isEmpty)
        #expect(h.presenter.posted.count == postsBefore + 1)  // shown again, still answerable

        await h.respond(.text(action: "request-changes", text: "Add tests first"), to: r.id)
        #expect(connection.sent == [decided(r.id, .requestChanges("Add tests first"))])
    }

    @Test func clickingANotificationOpensTheSession() async {
        let h = Harness()
        let r = request()
        let (connection, _) = await h.send(.request(r))
        await h.respond(.defaultClick, to: r.id)
        #expect(connection.sent == [decided(r.id, .openInTerminal)])
        #expect(h.terminal.opened == [SessionPlace(terminal: hint, folder: nil)])
        #expect(h.presenter.visible.isEmpty)
    }

    @Test func finishedIsPostedAndGoesAwayWhenTheSessionMovesOn() async {
        let h = Harness()
        _ = await h.send(
            .notify(
                NotifyEnvelope(
                    sessionID: "s1", project: acme, kind: .finished,
                    message: "All tests pass.", terminal: hint)))
        let finished = h.presenter.posted.first
        #expect(finished?.title == "acme-api · Finished")
        #expect(finished?.body == "All tests pass.")
        #expect(finished?.actions.isEmpty == true)
        _ = await h.send(.clear(sessionID: "s1"))
        #expect(h.presenter.visible.isEmpty)
    }

    @Test func aTimedOutRequestStaysAsASilentHeadsUp() async {
        let h = Harness()
        let r = request()
        let connection = FakeConnection()
        let id = h.controller.register(connection)
        h.controller.received(.request(r), from: id)
        h.controller.received(.timedOut(id: r.id), from: id)
        h.controller.closed(id)
        await h.controller.settle()
        let shown = h.presenter.visible[r.id.uuidString]
        #expect(shown?.title == "acme-api · Timed out")
        #expect(shown?.playsSound == false)
        await h.respond(.action("approve"), to: r.id)
        #expect(connection.sent.isEmpty)  // no decision after the hook gave up
    }

    @Test func responsesToUnknownOrDismissedNotificationsChangeNothing() async {
        let h = Harness()
        let r = request()
        let (connection, _) = await h.send(.request(r))
        let postsBefore = h.presenter.posted.count
        h.controller.handle(.action("approve"), identifier: UUID().uuidString, categoryIdentifier: "permission")
        await h.respond(.dismissed, to: r.id)
        #expect(connection.sent.isEmpty)
        #expect(h.presenter.posted.count == postsBefore)
    }

    @Test func whilePausedRequestsGoToTheTerminal() async {
        let h = Harness()
        h.controller.pause(minutes: 30)
        #expect(h.controller.isPaused)
        let r = request()
        let (connection, _) = await h.send(.request(r))
        #expect(connection.sent == [.response(ResponseEnvelope(id: r.id, outcome: .paused))])
        #expect(h.presenter.posted.isEmpty)
        h.controller.resume()
        #expect(!h.controller.isPaused)
    }

    @Test func stoppingRemovesEveryNotificationAndClosesTheHooks() async {
        let h = Harness()
        let r = request()
        let (connection, _) = await h.send(.request(r))
        h.controller.stop()
        #expect(connection.isClosed)  // the hook sees EOF: terminal dialog
        #expect(h.presenter.visible.isEmpty)
    }

    @Test func theAuthorizationIsLoggedAtLaunch() async {
        let h = Harness()
        await h.controller.prepareNotifications()
        #expect(h.log.lines.contains("notifications: authorized, style alert"))
    }

    // MARK: Status queries (hook-me-up-setup doctor and notifications)

    @Test func aStatusQueryGetsOneStatusAndTheConnectionCloses() async {
        let h = Harness(version: "0.2.0", build: "0.2.0")
        let r = request()
        _ = await h.send(.request(r))
        h.presenter.current = NotificationAuthorization(status: .authorized, alertStyle: .banner)
        let entries = h.controller.store.entries
        let posted = h.presenter.posted
        let checks = h.presenter.authorizationChecks

        let (connection, id) = await h.send(.statusQuery)
        let expected = AgentStatus(
            version: "0.2.0", build: "0.2.0",
            notifications: NotificationAuthorization(status: .authorized, alertStyle: .banner), paused: false,
            pendingCount: 1)
        #expect(connection.sent == [.status(expected)])
        #expect(connection.isClosed)
        #expect(h.presenter.authorizationChecks == checks + 1)
        // Read only: the entries and the notifications stay as they were.
        #expect(h.controller.store.entries == entries)
        #expect(h.presenter.posted == posted)
        #expect(h.presenter.removed.isEmpty)
        #expect(h.log.lines.last == "connection \(id): status query")
    }

    @Test func aStatusQueryReportsAPauseAndNotificationsOffWithoutReleasingAnything() async {
        let h = Harness()
        let r = request()
        let (hook, _) = await h.send(.request(r))
        h.presenter.current = NotificationAuthorization(status: .denied, alertStyle: .none)
        h.controller.pause(minutes: 30)
        let (connection, _) = await h.send(.statusQuery)
        guard case .status(let status)? = connection.sent.first else {
            Issue.record("no status: \(connection.sent)")
            return
        }
        #expect(status.paused)
        #expect(status.notifications.status == .denied)
        #expect(status.pendingCount == 1)
        #expect(hook.sent.isEmpty && !hook.isClosed)  // the waiting request is not touched
        #expect(h.controller.store.entries.map(\.id) == [r.id])
    }

    @Test func aStatusQueryOnARequestConnectionEndsThatRequest() async {
        // A confused peer: a request, then a status query on the same connection. Closing
        // the connection ends the request, as when the hook goes away.
        let h = Harness()
        let r = request()
        let (connection, id) = await h.send(.request(r))
        h.controller.received(.statusQuery, from: id)
        await h.controller.settle()
        #expect(connection.isClosed)
        #expect(h.controller.store.entries.isEmpty)
        #expect(h.presenter.visible.isEmpty)
    }

    // MARK: Test notification (hook-me-up-setup notifications --test)

    @Test func aTestNotificationIsPostedOutsideTheEntriesAndTheConnectionCloses() async {
        let h = Harness()
        h.presenter.current = NotificationAuthorization(status: .authorized, alertStyle: .banner)
        let (connection, id) = await h.send(.testNotification)
        #expect(connection.sent.isEmpty)
        #expect(connection.isClosed)
        #expect(h.presenter.posted == [NativeNotification.testSpec(alertStyle: .banner)])
        #expect(h.presenter.posted.first?.identifier == "hook-me-up-test")
        #expect(h.controller.store.entries.isEmpty)
        #expect(h.log.lines.last == "connection \(id): test notification posted")

        // The ledger doesn't know it: requests coming and going never remove it.
        let r = request()
        _ = await h.send(.request(r))
        await h.respond(.action("approve"), to: r.id)
        #expect(!h.presenter.removed.contains("hook-me-up-test"))
        #expect(h.presenter.visible["hook-me-up-test"] != nil)

        // Clicking it answers nothing and changes nothing.
        let before = h.presenter.posted.count
        h.controller.handle(.defaultClick, identifier: "hook-me-up-test", categoryIdentifier: "")
        await h.controller.settle()
        #expect(h.terminal.opened.isEmpty)
        #expect(h.presenter.posted.count == before)
    }

    @Test func noTestNotificationWithoutPermission() async {
        let h = Harness()
        h.presenter.current = NotificationAuthorization(status: .denied, alertStyle: .none)
        let (connection, id) = await h.send(.testNotification)
        #expect(connection.isClosed)
        #expect(h.presenter.posted.isEmpty)
        #expect(h.log.lines.last == "connection \(id): test notification skipped (notifications are off)")
        h.presenter.current = NotificationAuthorization(status: .notDetermined, alertStyle: .none)
        _ = await h.send(.testNotification)
        #expect(h.presenter.posted.isEmpty)
    }
}
