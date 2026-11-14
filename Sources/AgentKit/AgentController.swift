import Combine
import Foundation
import HookMeUpCore
import HookMeUpIPC

/// Runs the agent: accepts hook connections, feeds their messages to `AgentCore`,
/// executes its effects and keeps one native notification per entry.
///
/// Everything runs on the main actor. Socket events and notification responses are
/// handled one at a time, in arrival order: a request waits for its authorization
/// check, and anything that arrives meanwhile (its connection closing, say) waits
/// behind it.
@MainActor
public final class AgentController: ObservableObject {
    /// The entries waiting for the user (the status menu shows their count).
    @Published public private(set) var store = PendingStore()
    /// Why the agent is not listening, when it could not start.
    @Published public private(set) var startError: String?

    static let howToEnableNotifications = """
        notifications are off for Hook Me Up, so every request goes to the terminal. \
        Turn them on in System Settings > Notifications > Hook Me Up, with the style set to Alerts.
        """

    private var core = AgentCore()
    private let presenter: any NotificationPresenting
    private let terminal: any TerminalActivating
    private let clock: any WallClock
    private let version: String
    private let build: String
    private let log: @MainActor (String) -> Void
    private var server: SocketServer?
    private var connections: [ConnectionID: any AgentConnection] = [:]
    private var nextConnectionID: ConnectionID = 1
    private var pauseTimer: Timer?
    private var notifications = NotificationLedger()
    private var lastEvent: Task<Void, Never>?
    private var hasLoggedNotificationsOff = false

    /// Creates a controller that shows entries with `presenter`, opens sessions with
    /// `terminal`, reads the time from `clock` and writes to `log`. `version` and `build`
    /// are the app's, reported to status queries.
    public init(
        presenter: any NotificationPresenting, terminal: any TerminalActivating,
        clock: any WallClock = SystemWallClock(), version: String = "unknown", build: String = "unknown",
        log: @escaping @MainActor (String) -> Void = { AgentLog.info($0) }
    ) {
        self.presenter = presenter
        self.terminal = terminal
        self.clock = clock
        self.version = version
        self.build = build
        self.log = log
    }

