import AppKit
import Foundation
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

@Suite struct ClientNotificationAttachmentTests {
    private func image(in folder: URL, name: String) throws -> URL {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 16, pixelsHigh: 16,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let url = folder.appendingPathComponent(name + ".png")
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
        return url
    }

    private func spec(_ client: HookClient?) -> NotificationSpec {
        NotificationSpec(
            identifier: "test", threadIdentifier: "test", categoryIdentifier: "permission",
            title: "Test", body: "Keep this body", actions: [], clientImage: client)
    }

    @Test func eachClientUsesADisposableCopyAndKeepsTheBundleImage() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "hmu-attachment-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        for (client, name) in [(HookClient.claude, "notification-claude"), (.codex, "notification-codex")] {
            let source = try image(in: folder, name: name)
            let before = try Data(contentsOf: source)
            let prepared = try #require(
                ClientNotificationAttachment.prepare(for: client, resourceFolder: folder, temporaryFolder: folder))
            let content = UserNotificationPresenter.content(for: spec(client), attachment: prepared.attachment)
            #expect(content.attachments.count == 1)
            #expect(content.attachments.first?.identifier == client.rawValue)
            #expect(prepared.attachment.url != source)
            #expect(prepared.attachment.url.lastPathComponent == name + ".png")
            #expect(try Data(contentsOf: prepared.attachment.url) == before)
            #expect(try Data(contentsOf: source) == before)
            try FileManager.default.removeItem(at: prepared.directory)
            #expect(FileManager.default.fileExists(atPath: source.path))
        }
    }

    @Test func missingImageOrAttachmentFailureKeepsTheNotificationWithoutAnImage() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "hmu-attachment-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let missing = ClientNotificationAttachment.prepare(for: .codex, resourceFolder: folder, temporaryFolder: folder)
        #expect(missing == nil)
        let source = try image(in: folder, name: "notification-codex")
        var attempted = false
        let failed = ClientNotificationAttachment.prepare(for: .codex, resourceFolder: folder, temporaryFolder: folder)
        { _, _ in
            attempted = true
            throw CocoaError(.fileReadCorruptFile)
        }
        #expect(attempted)
        #expect(failed == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == [source.lastPathComponent])
        for prepared in [missing, failed] {
            let content = UserNotificationPresenter.content(for: spec(.codex), attachment: prepared?.attachment)
            #expect(content.attachments.isEmpty)
            #expect(content.title == "Test")
            #expect(content.body == "Keep this body")
            #expect(content.sound != nil)
        }
        #expect(UserNotificationPresenter.content(for: spec(nil)).attachments.isEmpty)
    }
}
