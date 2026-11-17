import Foundation
import Testing

@testable import HookMeUpCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let later = t0 + 10

private func request(
    _ id: UUID = UUID(), session: String = "s1", kind: EntryKind = .permission,
    tty: String? = "ttys001"
) -> RequestEnvelope {
    RequestEnvelope(
        id: id, sessionID: session, project: ProjectInfo(name: "proj", gitRoot: nil, branch: nil, worktree: nil),
        summary: RequestSummary(
            kind: kind, title: "Run a command", description: "List files", tags: [], origin: nil),
        input: .object(["command": "ls"]), terminal: TerminalHint(ancestorPIDs: [42], tty: tty), sessionPermissions: [])
}

private func notify(_ kind: EntryKind, session: String = "s1", message: String = "Done.") -> WireMessage {
    .notify(
        NotifyEnvelope(
            sessionID: session, project: ProjectInfo(name: "proj", gitRoot: nil, branch: nil, worktree: nil),
            kind: kind, message: message, terminal: TerminalHint(ancestorPIDs: [7], tty: nil)))
}

private func response(_ id: UUID, _ outcome: ResponseOutcome) -> WireMessage {
    .response(ResponseEnvelope(id: id, outcome: outcome))
}

@Suite struct AgentCoreTests {
    @Test func requestAddsAnEntryAndWaitsForTheUser() {
        var core = AgentCore()
        let r = request()
        #expect(core.receive(.request(r), from: 1, now: t0) == [])
        #expect(core.store.entries.map(\.id) == [r.id])
        #expect(core.request(for: r.id) == r)
    }

    @Test func requestWhilePausedRepliesPausedAndCloses() {
        var core = AgentCore()
        core.pause(until: t0 + 1800)
        let r = request()
        #expect(core.receive(.request(r), from: 1, now: t0) == [.send(1, response(r.id, .paused)), .close(1)])
        #expect(core.store.entries.isEmpty)
        core.resume()
        #expect(core.receive(.request(request()), from: 2, now: t0) == [])
        #expect(core.store.entries.count == 1)
    }

    @Test func notificationsWhilePausedAreDropped() {
        var core = AgentCore()
        core.pause(until: t0 + 1800)
        #expect(core.receive(notify(.waiting), from: 1, now: t0) == [])
        #expect(core.receive(notify(.finished), from: 2, now: t0) == [])
        #expect(core.store.entries.isEmpty)
    }

    @Test func terminalAnswerClosesConnectionAndRemovesEntry() {
        // The hook's connection closes before a decision: it was interrupted (Esc) or its
        // process is gone.
        var core = AgentCore()
        let r = request()
        _ = core.receive(.request(r), from: 1, now: t0)
        #expect(core.connectionClosed(1, now: later) == [])
        #expect(core.store.entries.isEmpty)
        // A late answer on the (already gone) entry sends nothing: no double decision.
        #expect(core.resolve(id: r.id, .approve, now: later + 10) == [])
    }

    @Test func fireAndForgetConnectionCloseRemovesNothing() {
        var core = AgentCore()
        _ = core.receive(notify(.waiting), from: 5, now: t0)
        #expect(core.connectionClosed(5, now: t0) == [])
        #expect(core.store.entries.count == 1)
        _ = core.receive(.clear(sessionID: "other"), from: 6, now: t0)
        #expect(core.connectionClosed(6, now: t0) == [])
        #expect(core.store.entries.count == 1)
    }

