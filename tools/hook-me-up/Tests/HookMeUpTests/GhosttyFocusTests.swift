import Foundation
import HookMeUpCore
import Testing

@testable import HookMeUp

private let idA = "4F9C2E1A-8B7D-4C3E-9A0B-1D2E3F405162"
private let idB = "0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9"
private let idC = "C0FFEE00-0000-4000-8000-000000000001"
private let folder = "/Users/dev/projects/acme-api"
private let token = "hmu-0123456789abcdef"

private func lines(_ lines: [String]) -> String { lines.map { $0 + "\n" }.joined() }

/// Ghostty and the session's tty, made up: records every script run and every write, in
/// order, and answers each script with what the test set.
private final class FakeGhostty {
    var list: String? = lines(["\(idA)\t\(folder)", "\(idB)\t\(folder)/", "\(idC)\t/Users/dev"])
    var titles: String? = lines(["\(idA)\t✳ Claude Code", "\(idB)\tzsh", "\(idC)\tvim"])
    var found: String? = lines([idB])
    var focus: String? = "found"
    var hasTTY = true
    /// What each write reports, in turn (then true).
    var writeResults: [Bool] = []
    private(set) var events: [String] = []
    private(set) var written: [[UInt8]] = []

    var io: TerminalActivator.GhosttyIO {
        TerminalActivator.GhosttyIO(
            run: { self.run($0) }, writeToSession: hasTTY ? { self.write($0) } : nil, makeToken: { token },
            resolve: { $0 })
    }

    private func run(_ command: GhosttyTerminals.Command) -> String? {
        switch command {
        case GhosttyTerminals.list:
            events.append("list")
            return list
        case GhosttyTerminals.titles:
            events.append("titles")
            return titles
        case GhosttyTerminals.activate:
            events.append("activate")
            return "found"
        case GhosttyTerminals.findMarker(token: token):
            events.append("find")
            return found
        default:
            for id in [idA, idB, idC] where command == GhosttyTerminals.focus(id: id) {
                events.append("focus \(id)")
                return focus
            }
            events.append("unexpected script")
            return nil
        }
    }

    private func write(_ bytes: [UInt8]) -> Bool {
        events.append("write")
        written.append(bytes)
        return writeResults.isEmpty ? true : writeResults.removeFirst()
    }
}

/// `ghosttyFocus` with several terminals in the session's folder: the title marker.
@Suite struct GhosttyFocusTests {
    /// Titles listed, marker written, Ghostty asked which terminal shows it, that one's
    /// title written back, and only then focused.
    @Test func theTerminalThatShowsTheMarkerIsFocusedAfterItsTitleIsBack() {
        let ghostty = FakeGhostty()
        #expect(TerminalActivator.ghosttyFocus(folder: folder, using: ghostty.io) == .focusedByMarker)
        #expect(ghostty.events == ["list", "titles", "write", "find", "write", "focus \(idB)"])
        #expect(ghostty.written == [GhosttyTerminals.titleSequence(token), GhosttyTerminals.titleSequence("zsh")])
    }

    /// The title written back has no control characters and fits in 255 bytes.
    @Test func theEarlierTitleIsWrittenBackSanitised() throws {
        let ghostty = FakeGhostty()
        let long = String(repeating: "é", count: 300)
        ghostty.titles = lines(["\(idA)\tclaude", "\(idB)\tevil\u{1B}]2;x\u{07}\(long)"])
        #expect(TerminalActivator.ghosttyFocus(folder: folder, using: ghostty.io) == .focusedByMarker)
        try #require(ghostty.written.count == 2)
        let restored = ghostty.written[1]
        #expect(restored.prefix(4) == [0x1B, 0x5D, 0x32, 0x3B] && restored.last == 0x07)
        let title = restored.dropFirst(4).dropLast()
        #expect(!title.contains { $0 < 0x20 || $0 == 0x7F })
        #expect(title.count <= 255)
        #expect(String(decoding: title, as: UTF8.self).hasPrefix("evil]2;xé"))
    }

