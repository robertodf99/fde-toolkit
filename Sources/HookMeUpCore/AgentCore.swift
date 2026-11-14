import Foundation

/// Opaque handle the agent app gives each accepted socket connection.
public typealias ConnectionID = Int

/// The agent's routing rules, free of sockets and UI: messages and the user's answers
/// go in, effects come out (send, close, open the terminal). The app executes them.
///
/// Invariants:
/// - at most one response per request, only on that request's connection, and only
///   for a live (pending) entry;
/// - a request connection closing before a decision removes its entry (the user
///   answered in the terminal and Claude Code cancelled the hook), except a
///   timed-out entry, which stays as a heads-up until the session moves on;
/// - fire-and-forget connections (notify, clear) never remove anything when they close;
/// - while paused, requests get `.paused` at once and notifications are dropped; so does a
///   question that cannot be asked one at a time (repeated or missing question texts);
public struct AgentCore: Sendable {
    /// Something for the app to do.
    public enum Effect: Equatable, Sendable {
        /// Send a message on a connection.
        case send(ConnectionID, WireMessage)
        /// Close a connection (the hook sees EOF).
        case close(ConnectionID)
        /// Bring a session's terminal forward.
        case activateTerminal(TerminalHint)
    }

    /// The entries waiting for the user.
    public private(set) var store = PendingStore()
    /// False while macOS does not allow our notifications: requests then get `.paused` at
    /// once (the hook prints nothing and the terminal dialog appears) and notifications
    /// are dropped. The app re-checks before each request (`setNotificationsAllowed`).
    public private(set) var notificationsAllowed = true
    /// Several AskUserQuestion questions are asked one notification at a time.
    private var questionStep: [UUID: Int] = [:]
    private var questionAnswers: [UUID: [String: [String]]] = [:]
    private var replyHints: [UUID: String] = [:]
    private var requests: [UUID: (connection: ConnectionID, envelope: RequestEnvelope)] = [:]
    private var requestOnConnection: [ConnectionID: UUID] = [:]

    /// Creates an agent core with no entries.
    public init() {}

    /// The request behind a live entry (tool input for questions and plans, the
    /// session permissions for "Approve for session").
    public func request(for id: UUID) -> RequestEnvelope? {
        requests[id]?.envelope
    }

    /// Handles a message from the hook on `connection`.
    public mutating func receive(_ message: WireMessage, from connection: ConnectionID, now: Date) -> [Effect] {
        switch message {
        case .request(let envelope):
            // One request per connection, unique ids.
            guard requestOnConnection[connection] == nil, requests[envelope.id] == nil,
                !store.entries.contains(where: { $0.id == envelope.id })
            else { return [.close(connection)] }
            // A question the agent cannot ask one at a time goes to the terminal at once.
            let unaskable = envelope.summary.kind == .question && QuestionForm(toolInput: envelope.input) == nil
            if store.isPaused(now: now) || !notificationsAllowed || unaskable {
                return [
                    .send(connection, .response(ResponseEnvelope(id: envelope.id, outcome: .paused))),
                    .close(connection),
                ]
            }
            let kind: EntryKind =
                [.permission, .question, .plan].contains(envelope.summary.kind) ? envelope.summary.kind : .permission
            var summary = envelope.summary
            summary.kind = kind
            let entry = PendingStore.Entry(
                id: envelope.id, sessionID: envelope.sessionID, kind: kind, summary: summary, project: envelope.project,
                terminal: envelope.terminal)
            store.add(entry)
            requests[envelope.id] = (connection, envelope)
            requestOnConnection[connection] = envelope.id
            return []

        case .notify(let note):
            guard !store.isPaused(now: now), notificationsAllowed, note.kind == .waiting || note.kind == .finished
            else {
                return []
            }
            let title = note.kind == .finished ? "Finished" : "Waiting for your reply"
            let entry = PendingStore.Entry(
                id: UUID(), sessionID: note.sessionID, kind: note.kind,
                summary: RequestSummary(
                    kind: note.kind, title: title, description: note.message, tags: [],
                    origin: nil),
                project: note.project, terminal: note.terminal)
            store.add(entry)
            return []

        case .clear(let sessionID):
            store.clear(sessionID: sessionID)
            return []

        case .timedOut(let id):
            // Only the hook that owns the request can time it out.
            guard requestOnConnection[connection] == id else { return [] }
            store.markTimedOut(id: id)
            return []

        case .response:
            return [.close(connection)]
        }
    }

