import Darwin
import Foundation
import HookMeUpIPC
import Testing

@testable import HookKit
@testable import HookMeUpCore

// MARK: Fixtures

private let docsPermissionRequest = #"""
    {
      "session_id": "abc123",
      "transcript_path": "/home/.../.claude/projects/.../00893aaf-19fa-41d2-8238-13269b9b3ca0.jsonl",
      "cwd": "/home/...",
      "permission_mode": "default",
      "hook_event_name": "PermissionRequest",
      "tool_name": "Bash",
      "tool_input": {
        "command": "rm -rf node_modules",
        "description": "Remove node_modules directory"
      },
      "permission_suggestions": [
        {
          "type": "addRules",
          "rules": [{ "toolName": "Bash", "ruleContent": "rm -rf node_modules" }],
          "behavior": "allow",
          "destination": "localSettings"
        }
      ]
    }
    """#

private let askUserQuestion = #"""
    {"session_id":"q1","cwd":"/tmp","hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion",
     "tool_input":{"questions":[{"question":"Which colour?","header":"Colour","options":[{"label":"Blue"},{"label":"Orange"}],"multiSelect":false}]}}
    """#

private let notification = #"""
    {"session_id":"n1","cwd":"/tmp","hook_event_name":"Notification","message":"Claude needs your input","notification_type":"elicitation_dialog"}
    """#

private let stop = #"""
    {"session_id":"f1","cwd":"/tmp","hook_event_name":"Stop","stop_hook_active":false,"last_assistant_message":"All tests pass. Details follow."}
    """#

private let allowJSON = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#

// MARK: Helpers

final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

final class ShortTempDir {
    let url: URL
    init() throws {
        url = URL(fileURLWithPath: "/tmp/hmu-" + UUID().uuidString.prefix(8).lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
    var socket: URL { url.appendingPathComponent("agent.sock") }
}

func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        usleep(5_000)
    }
    return condition()
}

/// An in-process stand-in for the agent: records every message and answers requests
/// with `reply` (nil = never answer; the closure may also close the connection).
final class FakeAgent: @unchecked Sendable {
    let server: SocketServer
    let received = Box<[WireMessage]>([])
    let closedByClient = Box(0)

    init(path: URL, reply: @escaping @Sendable (RequestEnvelope, Connection) -> Void = { _, _ in }) throws {
        server = SocketServer(path: path)
        let received = self.received
        let closedByClient = self.closedByClient
        try server.start { connection in
            connection.onClose = { closedByClient.value += 1 }
            connection.startReading(queue: DispatchQueue(label: "fake-agent")) { message in
                received.value.append(message)
                if case .request(let request) = message { reply(request, connection) }
            }
        }
    }

    deinit { server.stop() }

    var requests: [RequestEnvelope] {
        received.value.compactMap { if case .request(let request) = $0 { return request } else { return nil } }
    }
}

func respond(_ outcome: ResponseOutcome) -> @Sendable (RequestEnvelope, Connection) -> Void {
    { request, connection in try? connection.send(.response(ResponseEnvelope(id: request.id, outcome: outcome))) }
}

/// A raw listener (not our server) that answers the first connection with `bytes`.
func serveRawOnce(_ path: String, bytes: Data) {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(path.utf8)
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
        raw.copyBytes(from: pathBytes)
        raw[pathBytes.count] = 0
    }
    _ = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
    }
    listen(fd, 1)
    Thread {
        let client = accept(fd, nil, nil)
        var chunk = [UInt8](repeating: 0, count: 65536)
        _ = read(client, &chunk, chunk.count)  // let the hook send its request first
        bytes.withUnsafeBytes { _ = write(client, $0.baseAddress, $0.count) }
        usleep(500_000)
        close(client)
        close(fd)
    }.start()
}

private func run(_ mode: HookMode, _ json: String, socket: URL, clock: @escaping () -> Date = Date.init) -> String? {
    runHook(mode: mode, stdin: Data(json.utf8), socketPath: socket, clock: clock).map {
        String(decoding: $0, as: UTF8.self)
    }
}

// MARK: Tests

@Suite(.serialized) struct RunHookTests {
    @Test func agentDownPrintsNothing() throws {
        let temp = try ShortTempDir()
        let start = Date()
        for mode in [HookMode.permission(timeout: 600), .notify, .finished, .clear] {
            #expect(run(mode, docsPermissionRequest, socket: temp.socket) == nil)
        }
        #expect(Date().timeIntervalSince(start) < 1)
    }

    @Test func agentKilledMidRequestPrintsNothing() throws {
        // The agent reads the request, then goes away without answering.
        let temp = try ShortTempDir()
        let agent = try FakeAgent(path: temp.socket) { _, connection in connection.close() }
        let start = Date()
        #expect(run(.permission(timeout: 600), docsPermissionRequest, socket: temp.socket) == nil)
        #expect(Date().timeIntervalSince(start) < 2)
        #expect(agent.requests.count == 1)
    }

    @Test func garbageStdinPrintsNothing() throws {
        let temp = try ShortTempDir()
        let agent = try FakeAgent(path: temp.socket, reply: respond(.decided(.approve)))
        for garbage in ["", "not json", "{}", "[1,2]", #"{"session_id":"s","cwd":"/p"}"#] {
            #expect(run(.permission(timeout: 600), garbage, socket: temp.socket) == nil)
        }
        usleep(100_000)
        #expect(agent.received.value.isEmpty)  // nothing was even asked
    }

    @Test func otherEventInPermissionModePrintsNothing() throws {
        let temp = try ShortTempDir()
        let agent = try FakeAgent(path: temp.socket, reply: respond(.decided(.approve)))
        #expect(run(.permission(timeout: 600), notification, socket: temp.socket) == nil)
        #expect(run(.permission(timeout: 600), stop, socket: temp.socket) == nil)
        usleep(100_000)
        #expect(agent.received.value.isEmpty)
    }

    @Test func garbageResponsePrintsNothing() throws {
        let temp = try ShortTempDir()
        serveRawOnce(temp.socket.path, bytes: Data([0, 0, 0, 5]) + Data("hello".utf8))
        #expect(run(.permission(timeout: 600), docsPermissionRequest, socket: temp.socket) == nil)
    }

    @Test func mismatchedIDPrintsNothing() throws {
        let temp = try ShortTempDir()
        let agent = try FakeAgent(path: temp.socket) { _, connection in
            try? connection.send(.response(ResponseEnvelope(id: UUID(), outcome: .decided(.approve))))
        }
        #expect(run(.permission(timeout: 600), docsPermissionRequest, socket: temp.socket) == nil)
        #expect(agent.requests.count == 1)  // the agent was really asked (and kept alive)
    }

    @Test func nonResponseMessagePrintsNothing() throws {
        let temp = try ShortTempDir()
        let agent = try FakeAgent(path: temp.socket) { request, connection in
            try? connection.send(.timedOut(id: request.id))
        }
        #expect(run(.permission(timeout: 600), docsPermissionRequest, socket: temp.socket) == nil)
        #expect(agent.requests.count == 1)
    }

    @Test func approveRoundTripPrintsAllowJSON() throws {
        let temp = try ShortTempDir()
        let agent = try FakeAgent(path: temp.socket, reply: respond(.decided(.approve)))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(run(.permission(timeout: 600), docsPermissionRequest, socket: temp.socket, clock: { now }) == allowJSON)

        let request = try #require(agent.requests.first)
        #expect(request.sessionID == "abc123")
        #expect(request.summary.title == "Delete files")
        #expect(request.summary.description == "Remove node_modules directory")
        #expect(
            request.input
                == .object([
                    "command": .string("rm -rf node_modules"),
                    "description": .string("Remove node_modules directory"),
                ]))
        #expect(request.terminal.ancestorPIDs.first == getpid() || request.terminal.ancestorPIDs.first == getppid())
        #expect(!request.terminal.ancestorPIDs.isEmpty)
        // What "Allow for session" would add, already filtered to session-only (display only).
        #expect(
            request.sessionPermissions == [
                PermissionUpdate(
                    type: "addRules", rules: [PermissionRule(toolName: "Bash", ruleContent: "rm -rf node_modules")],
                    behavior: "allow", destination: "session")
            ])
    }

    @Test func denyRoundTrip() throws {
        let temp = try ShortTempDir()
        let agent = try FakeAgent(path: temp.socket, reply: respond(.decided(.deny)))
        #expect(
            run(.permission(timeout: 600), docsPermissionRequest, socket: temp.socket)
                == #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"User denied this via a notification. Don't retry the same action; ask or try another approach."}}}"#
        )
        #expect(agent.requests.count == 1)
    }

    @Test func approveForSessionNeverPersists() throws {
        // The docs example suggests a localSettings rule: it must come out as session-only.
        let temp = try ShortTempDir()
        let agent = try FakeAgent(path: temp.socket, reply: respond(.decided(.approveForSession)))
        defer { #expect(agent.requests.count == 1) }
        #expect(
            run(.permission(timeout: 600), docsPermissionRequest, socket: temp.socket)
                == #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow","updatedPermissions":[{"behavior":"allow","destination":"session","rules":[{"ruleContent":"rm -rf node_modules","toolName":"Bash"}],"type":"addRules"}]}}}"#
        )
    }

    @Test func answerUsesHooksOwnToolInput() throws {
        let temp = try ShortTempDir()
        let agent = try FakeAgent(path: temp.socket, reply: respond(.decided(.answer(["Which colour?": "Orange"]))))
        defer { #expect(agent.requests.count == 1) }
        let output = try #require(run(.permission(timeout: 600), askUserQuestion, socket: temp.socket))
        let json = try JSONDecoder().decode(JSONValue.self, from: Data(output.utf8))
        #expect(
            json["hookSpecificOutput"]?["decision"]?["updatedInput"]
                == .object([
                    "questions": .array([
                        .object([
                            "question": .string("Which colour?"), "header": .string("Colour"),
                            "options": .array([
                                .object(["label": .string("Blue")]), .object(["label": .string("Orange")]),
                            ]),
                            "multiSelect": .bool(false),
                        ])
                    ]),
                    "answers": .object(["Which colour?": .string("Orange")]),
                ]))
    }

    @Test func openInTerminalPrintsNothing() throws {
        let temp = try ShortTempDir()
        let agent = try FakeAgent(path: temp.socket, reply: respond(.decided(.openInTerminal)))
        #expect(run(.permission(timeout: 600), docsPermissionRequest, socket: temp.socket) == nil)
        #expect(agent.requests.count == 1)
        agent.server.stop()
    }

    @Test func pausedPrintsNothing() throws {
        let temp = try ShortTempDir()
        let agent = try FakeAgent(path: temp.socket, reply: respond(.paused))
        let start = Date()
        #expect(run(.permission(timeout: 600), docsPermissionRequest, socket: temp.socket) == nil)
        #expect(Date().timeIntervalSince(start) < 1)
        #expect(agent.requests.count == 1)
    }

    @Test func selfTimeoutSendsTimedOutAndPrintsNothing() throws {
        let temp = try ShortTempDir()
        let agent = try FakeAgent(path: temp.socket)  // never answers
        let start = Date()
        // Handler timeout 12 s -> the hook gives up 10 s earlier, after 2 s.
        #expect(run(.permission(timeout: 12), docsPermissionRequest, socket: temp.socket) == nil)
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed >= 1.9 && elapsed < 3.5)
        #expect(waitUntil { agent.received.value.count == 2 })
        let request = try #require(agent.requests.first)
        #expect(agent.received.value.last == .timedOut(id: request.id))
    }

    @Test func selfTimeoutLeavesTenSecondsBeforeTheHandlerTimeout() {
        #expect(HookTiming.selfExitDelay(handlerTimeout: 600) == 590)
        #expect(HookTiming.selfExitDelay(handlerTimeout: 12) == 2)
        #expect(HookTiming.selfExitDelay(handlerTimeout: 5) == 1)
    }

    @Test func clearReturnsUnder250msWhenAgentDown() throws {
        let temp = try ShortTempDir()
        let clearJSON = #"{"session_id":"s1","cwd":"/tmp","hook_event_name":"UserPromptSubmit","prompt":"hi"}"#
        let start = Date()
        #expect(run(.clear, clearJSON, socket: temp.socket) == nil)
        #expect(Date().timeIntervalSince(start) < 0.25)

        // A stale socket file (agent crashed) is just as fast.
        let stale = socket(AF_UNIX, SOCK_STREAM, 0)
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(temp.socket.path.utf8)
        withUnsafeMutableBytes(of: &address.sun_path) {
            $0.copyBytes(from: pathBytes)
            $0[pathBytes.count] = 0
        }
        _ = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(stale, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        close(stale)
        let again = Date()
        #expect(run(.clear, clearJSON, socket: temp.socket) == nil)
        #expect(Date().timeIntervalSince(again) < 0.25)
    }

    @Test func clearNotifyAndFinishedReachTheAgent() throws {
        let temp = try ShortTempDir()
        let agent = try FakeAgent(path: temp.socket)
        #expect(
            run(
                .clear, #"{"session_id":"s1","cwd":"/tmp","hook_event_name":"SessionEnd","reason":"other"}"#,
                socket: temp.socket) == nil)
        #expect(run(.notify, notification, socket: temp.socket) == nil)
        #expect(run(.finished, stop, socket: temp.socket) == nil)
        #expect(waitUntil { agent.received.value.count == 3 })
        let messages = agent.received.value
        #expect(messages.first == .clear(sessionID: "s1"))
        guard messages.count == 3, case .notify(let waiting) = messages[1], case .notify(let finished) = messages[2]
        else {
            Issue.record("unexpected messages: \(messages)")
            return
        }
        #expect(waiting.sessionID == "n1")
        #expect(waiting.kind == .waiting)
        #expect(waiting.message == "Claude needs your input")
        #expect(finished.sessionID == "f1")
        #expect(finished.kind == .finished)
        #expect(finished.message == "All tests pass.")
    }

    @Test func sessionProcessDeathEndsTheWaitAndRemovesTheEntry() throws {
        // if Claude Code dies, the hook must not linger for 590 s.
        let temp = try ShortTempDir()
        let agent = try FakeAgent(path: temp.socket)  // never answers
        let session = Process()
        session.executableURL = URL(fileURLWithPath: "/bin/sleep")
        session.arguments = ["30"]
        try session.run()
        let result = Box<String?>("not finished")
        let done = DispatchSemaphore(value: 0)
        let socket = temp.socket
        let pid = session.processIdentifier
        Thread {
            result.value = runHook(
                mode: .permission(timeout: 600), stdin: Data(docsPermissionRequest.utf8),
                socketPath: socket, watchProcess: pid
            ).map { String(decoding: $0, as: UTF8.self) }
            done.signal()
        }.start()
        #expect(waitUntil { agent.requests.count == 1 })
        let start = Date()
        session.terminate()
        #expect(done.wait(timeout: .now() + 3) == .success)
        #expect(Date().timeIntervalSince(start) < 2)
        #expect(result.value == nil)  // printed nothing
        #expect(waitUntil { agent.closedByClient.value == 1 })  // the agent saw the hook go: entry removed
    }

    @Test func alreadyDeadSessionProcessReturnsAtOnce() throws {
        let temp = try ShortTempDir()
        let agent = try FakeAgent(path: temp.socket)
        let gone = Process()
        gone.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try gone.run()
        gone.waitUntilExit()
        let start = Date()
        #expect(
            runHook(
                mode: .permission(timeout: 600), stdin: Data(docsPermissionRequest.utf8),
                socketPath: temp.socket, watchProcess: gone.processIdentifier) == nil)
        #expect(Date().timeIntervalSince(start) < 2)
        _ = agent
    }

    @Test func headlessSessionsSendNoFinishedOrWaitingEntries() throws {
        // `claude -p` / SDK runs have nobody to come back to.
        let temp = try ShortTempDir()
        let agent = try FakeAgent(path: temp.socket)
        for entrypoint in ["sdk-cli", "sdk-ts", "sdk-py"] {
            let env = ["CLAUDE_CODE_ENTRYPOINT": entrypoint]
            #expect(runHook(mode: .finished, stdin: Data(stop.utf8), socketPath: temp.socket, environment: env) == nil)
            #expect(
                runHook(mode: .notify, stdin: Data(notification.utf8), socketPath: temp.socket, environment: env) == nil
            )
        }
        usleep(150_000)
        #expect(agent.received.value.isEmpty)
        // An interactive session (entrypoint "cli") still sends them.
        let cli = ["CLAUDE_CODE_ENTRYPOINT": "cli"]
        _ = runHook(mode: .finished, stdin: Data(stop.utf8), socketPath: temp.socket, environment: cli)
        _ = runHook(mode: .notify, stdin: Data(notification.utf8), socketPath: temp.socket, environment: cli)
        #expect(waitUntil { agent.received.value.count == 2 })
    }

    @Test func notifyAndFinishedIgnoreOtherEvents() throws {
        let temp = try ShortTempDir()
        let agent = try FakeAgent(path: temp.socket)
        #expect(run(.notify, stop, socket: temp.socket) == nil)
        #expect(run(.finished, notification, socket: temp.socket) == nil)
        #expect(run(.finished, docsPermissionRequest, socket: temp.socket) == nil)
        usleep(150_000)
        #expect(agent.received.value.isEmpty)
    }
}

@Suite struct ProcessTreeTests {
    @Test func processTreeIncludesParent() {
        let ancestors = ProcessTree.ancestors(of: getpid())
        #expect(ancestors.first?.pid == getppid())
        #expect(ancestors.first.map { !$0.path.isEmpty } == true)
        #expect(!ancestors.contains { $0.pid == getpid() })
        #expect(!ancestors.contains { $0.pid <= 1 })
    }

    @Test func unknownPIDHasNoAncestors() {
        #expect(ProcessTree.ancestors(of: 999_999).isEmpty)
    }
}

@Suite struct HookInvocationTests {
    @Test func parsesModesAndOptions() {
        #expect(
            HookInvocation.parse(["permission", "--timeout", "600"])
                == HookInvocation(mode: .permission(timeout: 600), socketPath: nil))
        #expect(
            HookInvocation.parse(["permission"]) == HookInvocation(mode: .permission(timeout: 600), socketPath: nil))
        #expect(HookInvocation.parse(["notify"]) == HookInvocation(mode: .notify, socketPath: nil))
        #expect(HookInvocation.parse(["finished"]) == HookInvocation(mode: .finished, socketPath: nil))
        #expect(
            HookInvocation.parse(["clear", "--socket", "/tmp/x.sock"])
                == HookInvocation(mode: .clear, socketPath: URL(fileURLWithPath: "/tmp/x.sock")))
    }

    @Test func timeoutIsClampedTo1Through600() {
        #expect(HookInvocation.parse(["permission", "--timeout", "900"])?.mode == .permission(timeout: 600))
        #expect(HookInvocation.parse(["permission", "--timeout", "0"])?.mode == .permission(timeout: 1))
        #expect(HookInvocation.parse(["permission", "--timeout", "-5"])?.mode == .permission(timeout: 1))
        #expect(HookInvocation.parse(["permission", "--timeout", "120"])?.mode == .permission(timeout: 120))
    }

    @Test func rejectsBadArguments() {
        for args in [
            [], ["approve"], ["permission", "--timeout"], ["permission", "--timeout", "abc"],
            ["permission", "--timeout", "inf"], ["permission", "--timeout", "nan"], ["clear", "--socket"],
            ["clear", "--bogus"],
        ] {
            #expect(HookInvocation.parse(args) == nil, "\(args)")
        }
    }

    @Test func defaultSocketIsInApplicationSupport() {
        #expect(
            HookMeUpPaths.socketURL(home: URL(fileURLWithPath: "/home/me")).path
                == "/home/me/Library/Application Support/hook-me-up/agent.sock")
    }
}
