import Foundation

/// The entries the agent shows (one native notification each) and the rules around
/// them: order, replacement per session, timing out and pause. A value type with
/// explicit times, so it is fully testable.
public struct PendingStore: Sendable {
    /// One request or heads-up shown to the user.
    public struct Entry: Identifiable, Equatable, Sendable {
        /// Whether a hook is still waiting for the entry.
        public enum State: String, Equatable, Sendable {
            /// The hook waits for a decision.
            case pending
            /// The hook gave up ("Timed out — answer in the terminal"); never decidable.
            case timedOut
        }

        /// The request id (or a fresh id for waiting/finished heads-ups).
        public var id: UUID
        /// The Claude Code session the entry belongs to.
        public var sessionID: String
        /// What the entry asks for.
        public var kind: EntryKind
        /// Plain-language text for the notification.
        public var summary: RequestSummary
        /// The project the session runs in.
        public var project: ProjectInfo
        /// Where the session's terminal is ("Open session").
        public var terminal: TerminalHint
        /// Whether a hook is still waiting for it.
        public var state: State
        /// The folder Claude Code was started in, when the hook sent it.
        public var sessionFolder: String?
        /// Optional CLI label.
        public var client: HookClient?

        /// Creates an entry.
        init(
            id: UUID, sessionID: String, kind: EntryKind, summary: RequestSummary, project: ProjectInfo,
            terminal: TerminalHint, state: State = .pending, sessionFolder: String? = nil, client: HookClient? = nil
        ) {
            self.id = id
            self.sessionID = sessionID
            self.kind = kind
            self.summary = summary
            self.project = project
            self.terminal = terminal
            self.state = state
            self.sessionFolder = sessionFolder
            self.client = client
        }

        /// Blocking entries have a hook waiting on a connection; they end with a decision,
        /// with that connection closing, or when the agent releases them (the session moved
        /// on, notifications turned off).
        var isBlocking: Bool { kind == .permission || kind == .question || kind == .plan }
        /// Still tied to a live hook. A timed-out entry is only a heads-up: its hook is
        /// gone, so it goes away with the session's waiting/finished entries.
        var isLive: Bool { isBlocking && state != .timedOut }
    }

    /// All entries in arrival order.
    public private(set) var entries: [Entry] = []
    private var pausedUntil: Date?

    /// Creates an empty store.
    public init() {}

    /// Appends `entry` (existing entries never move). The session's earlier waiting,
    /// finished and timed-out entries are replaced by it.
    mutating func add(_ entry: Entry) {
        entries.removeAll { $0.id != entry.id && $0.sessionID == entry.sessionID && !$0.isLive }
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
    }

    /// Removes the entry with `id`, if any.
    mutating func remove(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    /// The session moved on (new prompt, session end): drop its waiting/finished and
    /// timed-out entries. Live permission/question/plan entries are not cleared here:
    /// `AgentCore` first answers their hooks (`.paused`) and removes them, so a request
    /// never disappears while its hook still waits for an answer.
    mutating func clear(sessionID: String) {
        entries.removeAll { $0.sessionID == sessionID && !$0.isLive }
    }

    /// The hook gave up: the entry stays as a heads-up but can no longer be decided.
    mutating func markTimedOut(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].state == .pending else { return }
        entries[index].state = .timedOut
    }

    /// Pauses until `until`: requests go to the terminal meanwhile.
    mutating func pause(until: Date) {
        pausedUntil = until
    }

    /// Ends a pause early.
    mutating func resume() {
        pausedUntil = nil
    }

    /// Whether a pause is in effect at `now`.
    public func isPaused(now: Date) -> Bool {
        guard let pausedUntil else { return false }
        return now < pausedUntil
    }
}