    /// The peer closed `connection` (hook exited or was killed).
    public mutating func connectionClosed(_ connection: ConnectionID, now: Date) -> [Effect] {
        guard let id = requestOnConnection.removeValue(forKey: connection) else { return [] }
        requests[id] = nil
        forgetQuestions(id)
        if store.entries.first(where: { $0.id == id })?.state == .timedOut { return [] }
        store.remove(id: id)
        return []
    }

    /// The user's decision on an entry. Sent to the hook only for a pending entry
    /// with a live connection, at most once.
    public mutating func resolve(id: UUID, _ decision: UserDecision, now: Date) -> [Effect] {
        guard let entry = store.entries.first(where: { $0.id == id }) else { return [] }
        switch decision {
        case .openInTerminal:
            var effects: [Effect] = []
            if let request = takeRequest(id) {
                effects = [
                    .send(request.connection, .response(ResponseEnvelope(id: id, outcome: .decided(.openInTerminal)))),
                    .close(request.connection),
                ]
            }
            store.remove(id: id)
            return effects + [.activateTerminal(entry.terminal)]

        case .approve, .approveForSession, .deny, .answer, .approvePlan, .requestChanges:
            // Only a still-pending entry with a live hook can be decided, once.
            guard entry.state == .pending, let request = takeRequest(id) else { return [] }
            store.remove(id: id)
            return [
                .send(request.connection, .response(ResponseEnvelope(id: id, outcome: .decided(decision)))),
                .close(request.connection),
            ]
        }
    }

    /// Records whether notifications are allowed. Turning them off releases every waiting
    /// request with `.paused` (nobody could answer its notification any more) and drops
    /// all entries; the effects say which hooks to answer and close.
    public mutating func setNotificationsAllowed(_ allowed: Bool) -> [Effect] {
        let wasAllowed = notificationsAllowed
        notificationsAllowed = allowed
        guard wasAllowed, !allowed else { return [] }
        var effects: [Effect] = []
        for entry in store.entries {
            if let request = takeRequest(entry.id) {
                effects += [
                    .send(request.connection, .response(ResponseEnvelope(id: entry.id, outcome: .paused))),
                    .close(request.connection),
                ]
            }
            store.remove(id: entry.id)
        }
        return effects
    }

    /// Sends requests to the terminal until `date`.
    public mutating func pause(until date: Date) {
        store.pause(until: date)
    }

    /// Ends a pause early.
    public mutating func resume() {
        store.resume()
    }

    private mutating func takeRequest(_ id: UUID) -> (connection: ConnectionID, envelope: RequestEnvelope)? {
        guard let request = requests.removeValue(forKey: id) else { return nil }
        requestOnConnection[request.connection] = nil
        forgetQuestions(id)
        return request
    }

    // MARK: Questions, one notification at a time

    /// The question being asked now for a live question entry; nil otherwise.
    public func questionProgress(for id: UUID) -> QuestionProgress? {
        guard let request = requests[id]?.envelope, request.summary.kind == .question,
            let form = QuestionForm(toolInput: request.input)
        else { return nil }
        let step = questionStep[id] ?? 0
        guard form.questions.indices.contains(step) else { return nil }
        return QuestionProgress(
            step: step, total: form.questions.count, question: form.questions[step],
            hint: replyHints[id])
    }

    /// Records the answer to the question shown now. After the last question the hook
    /// gets one decision (all answers); an answer for any other step is ignored.
    public mutating func answerQuestion(id: UUID, step: Int, labels: [String], now: Date) -> [Effect] {
        guard let progress = questionProgress(for: id), progress.step == step, !labels.isEmpty,
            let entry = store.entries.first(where: { $0.id == id }), entry.state == .pending
        else { return [] }
        questionAnswers[id, default: [:]][progress.question.text] = labels
        replyHints[id] = nil
        if step + 1 < progress.total {
            questionStep[id] = step + 1
            return []
        }
        let answers = questionAnswers[id] ?? [:]
        return resolve(id: id, .answer(selections: answers), now: now)
    }

    /// Shows a hint with the current question after a reply that was not understood.
    public mutating func setReplyHint(id: UUID, step: Int, hint: String) {
        guard questionProgress(for: id)?.step == step else { return }
        replyHints[id] = hint
    }

    private mutating func forgetQuestions(_ id: UUID) {
        questionStep[id] = nil
        questionAnswers[id] = nil
        replyHints[id] = nil
    }
}
