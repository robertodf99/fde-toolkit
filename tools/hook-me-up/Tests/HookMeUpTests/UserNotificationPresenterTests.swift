import HookMeUpCore
import Testing
import UserNotifications

@testable import HookMeUp

/// The UserNotifications mapping (no notification center needed).
@Suite struct UserNotificationPresenterTests {
    private let spec = NotificationSpec(
        identifier: "11111111-2222-3333-4444-555555555555", threadIdentifier: "acme-api",
        categoryIdentifier: "permission", title: "acme-api · Needs permission", body: "Run a command\nls",
        actions: [
            .init(identifier: "approve", title: "Approve", requiresAuthentication: true),
            .init(identifier: "deny", title: "Deny", style: .destructive, requiresAuthentication: true),
            .init(
                identifier: "reply", title: "Reply…", textInput: .init(buttonTitle: "Send", placeholder: "e.g. 1, 3")),
        ])

    @Test func contentCarriesTitleBodyThreadCategoryAndSound() {
        let content = UserNotificationPresenter.content(for: spec)
        #expect(content.title == "acme-api · Needs permission")
        #expect(content.body == "Run a command\nls")
        #expect(content.threadIdentifier == "acme-api")
        #expect(content.categoryIdentifier == "permission")
        #expect(content.sound != nil)
        var silent = spec
        silent.playsSound = false
        #expect(UserNotificationPresenter.content(for: silent).sound == nil)
    }

    @Test func actionsKeepTheirStyleAndTextInput() {
        let category = UserNotificationPresenter.category("permission", actions: spec.actions)
        #expect(category.identifier == "permission")
        #expect(category.actions.map(\.identifier) == ["approve", "deny", "reply"])
        #expect(category.actions[0].options == .authenticationRequired)
        #expect(category.actions[1].options == [.destructive, .authenticationRequired])
        let reply = category.actions[2] as? UNTextInputNotificationAction
        #expect(reply?.textInputButtonTitle == "Send")
        #expect(reply?.textInputPlaceholder == "e.g. 1, 3")
        #expect(!(category.actions[0] is UNTextInputNotificationAction))
    }

    @Test func responsesMapToTheCoreResponse() {
        typealias P = UserNotificationPresenter
        #expect(P.response(actionIdentifier: UNNotificationDefaultActionIdentifier, text: nil) == .defaultClick)
        #expect(P.response(actionIdentifier: UNNotificationDismissActionIdentifier, text: nil) == .dismissed)
        #expect(P.response(actionIdentifier: "approve", text: nil) == .action("approve"))
        #expect(P.response(actionIdentifier: "reply", text: "1, 3") == .text(action: "reply", text: "1, 3"))
    }

    @Test func authorizationMapsStatusAndStyle() {
        typealias P = UserNotificationPresenter
        #expect(P.authorization(status: .authorized, alertStyle: .alert).allowsNotifications)
        #expect(!P.authorization(status: .denied, alertStyle: .none).allowsNotifications)
        #expect(!P.authorization(status: .notDetermined, alertStyle: .none).allowsNotifications)
        #expect(P.authorization(status: .authorized, alertStyle: .banner).description == "authorized, style banner")
    }
}
