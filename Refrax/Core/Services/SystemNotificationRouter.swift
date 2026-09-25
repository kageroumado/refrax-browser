import Foundation
import UserNotifications

/// Refrax's one `UNUserNotificationCenter` delegate: shows notifications while Refrax is in
/// front and sends each response to the feature that posted it.
///
/// macOS allows a single delegate per app, so every feature posting notifications is routed
/// from here: web notifications to ``WebNotificationManager``, page reminders to
/// ``PageReminderManager``.
final class SystemNotificationRouter: NSObject, nonisolated UNUserNotificationCenterDelegate {
    private let webNotifications: WebNotificationManager
    private let pageReminders: PageReminderManager
    private let openURL: (URL) -> Void

    init(
        webNotifications: WebNotificationManager,
        pageReminders: PageReminderManager,
        openURL: @escaping (URL) -> Void,
    ) {
        self.webNotifications = webNotifications
        self.pageReminders = pageReminders
        self.openURL = openURL
    }

    /// Becomes the delegate and registers every feature's notification categories. Call before
    /// launch finishes, so a click that launched Refrax is delivered.
    func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            PageReminderManager.notificationCategory,
            UNNotificationCategory(
                identifier: WebNotificationContentBuilder.categoryIdentifier,
                actions: [],
                intentIdentifiers: [],
                options: [.customDismissAction],
            ),
        ])
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
    ) async {
        let action = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo
        if let webNotification = WebNotificationUserInfo(userInfo) {
            let isDismissal = action == UNNotificationDismissActionIdentifier
            await MainActor.run {
                webNotifications.handle(isDismissal ? .dismissed : .clicked, to: webNotification)
            }
        } else if let reminder = PageReminderManager.ReminderResponse(action: action, userInfo: userInfo, body: response.notification.request.content.body) {
            await MainActor.run {
                pageReminders.handle(reminder, openURL: openURL)
            }
        }
    }
}
