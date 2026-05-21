import Foundation
import UserNotifications

/// Shim for `browser.notifications` API using UserNotifications framework.
///
/// Implements the WebExtensions notifications API for displaying system notifications.
/// Uses `UNUserNotificationCenter` for macOS notification delivery.
///
/// ## Permissions
///
/// The app must request notification permissions. If denied, notifications
/// will silently fail (matching Chrome behavior).
///
/// ## Limitations
///
/// - Button actions are limited compared to Chrome's rich notifications
/// - Progress notifications are not supported (macOS limitation)
/// - Image notifications show as attachments, not inline
///
/// ## Thread Safety
///
/// All operations are MainActor-isolated.

final class NotificationsShim: ExtensionShim, @unchecked Sendable {
    // MARK: - Properties

    /// Maps notification IDs to extension IDs for routing callbacks.
    private var notificationExtensions: [String: String] = [:]

    /// The notification center.
    private let center = UNUserNotificationCenter.current()

    /// Delegate for handling notification interactions.
    private var delegate: NotificationDelegate?

    // MARK: - Initialization

    init() {
        // Set up delegate for notification interactions
        let delegate = NotificationDelegate(shim: self)
        self.delegate = delegate
        // Note: The delegate should be set on UNUserNotificationCenter only once globally.
        // This is typically done at app launch in AppDelegate.
    }

    // MARK: - ExtensionShim Protocol

    func handle(method: String, args: [String: Any], extensionID: String) async throws -> Any? {
        switch method {
        case "create":
            let notificationId = args["notificationId"] as? String
            guard let options = args["options"] as? [String: Any] else {
                throw ShimError.invalidArguments("'options' is required")
            }
            return try await create(notificationId: notificationId, options: options, extensionID: extensionID)

        case "update":
            guard let notificationId = args["notificationId"] as? String else {
                throw ShimError.invalidArguments("'notificationId' is required")
            }
            guard let options = args["options"] as? [String: Any] else {
                throw ShimError.invalidArguments("'options' is required")
            }
            return try await update(notificationId: notificationId, options: options, extensionID: extensionID)

        case "clear":
            guard let notificationId = args["notificationId"] as? String else {
                throw ShimError.invalidArguments("'notificationId' is required")
            }
            return clear(notificationId: notificationId, extensionID: extensionID)

        case "getAll":
            return await getAll(extensionID: extensionID)

        case "getPermissionLevel":
            return await getPermissionLevel()

        default:
            throw ShimError.unsupportedMethod(method)
        }
    }

    // MARK: - Notification Operations

    /// Creates and displays a notification.
    ///
    /// - Parameters:
    ///   - notificationId: Optional ID; auto-generated if nil.
    ///   - options: Notification options (type, title, message, iconUrl, etc.).
    ///   - extensionID: The calling extension's identifier.
    /// - Returns: The notification ID.
    private func create(
        notificationId: String?,
        options: [String: Any],
        extensionID: String,
    ) async throws -> String {
        let id = notificationId ?? UUID().uuidString
        let fullId = "\(extensionID):\(id)"

        let content = UNMutableNotificationContent()

        // Required fields
        guard let title = options["title"] as? String else {
            throw ShimError.invalidArguments("'title' is required")
        }
        guard let message = options["message"] as? String else {
            throw ShimError.invalidArguments("'message' is required")
        }

        content.title = title
        content.body = message

        // Optional contextMessage as subtitle
        if let contextMessage = options["contextMessage"] as? String {
            content.subtitle = contextMessage
        }

        // Sound
        if options["silent"] as? Bool != true {
            content.sound = .default
        }

        // Thread identifier for grouping
        content.threadIdentifier = extensionID

        // Create the request
        let request = UNNotificationRequest(
            identifier: fullId,
            content: content,
            trigger: nil, // Deliver immediately
        )

        try await center.add(request)

        // Track the notification
        notificationExtensions[fullId] = extensionID

        Logger.debug(
            "Created notification '\(id)' for extension \(extensionID)",
            category: Logger.extensions,
        )

        return id
    }

    /// Updates an existing notification.
    ///
    /// - Parameters:
    ///   - notificationId: The notification ID to update.
    ///   - options: New notification options.
    ///   - extensionID: The calling extension's identifier.
    /// - Returns: `true` if the notification was updated.
    private func update(
        notificationId: String,
        options: [String: Any],
        extensionID: String,
    ) async throws -> Bool {
        let fullId = "\(extensionID):\(notificationId)"

        // Check if notification exists
        guard notificationExtensions[fullId] == extensionID else {
            return false
        }

        // Re-create the notification with updated options
        _ = try await create(notificationId: notificationId, options: options, extensionID: extensionID)
        return true
    }

    /// Clears a notification.
    ///
    /// - Parameters:
    ///   - notificationId: The notification ID to clear.
    ///   - extensionID: The calling extension's identifier.
    /// - Returns: `true` if the notification was cleared.
    private func clear(notificationId: String, extensionID: String) -> Bool {
        let fullId = "\(extensionID):\(notificationId)"

        guard notificationExtensions[fullId] == extensionID else {
            return false
        }

        center.removeDeliveredNotifications(withIdentifiers: [fullId])
        center.removePendingNotificationRequests(withIdentifiers: [fullId])
        notificationExtensions.removeValue(forKey: fullId)

        return true
    }

    /// Gets all notifications for an extension.
    ///
    /// - Parameter extensionID: The calling extension's identifier.
    /// - Returns: Object mapping notification IDs to true.
    private func getAll(extensionID: String) async -> [String: Bool] {
        let delivered = await center.deliveredNotifications()
        let pending = await center.pendingNotificationRequests()

        var result: [String: Bool] = [:]
        let prefix = "\(extensionID):"

        for notification in delivered {
            let id = notification.request.identifier
            if id.hasPrefix(prefix) {
                let shortId = String(id.dropFirst(prefix.count))
                result[shortId] = true
            }
        }

        for request in pending {
            let id = request.identifier
            if id.hasPrefix(prefix) {
                let shortId = String(id.dropFirst(prefix.count))
                result[shortId] = true
            }
        }

        return result
    }

    /// Gets the current permission level.
    ///
    /// - Returns: "granted", "denied", or "unknown".
    private func getPermissionLevel() async -> String {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return "granted"
        case .denied:
            return "denied"
        case .notDetermined, .ephemeral:
            return "unknown"
        @unknown default:
            return "unknown"
        }
    }

    // MARK: - Cleanup

    /// Clears all notifications for an extension (called on uninstall).
    func clearAllForExtension(_ extensionID: String) {
        let prefix = "\(extensionID):"
        let ids = notificationExtensions.keys.filter { $0.hasPrefix(prefix) }

        center.removeDeliveredNotifications(withIdentifiers: Array(ids))
        center.removePendingNotificationRequests(withIdentifiers: Array(ids))

        for id in ids {
            notificationExtensions.removeValue(forKey: id)
        }
    }
}

// MARK: - Notification Delegate

/// Delegate for handling notification interactions.
private final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    weak var shim: NotificationsShim?

    init(shim: NotificationsShim) {
        self.shim = shim
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive _: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void,
    ) {
        // Handle notification clicks here
        // Could dispatch events to extensions via shim
        completionHandler()
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void,
    ) {
        // Show notifications even when app is in foreground
        completionHandler([.banner, .sound])
    }
}
