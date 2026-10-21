import Foundation
import OpenMarginCore
import UserNotifications

/// Local notification actions for the start prompt. AppModel is not an NSObject, so this stays separate.
final class NotificationBridge: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationBridge()
    static let categoryID = "openmargin.listen"
    static let listenAction = "listen"
    static let dismissAction = "dismiss"

    var onListen: (@MainActor (String) -> Void)?
    var onDismiss: (@MainActor (String) -> Void)?
    private var withdrawn: Set<String> = []

    @MainActor
    func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let listen = UNNotificationAction(identifier: Self.listenAction, title: "Listen", options: [.foreground])
        let later = UNNotificationAction(identifier: Self.dismissAction, title: "Not now", options: [])
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [listen, later],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    @MainActor
    func post(_ offer: StartCandidate) {
        withdrawn.remove(offer.id)
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                await self.deliverIfAllowed(offer, status: status)
            }
        }
    }

    @MainActor
    func withdraw(_ id: String) {
        withdrawn.insert(id)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    @MainActor
    private func deliverIfAllowed(_ offer: StartCandidate, status: UNAuthorizationStatus) async {
        switch status {
        case .notDetermined:
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
            if granted { deliver(offer) }
        case .authorized, .provisional, .ephemeral:
            deliver(offer)
        case .denied:
            break
        @unknown default:
            break
        }
    }

    @MainActor
    private func deliver(_ offer: StartCandidate) {
        guard !withdrawn.contains(offer.id) else { return }
        let content = UNMutableNotificationContent()
        content.title = offer.promptTitle
        content.body = "Listen to this meeting? Tell the other people if you do."
        content.categoryIdentifier = Self.categoryID
        content.sound = .default
        let request = UNNotificationRequest(identifier: offer.id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let id = response.notification.request.identifier
        let listen = response.actionIdentifier != Self.dismissAction
        await MainActor.run {
            if listen {
                NotificationBridge.shared.onListen?(id)
            } else {
                NotificationBridge.shared.onDismiss?(id)
            }
        }
    }
}