    /// A terminal whose title wasn't listed (it held a line break) gets an empty title back,
    /// not the marker.
    @Test func anUnlistedTitleIsWrittenBackEmpty() {
        let ghostty = FakeGhostty()
        ghostty.titles = lines(["\(idA)\tclaude"])
        #expect(TerminalActivator.ghosttyFocus(folder: folder, using: ghostty.io) == .focusedByMarker)
        #expect(ghostty.written.last == GhosttyTerminals.titleSequence(""))
    }

    /// Ghostty ignores the title (`title = …` in its config), the session changed it first, or
    /// Ghostty shows it too late: which title it replaced can't be told, so an empty title is
    /// written (the marker must never stay); Ghostty only comes forward.
    @Test func aMarkerNotSeenBringsGhosttyForward() {
        let ghostty = FakeGhostty()
        ghostty.found = ""
        #expect(TerminalActivator.ghosttyFocus(folder: folder, using: ghostty.io) == .markerNotSeen(2))
        #expect(ghostty.events == ["list", "titles", "write", "find", "write", "activate"])
        #expect(ghostty.written == [GhosttyTerminals.titleSequence(token), GhosttyTerminals.titleSequence("")])
    }

    /// The find script failed or timed out: the marker may be showing all the same.
    @Test func aFailedFindScriptCountsAsNotSeen() {
        let ghostty = FakeGhostty()
        ghostty.found = nil
        #expect(TerminalActivator.ghosttyFocus(folder: folder, using: ghostty.io) == .markerNotSeen(2))
        #expect(ghostty.events == ["list", "titles", "write", "find", "write", "activate"])
        #expect(ghostty.written.last == GhosttyTerminals.titleSequence(""))
    }

    /// Two terminals show it: which one is the session's can't be told, nor which title to
    /// write back, so an empty one is.
    @Test func aMarkerInTwoTerminalsFocusesNothing() {
        let ghostty = FakeGhostty()
        ghostty.found = lines([idA, idB])
        #expect(TerminalActivator.ghosttyFocus(folder: folder, using: ghostty.io) == .markerNotSeen(2))
        #expect(ghostty.events == ["list", "titles", "write", "find", "write", "activate"])
        #expect(ghostty.written.last == GhosttyTerminals.titleSequence(""))
    }

    /// A marker left by an earlier click (one Ghostty showed too late, say) is never taken
    /// for the earlier title: an empty title is written back instead, so it can't live on.
    @Test(arguments: ["hmu-fedcba9876543210", "✳ hmu-fedcba9876543210 build"])
    func aLeftoverMarkerIsNeverWrittenBack(_ leftover: String) {
        let ghostty = FakeGhostty()
        ghostty.titles = lines(["\(idA)\tclaude", "\(idB)\t\(leftover)"])
        #expect(TerminalActivator.ghosttyFocus(folder: folder, using: ghostty.io) == .focusedByMarker)
        #expect(ghostty.written == [GhosttyTerminals.titleSequence(token), GhosttyTerminals.titleSequence("")])
    }

    /// The terminal that shows it is not in the session's folder: its title is written back,
    /// but it is not focused.
    @Test func aMarkerOutsideTheFolderIsNotFocused() {
        let ghostty = FakeGhostty()
        ghostty.found = lines([idC])
        #expect(TerminalActivator.ghosttyFocus(folder: folder, using: ghostty.io) == .markerNotSeen(2))
        #expect(ghostty.events == ["list", "titles", "write", "find", "write", "activate"])
        #expect(ghostty.written.last == GhosttyTerminals.titleSequence("vim"))
    }

    /// The tty isn't the session's any more (or can't be opened): nothing was written, so
    /// nothing is asked or written back.
    @Test func aFailedMarkerWriteBringsGhosttyForward() {
        let ghostty = FakeGhostty()
        ghostty.writeResults = [false]
        #expect(TerminalActivator.ghosttyFocus(folder: folder, using: ghostty.io) == .noUsableTTY(2))
        #expect(ghostty.events == ["list", "titles", "write", "activate"])
    }

    /// No usable tty at all: no titles, no write.
    @Test func withoutATTYNothingIsWritten() {
        let ghostty = FakeGhostty()
        ghostty.hasTTY = false
        #expect(TerminalActivator.ghosttyFocus(folder: folder, using: ghostty.io) == .noUsableTTY(2))
        #expect(ghostty.events == ["list", "activate"])
        #expect(ghostty.written.isEmpty)
    }

