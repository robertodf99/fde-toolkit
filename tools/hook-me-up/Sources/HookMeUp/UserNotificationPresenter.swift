import AgentKit
import Foundation
import HookMeUpCore
import UserNotifications

/// Shows the agent's notifications with UNUserNotificationCenter and reports what the
/// user does with them. Works only from the app bundle (macOS keeps the permission
/// per bundle id).
@MainActor
final class UserNotificationPresenter: NSObject, NotificationPresenting {
    /// Receives each response on the main actor: (response, notification identifier,
    /// category identifier).
    var onResponse: ((NotificationResponse, String, String) -> Void)?

    private let center: UNUserNotificationCenter
    /// What is shown (or about to be) per identifier; a late add for anything else is dropped.
    private var current: [String: NotificationSpec] = [:]
    /// The registered categories' buttons, by category identifier.
    private var registered: [String: [NotificationActionSpec]] = [:]

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
        // Notifications from an earlier run belong to requests that no longer exist.
        center.removeAllDeliveredNotifications()
        center.removeAllPendingNotificationRequests()
    }

    func requestAuthorization() async -> NotificationAuthorization {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        return await authorization()
    }

    func authorization() async -> NotificationAuthorization {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { settings in
                continuation.resume(
                    returning: Self.authorization(
                        status: settings.authorizationStatus,
                        alertStyle: settings.alertStyle))
            }
        }
    }

    func post(_ spec: NotificationSpec) {
        current[spec.identifier] = spec
        // A notification without a category (the installer's test) registers none.
        if !spec.categoryIdentifier.isEmpty, registered[spec.categoryIdentifier] != spec.actions {
            registered[spec.categoryIdentifier] = spec.actions
            registerCategories()
        }
        // Reading the categories back waits until the new set is registered, so the
        // notification never shows up without its buttons.
        center.getNotificationCategories { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.add(spec) }
            }
        }
    }

    func remove(identifiers: [String]) {
        for identifier in identifiers { current[identifier] = nil }
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        // Drop the buttons nobody uses any more (questions and session approvals have
        // a category per notification).
        let used = Set(current.values.map(\.categoryIdentifier))
        let unused = registered.keys.filter { !used.contains($0) }
        guard !unused.isEmpty else { return }
        for category in unused { registered[category] = nil }
        registerCategories()
    }

    private func add(_ spec: NotificationSpec) {
        guard current[spec.identifier] == spec else { return }  // replaced or removed meanwhile
        let request = UNNotificationRequest(identifier: spec.identifier, content: Self.content(for: spec), trigger: nil)
        center.add(request) { [weak self] error in
            if let error {
                AgentLog.info("notification \(spec.identifier.prefix(8)) not posted: \(error)")
                return
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.logDelivered(after: spec.identifier) }
            }
        }
    }

    /// Lists what macOS shows now (short ids only), to confirm a post took effect.
    private func logDelivered(after identifier: String) {
        center.getDeliveredNotifications { delivered in
            let identifiers = delivered.map { String($0.request.identifier.prefix(8)) }.sorted()
            AgentLog.info("posted \(identifier.prefix(8)); delivered now: \(identifiers.joined(separator: ", "))")
        }
    }

    private func registerCategories() {
        center.setNotificationCategories(Set(registered.map { Self.category($0.key, actions: $0.value) }))
    }

    // MARK: Mapping (pure, tested)

    nonisolated static func content(for spec: NotificationSpec) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = spec.title
        content.body = spec.body
        content.threadIdentifier = spec.threadIdentifier
        content.categoryIdentifier = spec.categoryIdentifier
        content.sound = spec.playsSound ? .default : nil
        return content
    }

    nonisolated static func category(_ identifier: String, actions: [NotificationActionSpec]) -> UNNotificationCategory
    {
        let actions = actions.map { action -> UNNotificationAction in
            var options: UNNotificationActionOptions =
                switch action.style {
                case .normal: []
                case .destructive: .destructive
                }
            if action.requiresAuthentication { options.insert(.authenticationRequired) }
            if let input = action.textInput {
                return UNTextInputNotificationAction(
                    identifier: action.identifier, title: action.title, options: options,
                    textInputButtonTitle: input.buttonTitle,
                    textInputPlaceholder: input.placeholder)
            }
            return UNNotificationAction(identifier: action.identifier, title: action.title, options: options)
        }
        return UNNotificationCategory(identifier: identifier, actions: actions, intentIdentifiers: [], options: [])
    }

    nonisolated static func response(actionIdentifier: String, text: String?) -> NotificationResponse {
        switch actionIdentifier {
        case UNNotificationDefaultActionIdentifier: .defaultClick
        case UNNotificationDismissActionIdentifier: .dismissed
        default: text.map { .text(action: actionIdentifier, text: $0) } ?? .action(actionIdentifier)
        }
    }

    nonisolated static func authorization(status: UNAuthorizationStatus, alertStyle: UNAlertStyle)
        -> NotificationAuthorization
    {
        let mappedStatus: NotificationAuthorization.Status =
            switch status {
            case .authorized, .ephemeral: .authorized
            case .provisional: .provisional
            case .denied: .denied
            case .notDetermined: .notDetermined
            @unknown default: .denied
            }
        let mappedStyle: NotificationAuthorization.AlertStyle =
            switch alertStyle {
            case .alert: .alert
            case .banner: .banner
            case .none: .none
            @unknown default: .none
            }
        return NotificationAuthorization(status: mappedStatus, alertStyle: mappedStyle)
    }
}

extension UserNotificationPresenter: UNUserNotificationCenterDelegate {
    /// Shown even when the app is frontmost, with the native sound.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler:
            @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        let category = response.notification.request.content.categoryIdentifier
        let mapped = Self.response(
            actionIdentifier: response.actionIdentifier,
            text: (response as? UNTextInputNotificationResponse)?.userText)
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.onResponse?(mapped, identifier, category) }
        }
        completionHandler()
    }
}
