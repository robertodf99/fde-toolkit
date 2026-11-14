import Foundation
import Testing

@testable import HookMeUpCore

private let project = ProjectInfo(name: "proj", gitRoot: "/home/me/proj", branch: "main", worktree: "wt")
private let terminal = TerminalHint(ancestorPIDs: [123, 45, 1], tty: "ttys003")
private let summary = RequestSummary(
    kind: .permission, title: "Run a command", description: "List files",
    tags: [.network], origin: .subagent)

private func header(_ length: UInt32) -> Data {
    Data([UInt8(length >> 24), UInt8((length >> 16) & 0xFF), UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF)])
}

@Suite struct WireFieldTests {
    /// The request carries only what the agent uses: no unused detail, timeout or date.
    @Test func requestCarriesOnlyWhatTheAgentUses() throws {
        let request = RequestEnvelope(
            id: UUID(), sessionID: "s", project: project, summary: summary, input: .object([:]), terminal: terminal)
        let object = try #require(
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        #expect(
            Set(object.keys) == ["id", "sessionID", "project", "summary", "input", "terminal", "sessionPermissions"])
        let summaryObject = try #require(object["summary"] as? [String: Any])
        #expect(Set(summaryObject.keys) == ["kind", "title", "description", "tags", "origin"])
    }
}

@Suite struct FramingTests {
    static let allMessages: [WireMessage] = {
        let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let request = RequestEnvelope(
            id: id, sessionID: "sess-1", project: project, summary: summary,
            input: .object(["command": .string("ls"), "n": .number(3), "ok": .bool(true), "x": .null]),
            terminal: terminal)
        let decisions: [UserDecision] = [
            .approve, .approveForSession, .deny, .answer(["Q?": "A, B"]), .approvePlan,
            .requestChanges("Add tests\nplease"), .openInTerminal,
        ]
        return [
            .request(request),
            .notify(
                NotifyEnvelope(
                    sessionID: "sess-2", project: project, kind: .finished, message: "Done.", terminal: terminal)),
            .notify(
                NotifyEnvelope(
                    sessionID: "sess-3", project: ProjectInfo(name: "x", gitRoot: nil, branch: nil, worktree: nil),
                    kind: .waiting, message: "", terminal: TerminalHint(ancestorPIDs: [], tty: nil))),
            .clear(sessionID: "sess-1"),
            .timedOut(id: id),
            .response(ResponseEnvelope(id: id, outcome: .paused)),
        ] + decisions.map { .response(ResponseEnvelope(id: id, outcome: .decided($0))) }
    }()

    @Test func roundTripAllCases() throws {
        for message in Self.allMessages {
            var buffer = try Framing.encode(message)
            #expect(try Framing.decode(&buffer) == message)
            #expect(buffer.isEmpty)
        }
    }

    @Test func frameHasBigEndianLengthPrefix() throws {
        let frame = try Framing.encode(.clear(sessionID: "s"))
        let length = frame.prefix(4).reduce(0) { $0 << 8 | Int($1) }
        #expect(length == frame.count - 4)
        #expect((try? JSONSerialization.jsonObject(with: frame.dropFirst(4))) != nil)
    }

    @Test func partialFrameReturnsNil() throws {
        let frame = try Framing.encode(Self.allMessages[0])
        var buffer = Data()
        for (index, byte) in frame.enumerated() {
            buffer.append(byte)
            let decoded = try Framing.decode(&buffer)
            if index < frame.count - 1 {
                #expect(decoded == nil)
                #expect(buffer.count == index + 1)  // nothing consumed until complete
            } else {
                #expect(decoded == Self.allMessages[0])
                #expect(buffer.isEmpty)
            }
        }
        var empty = Data()
        #expect(try Framing.decode(&empty) == nil)
    }

    @Test func oversizeFrameThrows() throws {
        var buffer = header(UInt32(Framing.maxFrame + 1)) + Data(repeating: 0x20, count: 16)
        #expect(throws: FramingError.self) { try Framing.decode(&buffer) }

        let huge = WireMessage.clear(sessionID: String(repeating: "x", count: Framing.maxFrame))
        #expect(throws: FramingError.self) { try Framing.encode(huge) }

        // Exactly maxFrame is allowed: an incomplete frame of that size is just "not yet".
        var atLimit = header(UInt32(Framing.maxFrame)) + Data(repeating: 0x20, count: 10)
        #expect(try Framing.decode(&atLimit) == nil)
    }

    @Test func zeroLengthThrows() {
        var buffer = header(0) + Data("{}".utf8)
        #expect(throws: FramingError.self) { try Framing.decode(&buffer) }
    }

    @Test func garbagePayloadThrows() {
        let payload = Data("not json".utf8)
        var buffer = header(UInt32(payload.count)) + payload
        #expect(throws: (any Error).self) { try Framing.decode(&buffer) }
        let unknown = Data(#"{"launchMissiles":{}}"#.utf8)
        var other = header(UInt32(unknown.count)) + unknown
        #expect(throws: (any Error).self) { try Framing.decode(&other) }
    }

    @Test func twoFramesInOneBuffer() throws {
        let first = WireMessage.clear(sessionID: "a")
        let second = WireMessage.timedOut(id: UUID())
        var buffer = try Framing.encode(first) + Framing.encode(second) + Data([0, 0])
        #expect(try Framing.decode(&buffer) == first)
        #expect(try Framing.decode(&buffer) == second)
        #expect(try Framing.decode(&buffer) == nil)
        #expect(buffer == Data([0, 0]))
    }

    @Test func slicedBufferWithNonZeroStartIndex() throws {
        let whole = Data([9, 9, 9]) + (try Framing.encode(.clear(sessionID: "slice")))
        var buffer = whole.dropFirst(3)  // startIndex == 3
        #expect(buffer.startIndex == 3)
        #expect(try Framing.decode(&buffer) == .clear(sessionID: "slice"))
        #expect(buffer.isEmpty)
    }
}