    @Test func aFailedTitlesScriptWritesNothing() {
        let ghostty = FakeGhostty()
        ghostty.titles = nil
        #expect(TerminalActivator.ghosttyFocus(folder: folder, using: ghostty.io) == .scriptFailed)
        #expect(ghostty.events == ["list", "titles"])
        #expect(ghostty.written.isEmpty)
    }

    /// The title is back before the focus is tried, even when the focus then fails.
    @Test func aFailedFocusAfterTheMarkerStillWroteTheTitleBack() {
        let ghostty = FakeGhostty()
        ghostty.focus = nil
        #expect(TerminalActivator.ghosttyFocus(folder: folder, using: ghostty.io) == .scriptFailed)
        #expect(ghostty.events == ["list", "titles", "write", "find", "write", "focus \(idB)"])
    }

    // MARK: Unchanged cases

    @Test func oneTerminalInTheFolderIsFocusedWithoutAMarker() {
        let ghostty = FakeGhostty()
        ghostty.list = lines(["\(idA)\t\(folder)", "\(idC)\t/Users/dev"])
        #expect(TerminalActivator.ghosttyFocus(folder: folder, using: ghostty.io) == .focused)
        #expect(ghostty.events == ["list", "focus \(idA)"])
        #expect(ghostty.written.isEmpty)
    }

    @Test func noTerminalInTheFolderBringsGhosttyForward() {
        let ghostty = FakeGhostty()
        ghostty.list = lines(["\(idC)\t/Users/dev"])
        #expect(TerminalActivator.ghosttyFocus(folder: folder, using: ghostty.io) == .noUniqueMatch(0))
        #expect(ghostty.events == ["list", "activate"])
        #expect(ghostty.written.isEmpty)
    }

    @Test func aFailedListDoesNothingElse() {
        let ghostty = FakeGhostty()
        ghostty.list = nil
        #expect(TerminalActivator.ghosttyFocus(folder: folder, using: ghostty.io) == .scriptFailed)
        #expect(ghostty.events == ["list"])
    }

    @Test func aFailedFocusOfTheOneTerminalIsAScriptFailure() {
        let ghostty = FakeGhostty()
        ghostty.list = lines(["\(idA)\t\(folder)"])
        ghostty.focus = "missing"
        #expect(TerminalActivator.ghosttyFocus(folder: folder, using: ghostty.io) == .scriptFailed)
    }
}

/// Records the steps of several runs, from any thread.
private final class StepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [String] = []

    func add(_ step: String) {
        lock.lock()
        steps.append(step)
        lock.unlock()
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return steps
    }
}

/// Two clicks on Ghostty notifications at almost the same time: the second one's scripts and
/// writes start only after the first one's are done, so their markers and titles never mix.
@Suite struct GhosttyClickOrderTests {
    @Test func ghosttyClicksRunOneAtATime() {
        let log = StepLog()
        let done = DispatchGroup()
        for click in 1...2 {
            done.enter()
            TerminalActivator.ghosttyClicks.async {
                let io = TerminalActivator.GhosttyIO(
                    run: { command in
                        log.add("\(click) begin")
                        Thread.sleep(forTimeInterval: 0.02)
                        log.add("\(click) end")
                        // Two terminals in the folder; no titles; the marker is never seen.
                        return command == GhosttyTerminals.list
                            ? lines(["\(idA)\t\(folder)", "\(idB)\t\(folder)"]) : ""
                    },
                    writeToSession: { _ in
                        log.add("\(click) write")
                        return true
                    }, makeToken: { token }, resolve: { $0 })
                _ = TerminalActivator.ghosttyFocus(folder: folder, using: io)
                done.leave()
            }
        }
        #expect(done.wait(timeout: .now() + 10) == .success)
        let steps = log.all
        let clicks = steps.map { $0.prefix(1) }
        // All of one click's steps, then all of the other's.
        let firstClick = clicks.first
        let switchIndex = clicks.firstIndex { $0 != firstClick } ?? clicks.endIndex
        #expect(clicks[switchIndex...].allSatisfy { $0 != firstClick }, "\(steps)")
        #expect(steps.filter { $0.hasSuffix("write") }.count == 4)
    }
}