    /// Starts listening for hooks on `socketPath`.
    public func start(socketPath: URL) throws {
        let server = SocketServer(path: socketPath)
        try server.start { [weak self] connection in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.accept(connection) }
            }
        }
        self.server = server
        log("listening on \(socketPath.path)")
    }

    /// Asks for notification permission if macOS has not asked yet and logs the result.
    public func prepareNotifications() async {
        let authorization = await presenter.requestAuthorization()
        log("notifications: \(authorization)")
        noteAuthorization(authorization)
    }

    /// Stops listening, closes every connection (waiting hooks fall back to the
    /// terminal dialog) and removes the notifications.
    public func stop() {
        server?.stop()
        server = nil
        for connection in connections.values { connection.close() }
        connections.removeAll()
        let changes = notifications.update(to: [])
        if !changes.remove.isEmpty { presenter.remove(identifiers: changes.remove) }
    }

    /// Records why the agent could not start (shown in the status menu).
    public func reportStartError(_ message: String) {
        startError = message
    }

    /// Sends requests to the terminal for `minutes`.
    public func pause(minutes: Double) {
        let until = clock.now.addingTimeInterval(minutes * 60)
        core.pause(until: until)
        log("paused for \(Int(minutes)) min")
        publish()
        // Refresh the menu-bar item when the pause ends.
        pauseTimer?.invalidate()
        let timer = Timer(fire: until, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.publish() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pauseTimer = timer
    }

    /// Ends a pause early.
    public func resume() {
        core.resume()
        pauseTimer?.invalidate()
        pauseTimer = nil
        log("resumed")
        publish()
    }

    /// Whether requests currently go to the terminal because of a pause.
    public var isPaused: Bool { core.store.isPaused(now: clock.now) }

    /// Checks again whether notifications are allowed, so requests waiting when they were
    /// turned off are released to the terminal without waiting for the next request.
    /// Does nothing while no entry waits. The app calls it every minute.
    public func recheckAuthorization() {
        enqueue { controller in
            guard !controller.core.store.entries.isEmpty else { return }
            await controller.refreshAuthorization()
        }
    }

    /// What the user did with the notification `identifier` (an entry id).
    public func handle(_ response: NotificationResponse, identifier: String, categoryIdentifier: String) {
        enqueue { controller in
            controller.process(response, identifier: identifier, categoryIdentifier: categoryIdentifier)
        }
    }

    // MARK: Event queue

    /// Runs `work` after every earlier event, in order.
    private func enqueue(_ work: @escaping @MainActor (AgentController) async -> Void) {
        let previous = lastEvent
        lastEvent = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            await work(self)
        }
    }

    /// Waits until every queued event has been handled.
    func settle() async {
        while let pending = lastEvent {
            await pending.value
            if pending == lastEvent { return }
        }
    }

    // MARK: Socket events

    private func accept(_ connection: Connection) {
        let id = register(connection)
        connection.onClose = { [weak self] in
            // Runs on the reading queue, which is the main queue.
            MainActor.assumeIsolated { self?.closed(id) }
        }
        connection.startReading(queue: .main) { [weak self] message in
            MainActor.assumeIsolated { self?.received(message, from: id) }
        }
    }

    /// Adds a connection and returns its id.
    func register(_ connection: any AgentConnection) -> ConnectionID {
        let id = nextConnectionID
        nextConnectionID += 1
        connections[id] = connection
        return id
    }

    func received(_ message: WireMessage, from connection: ConnectionID) {
        enqueue { controller in
            if message == .statusQuery {
                await controller.answerStatusQuery(on: connection)
                return
            }
            if message.wantsNotification {
                await controller.refreshAuthorization()
            }
            controller.apply(controller.core.receive(message, from: connection, now: controller.clock.now))
            controller.log("connection \(connection): \(Self.describe(message)) -> \(controller.counts)")
        }
    }

    func closed(_ connection: ConnectionID) {
        enqueue { controller in
            controller.connections[connection] = nil
            let before = controller.core.store.entries.count
            controller.apply(controller.core.connectionClosed(connection, now: controller.clock.now))
            let removed = before - controller.core.store.entries.count
            controller.log(
                "connection \(connection) closed by peer"
                    + (removed > 0 ? "; removed \(removed) entry" : "") + " -> \(controller.counts)")
        }
    }

    /// Answers with one `status` (no request content) and closes the connection. Reads
    /// the notification settings without acting on them, so the entries stay as they are.
    private func answerStatusQuery(on connection: ConnectionID) async {
        let authorization = await presenter.authorization()
        let status = AgentStatus(
            version: version, build: build, notifications: authorization, paused: isPaused,
            pendingCount: core.store.entries.count)
        do {
            try connections[connection]?.send(.status(status))
        } catch {
            log("send on connection \(connection) failed: \(error)")
        }
        log("connection \(connection): status query")
        closeLocally(connection)
    }

    /// Closes a connection the agent is done with. A request a confused peer sent on the
    /// same connection ends with it, as if the peer had closed it.
    private func closeLocally(_ connection: ConnectionID) {
        connections.removeValue(forKey: connection)?.close()
        let before = core.store.entries.count
        let effects = core.connectionClosed(connection, now: clock.now)
        if core.store.entries.count != before || !effects.isEmpty { apply(effects) }
    }

    // MARK: Notifications

    private func refreshAuthorization() async {
        noteAuthorization(await presenter.authorization())
    }

    private func noteAuthorization(_ authorization: NotificationAuthorization) {
        let before = core.store.entries.count
        let effects = core.setNotificationsAllowed(authorization.allowsNotifications)
        if core.store.entries.count != before {
            let released = effects.filter { if case .send = $0 { true } else { false } }.count
            log(
                "notifications turned off: released \(released) waiting request\(released == 1 ? "" : "s")"
                    + " to the terminal")
            apply(effects)
        }
        if authorization.allowsNotifications {
            hasLoggedNotificationsOff = false
        } else if !hasLoggedNotificationsOff {
            hasLoggedNotificationsOff = true
            log(Self.howToEnableNotifications + " (now: \(authorization))")
        }
    }

    private func process(_ response: NotificationResponse, identifier: String, categoryIdentifier: String) {
        guard let id = UUID(uuidString: identifier), let entry = core.store.entries.first(where: { $0.id == id }) else {
            log("response to a notification that is no longer waiting")
            return
        }
        guard response != .dismissed else { return }
        // macOS may remove a notification once it is acted on: post it again if it stays.
        notifications.noteActedOn(identifier)
        let progress = core.questionProgress(for: id)
        let outcome = NativeNotification.outcome(
            of: response, categoryIdentifier: categoryIdentifier, entry: entry, request: core.request(for: id),
            progress: progress)
        let now = clock.now
        switch outcome {
        case .decide(let decision):
            apply(core.resolve(id: id, decision, now: now))
        case .openSession:
            apply(core.resolve(id: id, .openInTerminal, now: now))
        case .answer(let step, let labels):
            apply(core.answerQuestion(id: id, step: step, labels: labels, now: now))
        case .invalidReply(let step, let hint):
            core.setReplyHint(id: id, step: step, hint: hint)
            apply([])
        case .repost, .ignore:
            apply([])
        }
        log("notification \(AgentLog.short(id)): \(Self.name(of: outcome)) -> \(counts)")
    }

    private func syncNotifications() {
        let desired = core.store.entries.map { entry in
            NativeNotification.spec(
                for: entry, request: core.request(for: entry.id),
                progress: core.questionProgress(for: entry.id))
        }
        let changes = notifications.update(to: desired)
        if !changes.remove.isEmpty { presenter.remove(identifiers: changes.remove) }
        for spec in changes.post { presenter.post(spec) }
    }

    // MARK: Effects

    private func apply(_ effects: [AgentCore.Effect]) {
        for effect in effects {
            switch effect {
            case .send(let connection, let message):
                do {
                    try connections[connection]?.send(message)
                } catch {
                    log("send on connection \(connection) failed: \(error)")
                }
            case .close(let connection):
                connections.removeValue(forKey: connection)?.close()
            case .openSession(let place):
                terminal.open(place)
            }
        }
        syncNotifications()
        publish()
    }

    private func publish() {
        store = core.store
    }

    // MARK: Log helpers (no content, only kinds and ids)

    private var counts: String {
        let entries = core.store.entries
        let timedOut = entries.filter { $0.state == .timedOut }.count
        return "\(entries.count) entries (\(timedOut) timed out)"
    }

    private static func describe(_ message: WireMessage) -> String {
        switch message {
        case .request(let r): "request \(AgentLog.short(r.id)) kind=\(r.summary.kind.rawValue)"
        case .notify(let n): "notify kind=\(n.kind.rawValue)"
        case .clear: "clear"
        case .timedOut(let id): "timedOut \(AgentLog.short(id))"
        case .response: "unexpected response"
        case .statusQuery: "status query"
        case .status: "unexpected status"
        }
    }

    private static func name(of outcome: NotificationOutcome) -> String {
        switch outcome {
        case .decide(let decision): name(of: decision)
        case .openSession: "openSession"
        case .answer(let step, _): "answer step \(step + 1)"
        case .invalidReply(let step, _): "invalid reply at step \(step + 1)"
        case .repost: "repost"
        case .ignore: "ignored"
        }
    }

    private static func name(of decision: UserDecision) -> String {
        switch decision {
        case .approve: "approve"
        case .approveForSession: "approveForSession"
        case .deny: "deny"
        case .answer: "answer"
        case .approvePlan: "approvePlan"
        case .requestChanges: "requestChanges"
        case .openInTerminal: "openInTerminal"
        }
    }
}

extension WireMessage {
    /// Requests and heads-ups become notifications, so they need a fresh authorization.
    fileprivate var wantsNotification: Bool {
        switch self {
        case .request, .notify: true
        case .clear, .timedOut, .response, .statusQuery, .status: false
        }
    }
}