    @Test func resolveSendsExactlyOneResponseThenCloses() {
        var core = AgentCore()
        let r = request()
        _ = core.receive(.request(r), from: 3, now: t0)
        #expect(
            core.resolve(id: r.id, .approve, now: later) == [.send(3, response(r.id, .decided(.approve))), .close(3)])
        #expect(core.store.entries.isEmpty)
        #expect(core.resolve(id: r.id, .deny, now: later + 1) == [])
        #expect(core.connectionClosed(3, now: later + 1) == [])  // a late close is harmless
    }

    @Test func openInTerminalRepliesAndActivates() {
        var core = AgentCore()
        let r = request()
        _ = core.receive(.request(r), from: 1, now: t0)
        #expect(
            core.resolve(id: r.id, .openInTerminal, now: later) == [
                .send(1, response(r.id, .decided(.openInTerminal))), .close(1),
                .openSession(SessionPlace(terminal: r.terminal, folder: nil)),
            ])
        #expect(core.store.entries.isEmpty)

        _ = core.receive(notify(.finished), from: 2, now: later + 1)
        let finished = core.store.entries[0]
        #expect(
            core.resolve(id: finished.id, .openInTerminal, now: later + 10) == [
                .openSession(SessionPlace(terminal: finished.terminal, folder: nil))
            ])
        #expect(core.store.entries.isEmpty)
    }

    @Test func timedOutKeepsHeadsUpUntilSessionMovesOn() {
        var core = AgentCore()
        let r = request()
        _ = core.receive(.request(r), from: 1, now: t0)
        #expect(core.receive(.timedOut(id: r.id), from: 1, now: t0 + 590) == [])
        #expect(core.connectionClosed(1, now: t0 + 590) == [])
        #expect(core.store.entries.map(\.state) == [.timedOut])  // "Timed out — answer in terminal"
        // No decision can be sent any more; Open session still works.
        #expect(core.resolve(id: r.id, .approve, now: t0 + 600) == [])
        _ = core.receive(.clear(sessionID: "s1"), from: 9, now: t0 + 700)
        #expect(core.store.entries.isEmpty)
    }

    @Test func timedOutFromAnotherConnectionIsIgnored() {
        var core = AgentCore()
        let r = request()
        _ = core.receive(.request(r), from: 1, now: t0)
        _ = core.receive(.timedOut(id: r.id), from: 2, now: t0 + 1)
        #expect(core.store.entries.map(\.state) == [.pending])
    }

    @Test func oneRequestPerConnectionAndUniqueIDs() {
        var core = AgentCore()
        let r = request()
        _ = core.receive(.request(r), from: 1, now: t0)
        #expect(core.receive(.request(request()), from: 1, now: t0) == [.close(1)])
        #expect(core.receive(.request(r), from: 2, now: t0) == [.close(2)])  // duplicate id
        #expect(core.store.entries.count == 1)
        #expect(
            core.resolve(id: r.id, .approve, now: later) == [.send(1, response(r.id, .decided(.approve))), .close(1)])
    }

    @Test func unexpectedMessagesCloseTheConnection() {
        var core = AgentCore()
        let id = UUID()
        #expect(core.receive(response(id, .decided(.approve)), from: 4, now: t0) == [.close(4)])
        #expect(core.store.entries.isEmpty)
        // The agent answers status queries itself; one that reaches the core is a stray.
        #expect(core.receive(.statusQuery, from: 5, now: t0) == [.close(5)])
        let status = AgentStatus(
            version: "1", build: "1", notifications: NotificationAuthorization(status: .authorized, alertStyle: .alert),
            paused: false, pendingCount: 0)
        #expect(core.receive(.status(status), from: 6, now: t0) == [.close(6)])
        #expect(core.receive(.testNotification, from: 7, now: t0) == [.close(7)])
        #expect(core.store.entries.isEmpty)
    }

    @Test func notifyBecomesEntryWithText() {
        var core = AgentCore()
        #expect(core.receive(notify(.finished, message: "All tests pass."), from: 1, now: t0) == [])
        let entry = core.store.entries[0]
        #expect(entry.kind == .finished)
        #expect(entry.summary.title == "Finished")
        #expect(entry.summary.description == "All tests pass.")
        _ = core.receive(notify(.waiting, message: "Claude needs your input"), from: 2, now: t0 + 1)
        #expect(core.store.entries.map(\.summary.title) == ["Waiting for your reply"])  // replaced Finished
    }

    // MARK: The session moves on: its waiting requests are released

    /// Claude Code does not stop the hook when the request is answered in the terminal
    /// dialog. The session's Stop hook (`finished`) tells the agent it moved on: every
    /// request of that session still waiting gets `.paused` (the hook prints nothing)
    /// instead of timing out later.
    @Test func finishedReleasesTheSessionsWaitingRequests() {
        var core = AgentCore()
        let first = request()
        let second = request(kind: .plan)
        let other = request(session: "s2")
        _ = core.receive(.request(first), from: 1, now: t0)
        _ = core.receive(.request(second), from: 2, now: t0)
        _ = core.receive(.request(other), from: 3, now: t0)
        #expect(
            core.receive(notify(.finished), from: 4, now: later) == [
                .send(1, response(first.id, .paused)), .close(1),
                .send(2, response(second.id, .paused)), .close(2),
            ])
        #expect(core.store.entries.map(\.id).first == other.id)
        #expect(core.store.entries.map(\.sessionID) == ["s2", "s1"])
        #expect(core.store.entries.last?.kind == .finished)
        #expect(core.request(for: other.id) == other)  // another session's request is untouched
        // Released once: no second response, a late close changes nothing.
        #expect(core.resolve(id: first.id, .approve, now: later + 1) == [])
        #expect(core.connectionClosed(1, now: later + 1) == [])
        #expect(core.connectionClosed(2, now: later + 1) == [])
        #expect(core.store.entries.count == 2)
    }

    /// A new prompt or the session's end releases its waiting requests the same way; its
    /// timed-out heads-up just goes (its hook already gave up).
    @Test func clearReleasesTheSessionsWaitingRequests() {
        var core = AgentCore()
        let waiting = request()
        let timedOut = request()
        let other = request(session: "s2")
        _ = core.receive(.request(waiting), from: 1, now: t0)
        _ = core.receive(.request(timedOut), from: 2, now: t0)
        _ = core.receive(.timedOut(id: timedOut.id), from: 2, now: t0 + 590)
        _ = core.receive(.request(other), from: 3, now: t0)
        #expect(
            core.receive(.clear(sessionID: "s1"), from: 4, now: t0 + 600) == [
                .send(1, response(waiting.id, .paused)), .close(1),
            ])
        #expect(core.store.entries.map(\.id) == [other.id])
        #expect(core.resolve(id: waiting.id, .deny, now: t0 + 601) == [])
        #expect(core.connectionClosed(1, now: t0 + 601) == [])
        #expect(core.connectionClosed(2, now: t0 + 601) == [])
        #expect(core.request(for: other.id) == other)
    }

    /// Waiting for input does not mean the session moved on: its requests stay.
    @Test func waitingNotifyReleasesNothing() {
        var core = AgentCore()
        let r = request()
        _ = core.receive(.request(r), from: 1, now: t0)
        #expect(core.receive(notify(.waiting), from: 2, now: later) == [])
        #expect(core.store.entries.map(\.id).first == r.id)
        #expect(core.store.entries.map(\.kind) == [.permission, .waiting])
        #expect(core.request(for: r.id) == r)
    }

    /// A pause drops the Finished heads-up but not the release: the hook would otherwise
    /// time out on a request already answered.
    @Test func finishedWhilePausedStillReleasesButAddsNoHeadsUp() {
        var core = AgentCore()
        let r = request()
        _ = core.receive(.request(r), from: 1, now: t0)
        core.pause(until: t0 + 1800)
        #expect(core.receive(notify(.finished), from: 2, now: later) == [.send(1, response(r.id, .paused)), .close(1)])
        #expect(core.store.entries.isEmpty)
    }

    @Test func aRequestAfterFinishedStaysLive() {
        var core = AgentCore()
        _ = core.receive(notify(.finished), from: 1, now: t0)
        let r = request()
        #expect(core.receive(.request(r), from: 2, now: later) == [])
        #expect(core.store.entries.map(\.id) == [r.id])  // replaced the Finished heads-up
        #expect(
            core.resolve(id: r.id, .approve, now: later + 1) == [
                .send(2, response(r.id, .decided(.approve))), .close(2),
            ])
    }

    @Test func requestKindIsAlwaysABlockingKind() {
        var core = AgentCore()
        let odd = request(kind: .finished)
        _ = core.receive(.request(odd), from: 1, now: t0)
        #expect(core.store.entries.first?.kind == .permission)
    }
}

