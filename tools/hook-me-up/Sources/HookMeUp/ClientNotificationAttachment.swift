import Foundation
import HookMeUpCore
import UserNotifications

/// A disposable copy: UserNotifications moves its file when scheduling the request.
struct ClientNotificationAttachment {
    let attachment: UNNotificationAttachment
    let directory: URL

    static func prepare(
        for client: HookClient, resourceFolder: URL? = Bundle.main.resourceURL,
        temporaryFolder: URL = FileManager.default.temporaryDirectory,
        makeAttachment: (String, URL) throws -> UNNotificationAttachment = {
            try UNNotificationAttachment(identifier: $0, url: $1, options: nil)
        }
    ) -> ClientNotificationAttachment? {
        guard let resourceFolder else { return nil }
        let directory = temporaryFolder.appendingPathComponent(
            "hmu-notification-" + UUID().uuidString, isDirectory: true)
        let name = client.notificationImageName + ".png"
        let copy = directory.appendingPathComponent(name)
        let files = FileManager.default
        do {
            try files.createDirectory(
                at: directory, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
            try files.copyItem(at: resourceFolder.appendingPathComponent(name), to: copy)
            let attachment = try makeAttachment(client.rawValue, copy)
            return ClientNotificationAttachment(attachment: attachment, directory: directory)
        } catch {
            try? files.removeItem(at: directory)
            return nil
        }
    }
}
