import Foundation
import Testing

@testable import HookMeUpCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let noTerminal = TerminalHint(ancestorPIDs: [], tty: nil)

private func entry(_ name: String, session: String = "s1", kind: EntryKind = .permission) -> PendingStore.Entry {
    PendingStore.Entry(
        id: UUID(), sessionID: session, kind: kind,
        summary: RequestSummary(kind: kind, title: name, description: "", tags: [], origin: nil),
        project: ProjectInfo(name: "p", gitRoot: nil, branch: nil, worktree: nil),
        terminal: noTerminal)
}

private func titles(_ entries: [PendingStore.Entry]) -> [String] { entries.map(\.summary.title) }

@Suite struct PendingStoreTests {
    @Test func newEntriesAreAppendedWithoutMovingExistingOnes() {
        var store = PendingStore()
        for (index, name) in ["A", "B", "C"].enumerated() {
            store.add(entry(name, session: "s\(index)"))
        }
        #expect(titles(store.entries) == ["A", "B", "C"])
        store.add(entry("D", session: "s9"))
        #expect(titles(store.entries) == ["A", "B", "C", "D"])
    }

    @Test func newEntryReplacesTheSessionsWaitingAndFinishedEntries() {
        var store = PendingStore()
        store.add(entry("finished-1", session: "s1", kind: .finished))
        store.add(entry("perm-2", session: "s2"))
        store.add(entry("waiting-1", session: "s1", kind: .waiting))
        #expect(titles(store.entries) == ["perm-2", "waiting-1"])
        store.add(entry("perm-1", session: "s1"))
        #expect(titles(store.entries) == ["perm-2", "perm-1"])
        // Blocking entries of the session stay: each ends with its own hook connection.
        store.add(entry("perm-1b", session: "s1", kind: .question))
        #expect(titles(store.entries) == ["perm-2", "perm-1", "perm-1b"])
    }

    @Test func clearingASessionKeepsItsLiveRequests() {
        var store = PendingStore()
        store.add(entry("perm-1", session: "s1"))
        store.add(entry("waiting-1", session: "s1", kind: .waiting))
        store.add(entry("waiting-2", session: "s2", kind: .waiting))
        store.clear(sessionID: "s1")
        // Permission/question/plan entries end with their hook: a decision, its connection
        // closing, or AgentCore releasing it before it clears the session.
        #expect(titles(store.entries) == ["perm-1", "waiting-2"])

        store.add(entry("finished-1", session: "s1", kind: .finished))
        store.clear(sessionID: "s1")
        #expect(titles(store.entries) == ["perm-1", "waiting-2"])
    }

    @Test func removingAnUnknownEntryChangesNothing() {
        var store = PendingStore()
        store.add(entry("A"))
        store.remove(id: UUID())
        #expect(titles(store.entries) == ["A"])
    }

    @Test func timedOutEntryStaysWithItsState() {
        var store = PendingStore()
        let a = entry("A")
        store.add(a)
        store.markTimedOut(id: a.id)
        #expect(store.entries.map(\.id) == [a.id])
        #expect(store.entries.first?.state == .timedOut)
    }

    @Test func timedOutEntriesAreClearedWhenTheSessionMovesOn() {
        var store = PendingStore()
        let a = entry("timed-out")
        store.add(a)
        store.add(entry("live"))
        store.markTimedOut(id: a.id)
        store.clear(sessionID: "s1")
        #expect(titles(store.entries) == ["live"])

        let c = entry("timed-out-2")
        store.add(c)
        store.markTimedOut(id: c.id)
        store.add(entry("next"))  // the session's next entry replaces it
        #expect(titles(store.entries) == ["live", "next"])
    }

    @Test func pauseLastsUntilItsEndOrAResume() {
        var store = PendingStore()
        #expect(!store.isPaused(now: t0))
        store.pause(until: t0 + 1800)
        #expect(store.isPaused(now: t0))
        #expect(store.isPaused(now: t0 + 1799))
        #expect(!store.isPaused(now: t0 + 1800))
        store.resume()
        #expect(!store.isPaused(now: t0 + 10))
    }
}