/// Pivot: native notifications. Several questions are answered one notification at a
/// time; the hook gets a single decision after the last one.
@Suite struct AgentCoreNativeTests {
    private static let questions: JSONValue = .object([
        "questions": .array([
            .object([
                "question": "Which colour?", "multiSelect": .bool(false),
                "options": .array([.object(["label": "Blue"]), .object(["label": "Orange"])]),
            ]),
            .object([
                "question": "Which do you like?", "multiSelect": .bool(true),
                "options": .array([
                    .object(["label": "Blue"]), .object(["label": "Orange"]), .object(["label": "Green"]),
                ]),
            ]),
        ])
    ])

    private func questionRequest(input: JSONValue = questions) -> RequestEnvelope {
        RequestEnvelope(
            id: UUID(), sessionID: "s1", project: ProjectInfo(name: "proj", gitRoot: nil, branch: nil, worktree: nil),
            summary: RequestSummary(
                kind: .question, title: "Which colour?", description: "", tags: [], origin: nil),
            input: input, terminal: TerminalHint(ancestorPIDs: [], tty: nil))
    }

    /// Questions the agent cannot ask one by one (a repeated text, or no readable
    /// question) go to the terminal at once instead of waiting with no way to answer.
    @Test(arguments: [
        JSONValue.object([
            "questions": .array([
                .object(["question": "Which?", "options": .array([.object(["label": "A"])])]),
                .object(["question": "Which?", "options": .array([.object(["label": "B"])])]),
            ])
        ]),
        .object(["questions": .array([])]),
        .object(["command": "ls"]),
    ])
    func questionsThatCannotBeAskedFailOpen(_ input: JSONValue) {
        var core = AgentCore()
        let r = questionRequest(input: input)
        #expect(
            core.receive(.request(r), from: 1, now: t0)
                == [.send(1, .response(ResponseEnvelope(id: r.id, outcome: .paused))), .close(1)])
        #expect(core.store.entries.isEmpty)
    }

    @Test func questionsAreAnsweredInOrderAndTheDecisionIsSentOnceAfterTheLast() {
        var core = AgentCore()
        let r = questionRequest()
        _ = core.receive(.request(r), from: 1, now: t0)
        #expect(core.questionProgress(for: r.id)?.step == 0)
        #expect(core.questionProgress(for: r.id)?.total == 2)
        #expect(core.questionProgress(for: r.id)?.question.text == "Which colour?")
        #expect(core.answerQuestion(id: r.id, step: 1, labels: ["Blue"], now: t0) == [])  // not yet asked
        #expect(core.answerQuestion(id: r.id, step: 0, labels: ["Orange"], now: t0) == [])  // nothing sent yet
        #expect(core.questionProgress(for: r.id)?.step == 1)
        #expect(core.questionProgress(for: r.id)?.question.text == "Which do you like?")
        let effects = core.answerQuestion(id: r.id, step: 1, labels: ["Blue", "Green"], now: t0)
        #expect(
            effects == [
                .send(
                    1,
                    .response(
                        ResponseEnvelope(
                            id: r.id,
                            outcome: .decided(
                                .answer([
                                    "Which colour?": "Orange", "Which do you like?": "Blue, Green",
                                ]))))),
                .close(1),
            ])
        #expect(core.answerQuestion(id: r.id, step: 1, labels: ["Blue"], now: t0) == [])  // exactly once
        #expect(core.store.entries.isEmpty)
    }

    @Test func invalidReplyHintIsShownUntilAValidAnswer() {
        var core = AgentCore()
        let r = questionRequest()
        _ = core.receive(.request(r), from: 1, now: t0)
        core.setReplyHint(id: r.id, step: 0, hint: "Reply with 1–2 or your own answer")
        #expect(core.questionProgress(for: r.id)?.hint == "Reply with 1–2 or your own answer")
        _ = core.answerQuestion(id: r.id, step: 0, labels: ["Blue"], now: t0)
        #expect(core.questionProgress(for: r.id)?.hint == nil)
    }

    @Test func terminalAnswerMidwayDropsPartialAnswers() {
        var core = AgentCore()
        let r = questionRequest()
        _ = core.receive(.request(r), from: 1, now: t0)
        _ = core.answerQuestion(id: r.id, step: 0, labels: ["Blue"], now: t0)
        _ = core.connectionClosed(1, now: t0)  // answered in the terminal
        #expect(core.questionProgress(for: r.id) == nil)
        #expect(core.answerQuestion(id: r.id, step: 1, labels: ["Blue"], now: t0) == [])
    }

    /// A question answered in the terminal midway: releasing it forgets the answers so far.
    @Test func releasedQuestionForgetsItsProgress() {
        var core = AgentCore()
        let r = questionRequest()
        _ = core.receive(.request(r), from: 1, now: t0)
        _ = core.answerQuestion(id: r.id, step: 0, labels: ["Blue"], now: t0)
        core.setReplyHint(id: r.id, step: 1, hint: "Reply with option numbers")
        #expect(
            core.receive(.clear(sessionID: "s1"), from: 2, now: t0)
                == [.send(1, .response(ResponseEnvelope(id: r.id, outcome: .paused))), .close(1)])
        #expect(core.questionProgress(for: r.id) == nil)
        #expect(core.answerQuestion(id: r.id, step: 1, labels: ["Blue"], now: t0) == [])
        #expect(core.store.entries.isEmpty)
    }

    @Test func withoutNotificationPermissionRequestsFailOpenAndNotificationsAreDropped() {
        var core = AgentCore()
        #expect(core.setNotificationsAllowed(false) == [])  // nothing waiting yet
        let r = questionRequest()
        #expect(
            core.receive(.request(r), from: 1, now: t0)
                == [.send(1, .response(ResponseEnvelope(id: r.id, outcome: .paused))), .close(1)])  // terminal dialog
        #expect(
            core.receive(
                .notify(
                    NotifyEnvelope(
                        sessionID: "s", project: ProjectInfo(name: "p", gitRoot: nil, branch: nil, worktree: nil),
                        kind: .finished, message: "Done", terminal: TerminalHint(ancestorPIDs: [], tty: nil))),
                from: 2, now: t0) == [])
        #expect(core.store.entries.isEmpty)
        #expect(core.setNotificationsAllowed(true) == [])  // the user enabled notifications: next request is shown
        #expect(core.receive(.request(questionRequest()), from: 3, now: t0) == [])
        #expect(core.store.entries.count == 1)
    }

    /// Notifications turned off while requests wait: nobody can answer them any more, so
    /// each hook gets `.paused` (terminal dialog) and every entry goes.
    @Test func revokingNotificationsReleasesWaitingRequests() {
        var core = AgentCore()
        let first = questionRequest()
        let second = questionRequest()
        _ = core.receive(.request(first), from: 1, now: t0)
        _ = core.receive(.request(second), from: 2, now: t0)
        _ = core.receive(
            .notify(
                NotifyEnvelope(
                    sessionID: "s9", project: ProjectInfo(name: "p", gitRoot: nil, branch: nil, worktree: nil),
                    kind: .finished, message: "Done", terminal: TerminalHint(ancestorPIDs: [], tty: nil))),
            from: 3, now: t0)
        #expect(core.store.entries.count == 3)
        #expect(
            core.setNotificationsAllowed(false) == [
                .send(1, .response(ResponseEnvelope(id: first.id, outcome: .paused))), .close(1),
                .send(2, .response(ResponseEnvelope(id: second.id, outcome: .paused))), .close(2),
            ])
        #expect(core.store.entries.isEmpty)
        #expect(core.questionProgress(for: first.id) == nil)
        #expect(core.setNotificationsAllowed(false) == [])  // only once
        #expect(core.resolve(id: first.id, .approve, now: t0) == [])  // no second answer
        #expect(core.connectionClosed(1, now: t0) == [])
    }

    /// Opening a session hands over where it runs: its terminal and its project folder (the
    /// git root, else the working folder outside git).
    @Test func openingASessionNamesItsFolder() {
        var core = AgentCore()
        var inRepository = questionRequest()
        inRepository.project = ProjectInfo(
            name: "acme-api", gitRoot: "/home/dev/projects/acme-api", branch: "main", worktree: nil)
        _ = core.receive(.request(inRepository), from: 1, now: t0)
        #expect(
            core.resolve(id: inRepository.id, .openInTerminal, now: t0).last
                == .openSession(SessionPlace(terminal: inRepository.terminal, folder: "/home/dev/projects/acme-api")))

        _ = core.receive(
            .notify(
                NotifyEnvelope(
                    sessionID: "s9",
                    project: ProjectInfo(
                        name: "scratch", gitRoot: nil, branch: nil, worktree: nil, folder: "/home/dev/scratch"),
                    kind: .finished, message: "Done", terminal: TerminalHint(ancestorPIDs: [], tty: nil))),
            from: 2, now: t0)
        let finished = core.store.entries[0]
        #expect(
            core.resolve(id: finished.id, .openInTerminal, now: t0)
                == [.openSession(SessionPlace(terminal: finished.terminal, folder: "/home/dev/scratch"))])
    }

    /// The folder Claude Code was started in wins over the git root (a worktree, a
    /// subfolder of a monorepo) and over the working folder.
    @Test func theSessionFolderIsPreferredForOpening() {
        var core = AgentCore()
        var request = questionRequest()
        request.project = ProjectInfo(
            name: "acme-api", gitRoot: "/home/dev/projects/acme-api/.claude/worktrees/fix", branch: "fix",
            worktree: "fix")
        request.sessionFolder = "/home/dev/projects/acme-api"
        _ = core.receive(.request(request), from: 1, now: t0)
        #expect(
            core.resolve(id: request.id, .openInTerminal, now: t0).last
                == .openSession(SessionPlace(terminal: request.terminal, folder: "/home/dev/projects/acme-api")))

        _ = core.receive(
            .notify(
                NotifyEnvelope(
                    sessionID: "s9",
                    project: ProjectInfo(
                        name: "scratch", gitRoot: nil, branch: nil, worktree: nil, folder: "/home/dev/scratch/sub"),
                    kind: .finished, message: "Done", terminal: TerminalHint(ancestorPIDs: [], tty: nil),
                    sessionFolder: "/home/dev/scratch")),
            from: 2, now: t0)
        let finished = core.store.entries[0]
        #expect(
            core.resolve(id: finished.id, .openInTerminal, now: t0)
                == [.openSession(SessionPlace(terminal: finished.terminal, folder: "/home/dev/scratch"))])
    }
}
