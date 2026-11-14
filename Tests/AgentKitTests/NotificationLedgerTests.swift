import HookMeUpCore
import Testing

@testable import AgentKit

private func spec(_ id: String, body: String = "b", sound: Bool = true) -> NotificationSpec {
    NotificationSpec(
        identifier: id, threadIdentifier: "acme-api", categoryIdentifier: "permission", title: "t",
        body: body, actions: [], playsSound: sound)
}

@Suite struct NotificationLedgerTests {
    @Test func aNewNotificationPlaysItsSoundOnlyTheFirstTime() {
        var ledger = NotificationLedger()
        #expect(ledger.update(to: [spec("a")]).post.map(\.playsSound) == [true])
        #expect(ledger.update(to: [spec("a", body: "next question")]).post.map(\.playsSound) == [false])
    }

    @Test func aSilentSpecStaysSilent() {
        var ledger = NotificationLedger()
        #expect(ledger.update(to: [spec("a", sound: false)]).post.map(\.playsSound) == [false])
    }

    @Test func unchangedNotificationsAreNotPostedAgain() {
        var ledger = NotificationLedger()
        _ = ledger.update(to: [spec("a"), spec("b")])
        let changes = ledger.update(to: [spec("a"), spec("b")])
        #expect(changes.post.isEmpty)
        #expect(changes.remove.isEmpty)
    }

    @Test func anActedOnNotificationIsPostedAgainSilentlyWhileItsEntryWaits() {
        var ledger = NotificationLedger()
        _ = ledger.update(to: [spec("a")])
        ledger.noteActedOn("a")
        #expect(ledger.update(to: [spec("a")]).post.map(\.playsSound) == [false])
        #expect(ledger.update(to: [spec("a")]).post.isEmpty)
    }

    @Test func anActedOnNotificationWhoseEntryEndedIsRemoved() {
        var ledger = NotificationLedger()
        _ = ledger.update(to: [spec("a")])
        ledger.noteActedOn("a")
        let changes = ledger.update(to: [])
        #expect(changes.post.isEmpty)
        #expect(changes.remove == ["a"])
    }

    @Test func aRemovedIdentifierRingsAgainIfItComesBack() {
        var ledger = NotificationLedger()
        _ = ledger.update(to: [spec("a")])
        _ = ledger.update(to: [])
        #expect(ledger.update(to: [spec("a")]).post.map(\.playsSound) == [true])
    }
}
