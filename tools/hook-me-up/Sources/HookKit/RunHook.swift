import Darwin
import Foundation
import HookMeUpCore
import HookMeUpIPC

/// Runs one hook invocation. Returns the bytes to print on stdout, or nil to print
/// nothing (Claude Code then shows its own terminal dialog). Every failure, mismatch,
/// timeout or pause returns nil: this never turns an error into a deny.
public func runHook(
    mode: HookMode, stdin: Data, socketPath: URL, clock: @escaping () -> Date = Date.init,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    watchProcess: pid_t? = ProcessTree.sessionProcess(of: getpid())
) -> Data? {
    guard let input = try? HookInput.parse(stdin) else { return nil }
    let headless = isHeadless(environment)
    let folder = sessionFolder(input, environment: environment)
    switch mode {
    case .permission(let timeout):
        return requestDecision(
            input, handlerTimeout: timeout, socketPath: socketPath, headless: headless, sessionFolder: folder,
            watchProcess: watchProcess, clock: clock)
    case .notify:
        // Headless (`claude -p`, SDK) sessions have nobody to come back to.
        guard input.hookEventName == "Notification", !headless else { return nil }
        notify(input, kind: .waiting, sessionFolder: folder, socketPath: socketPath)
    case .finished:
        guard input.hookEventName == "Stop", !headless else { return nil }
        notify(input, kind: .finished, sessionFolder: folder, socketPath: socketPath)
    case .clear:
        fireAndForget(.clear(sessionID: input.sessionID), socketPath: socketPath)
    }
    return nil
}

private func requestDecision(
    _ input: HookInput, handlerTimeout requestedTimeout: TimeInterval, socketPath: URL,
    headless: Bool, sessionFolder: String, watchProcess: pid_t?, clock: () -> Date
) -> Data? {
    guard input.hookEventName == "PermissionRequest", input.toolName != nil else { return nil }
    let handlerTimeout = min(max(requestedTimeout, 1), HookTiming.defaultHandlerTimeout)
    let start = clock()
    let project = ProjectInfo.resolve(cwd: URL(fileURLWithPath: input.cwd), fileSystem: LocalFileSystem())
    var summary = Summarizer.summarize(input, project: project, home: HookMeUpPaths.homeDirectory.path)
    if summary.origin == nil, headless { summary.origin = .headless }

    let id = UUID()
    var envelope = RequestEnvelope(
        id: id, sessionID: input.sessionID, project: project, summary: summary,
        input: input.toolInput ?? .null, terminal: terminalHint(),
        sessionPermissions: SessionPermissionFilter.sessionOnly(input.permissionSuggestions),
        sessionFolder: sessionFolder)

    guard let connection = try? SocketClient.connect(path: socketPath, timeout: HookTiming.permissionConnectTimeout)
    else { return nil }
    defer { connection.close() }
    // If the session process dies, stop waiting at once: the agent sees the connection
    // end and removes the entry; this hook prints nothing.
    let watch = watchProcess.map { ProcessExitWatch(pid: $0) { connection.interrupt() } }
    defer { watch?.cancel() }

    do {
        try connection.send(.request(envelope))
    } catch FramingError.oversize where summary.kind == .permission {
        // Too big for one frame (e.g. a huge Write): send it without the raw input, which
        // is display-only here; the summary still describes the request.
        envelope.input = .null
        guard (try? connection.send(.request(envelope))) != nil else { return nil }
    } catch {
        return nil
    }

    let remaining = HookTiming.selfExitDelay(handlerTimeout: handlerTimeout) - clock().timeIntervalSince(start)
    let reply: WireMessage?
    do {
        reply = try connection.receive(timeout: max(0, remaining))
    } catch SocketError.timedOut {
        try? connection.send(.timedOut(id: id))
        return nil
    } catch {
        return nil
    }

    // Only a decision for our own request id counts; anything else prints nothing.
    guard case .response(let response)? = reply, response.id == id,
        case .decided(let decision) = response.outcome
    else { return nil }
    return DecisionEncoder.output(for: decision, input: input)
}

private func notify(_ input: HookInput, kind: EntryKind, sessionFolder: String, socketPath: URL) {
    let project = ProjectInfo.resolve(cwd: URL(fileURLWithPath: input.cwd), fileSystem: LocalFileSystem())
    let summary = Summarizer.summarize(input, project: project, home: HookMeUpPaths.homeDirectory.path)
    fireAndForget(
        .notify(
            NotifyEnvelope(
                sessionID: input.sessionID, project: project, kind: kind,
                message: summary.description, terminal: terminalHint(), sessionFolder: sessionFolder)),
        socketPath: socketPath)
}

private func fireAndForget(_ message: WireMessage, socketPath: URL) {
    guard let connection = try? SocketClient.connect(path: socketPath, timeout: HookTiming.fireAndForgetConnectTimeout)
    else { return }
    try? connection.send(message)
    connection.close()
}

private func terminalHint() -> TerminalHint {
    let ancestors = ProcessTree.sessionAncestors(of: getpid())
    let tty = ancestors.lazy.compactMap { ProcessTree.controllingTTY(of: $0.pid) }.first
    return TerminalHint(ancestorPIDs: ancestors.map(\.pid), tty: tty)
}

/// The folder Claude Code was started in: `CLAUDE_PROJECT_DIR`, which stays put when
/// Claude enters a worktree, else the working folder from the hook's input. The agent
/// only uses it to open that folder in the editor that runs the session.
func sessionFolder(_ input: HookInput, environment: [String: String]) -> String {
    if let folder = environment["CLAUDE_PROJECT_DIR"], !folder.isEmpty { return folder }
    return input.cwd
}

/// Assumption (not verified): `claude -p` and SDK runs report an "sdk-*" entrypoint;
/// interactive sessions report "cli".
func isHeadless(_ environment: [String: String]) -> Bool {
    environment["CLAUDE_CODE_ENTRYPOINT"]?.hasPrefix("sdk") == true
}
