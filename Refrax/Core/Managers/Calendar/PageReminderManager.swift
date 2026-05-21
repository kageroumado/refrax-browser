import EventKit
import Foundation
import Observation
import UserNotifications

/// Preset reminder durations for quick selection.
enum ReminderDuration: CaseIterable, Identifiable {
    case fifteenMinutes
    case oneHour
    case tomorrowMorning
    case custom

    var id: Self { self }

    var label: String {
        switch self {
        case .fifteenMinutes:
            "15 min"
        case .oneHour:
            "1 hour"
        case .tomorrowMorning:
            "Tomorrow"
        case .custom:
            "Custom"
        }
    }

    var icon: String {
        switch self {
        case .fifteenMinutes:
            "clock.badge.questionmark"
        case .oneHour:
            "clock"
        case .tomorrowMorning:
            "sunrise"
        case .custom:
            "calendar.badge.clock"
        }
    }

    /// Calculates the reminder date from now.
    func date(from now: Date = Date()) -> Date? {
        let calendar = Calendar.current
        switch self {
        case .fifteenMinutes:
            return calendar.date(byAdding: .minute, value: 15, to: now)
        case .oneHour:
            return calendar.date(byAdding: .hour, value: 1, to: now)
        case .tomorrowMorning:
            // 9 AM tomorrow
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else {
                return nil
            }
            return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow)
        case .custom:
            return nil
        }
    }
}

/// Represents a page reminder configuration.
struct PageReminder: Sendable, Equatable {
    let pageURL: URL
    let pageTitle: String
    let reminderDate: Date
    let useSystemReminder: Bool

    /// Formatted time remaining until reminder.
    var formattedTimeUntil: String {
        let interval = reminderDate.timeIntervalSinceNow
        if interval < 0 {
            return "Now"
        }

        let hours = Int(interval) / 3_600
        let minutes = (Int(interval) % 3_600) / 60

        if hours > 0 {
            return hours == 1 ? "in 1 hour" : "in \(hours) hours"
        } else if minutes > 0 {
            return minutes == 1 ? "in 1 minute" : "in \(minutes) minutes"
        } else {
            return "in less than a minute"
        }
    }
}

/// A pending reminder displayed in the reminders widget.
struct PendingReminderItem: Identifiable, Equatable {
    let id: String
    let pageURL: URL
    let pageTitle: String
    let fireDate: Date
    let isSystemReminder: Bool

    var host: String {
        pageURL.host ?? pageURL.absoluteString
    }

    var formattedFireDate: String {
        let interval = fireDate.timeIntervalSinceNow
        if interval < 0 {
            return "Now"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: fireDate, relativeTo: Date())
    }

    var formattedAbsoluteTime: String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        if calendar.isDateInToday(fireDate) {
            formatter.dateFormat = "h:mm a"
        } else if calendar.isDateInTomorrow(fireDate) {
            formatter.dateFormat = "'Tomorrow' h:mm a"
        } else {
            formatter.dateFormat = "MMM d, h:mm a"
        }
        return formatter.string(from: fireDate)
    }
}

/// Manages page reminders using system notifications and Reminders.app.
///
/// Provides two reminder mechanisms:
/// - **Browser notifications**: Quick, session-based reminders using `UNUserNotificationCenter`
/// - **System reminders**: Persistent reminders via `Reminders.app` that sync across devices
///
/// ## Usage
///
/// ```swift
/// let manager = PageReminderManager()
/// let reminder = PageReminder(
///     pageURL: url,
///     pageTitle: "Article",
///     reminderDate: Date().addingTimeInterval(15 * 60),
///     useSystemReminder: false
/// )
/// try await manager.scheduleReminder(reminder)
/// ```
@Observable
final class PageReminderManager {
    // MARK: - Dependencies

    private let eventStore: EKEventStore
    private let notificationCenter: UNUserNotificationCenter

    // MARK: - State

    /// Current authorization status for Reminders.app access.
    private(set) var remindersAuthStatus: EKAuthorizationStatus = .notDetermined

    /// Current authorization status for notifications.
    private(set) var notificationAuthStatus: UNAuthorizationStatus = .notDetermined

    /// Error from the last operation.
    private(set) var lastError: String?

    /// All pending page reminders, sorted by fire date.
    private(set) var pendingItems: [PendingReminderItem] = []

    /// Whether there are any pending reminders.
    var hasPendingReminders: Bool { !pendingItems.isEmpty }

    // MARK: - Notification Identifiers

    /// Prefix for all page reminder notifications.
    private static let notificationPrefix = "com.refrax.pagereminder."

    /// User info key for the page URL.
    static let urlUserInfoKey = "pageURL"

    // MARK: - Initialization

    init() {
        self.eventStore = EKEventStore()
        self.notificationCenter = UNUserNotificationCenter.current()
        self.remindersAuthStatus = EKEventStore.authorizationStatus(for: .reminder)

        Task {
            let settings = await notificationCenter.notificationSettings()
            self.notificationAuthStatus = settings.authorizationStatus
            await self.refreshPendingItems()
        }

        Logger.info("PageReminderManager initialized", category: Logger.calendar)
    }

    // MARK: - Authorization

    /// Requests notification permission if needed.
    ///
    /// - Returns: Whether notifications are authorized.
    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            await checkNotificationStatus()
            return granted
        } catch {
            Logger.error("Failed to request notification permission: \(error)", category: Logger.calendar)
            return false
        }
    }

    /// Requests Reminders.app access.
    ///
    /// - Returns: Whether access was granted.
    func requestRemindersAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            remindersAuthStatus = EKEventStore.authorizationStatus(for: .reminder)
            return granted
        } catch {
            Logger.error("Failed to request reminders access: \(error)", category: Logger.calendar)
            remindersAuthStatus = .denied
            return false
        }
    }

    private func checkNotificationStatus() async {
        let settings = await notificationCenter.notificationSettings()
        notificationAuthStatus = settings.authorizationStatus
    }

    // MARK: - Reminder Scheduling

    /// Schedules a reminder for a page.
    ///
    /// - Parameter reminder: The reminder configuration.
    /// - Throws: `ReminderError` if scheduling fails.
    func scheduleReminder(_ reminder: PageReminder) async throws {
        lastError = nil

        if reminder.useSystemReminder {
            try await createSystemReminder(reminder)
            Logger.info(
                "Created system reminder for '\(reminder.pageTitle)' at \(reminder.reminderDate)",
                category: Logger.calendar,
            )
        } else {
            try await scheduleBrowserNotification(reminder)
            Logger.info(
                "Scheduled browser notification for '\(reminder.pageTitle)' at \(reminder.reminderDate)",
                category: Logger.calendar,
            )
        }

        await refreshPendingItems()
    }

    /// Creates a reminder in Reminders.app.
    private func createSystemReminder(_ reminder: PageReminder) async throws {
        // Request access if not authorized
        if remindersAuthStatus != .fullAccess {
            let granted = await requestRemindersAccess()
            guard granted else {
                lastError = "Reminders access denied"
                throw ReminderError.accessDenied(.reminders)
            }
        }

        // Create the reminder
        let ekReminder = EKReminder(eventStore: eventStore)
        ekReminder.title = reminder.pageTitle
        ekReminder.notes = reminder.pageURL.absoluteString
        ekReminder.url = reminder.pageURL

        // Set alarm for the reminder time
        let alarm = EKAlarm(absoluteDate: reminder.reminderDate)
        ekReminder.addAlarm(alarm)

        // Set due date components
        let calendar = Calendar.current
        ekReminder.dueDateComponents = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminder.reminderDate,
        )

        // Use default reminders list
        guard let defaultList = eventStore.defaultCalendarForNewReminders() else {
            lastError = "No default reminders list found"
            throw ReminderError.noDefaultList
        }
        ekReminder.calendar = defaultList

        // Save the reminder
        do {
            try eventStore.save(ekReminder, commit: true)
        } catch {
            lastError = error.localizedDescription
            throw ReminderError.saveFailed(error)
        }
    }

    /// Schedules a local notification for the reminder.
    private func scheduleBrowserNotification(_ reminder: PageReminder) async throws {
        // Request permission if not authorized
        if notificationAuthStatus != .authorized, notificationAuthStatus != .provisional {
            let granted = await requestNotificationPermission()
            guard granted else {
                lastError = "Notification permission denied"
                throw ReminderError.accessDenied(.notifications)
            }
        }

        // Create notification content
        let content = UNMutableNotificationContent()
        content.title = "Page Reminder"
        content.body = reminder.pageTitle
        content.sound = .default
        content.userInfo = [
            Self.urlUserInfoKey: reminder.pageURL.absoluteString,
        ]

        // Category for actions
        content.categoryIdentifier = "PAGE_REMINDER"

        // Calculate time interval
        let interval = reminder.reminderDate.timeIntervalSinceNow
        guard interval > 0 else {
            lastError = "Reminder time must be in the future"
            throw ReminderError.invalidTime
        }

        // Create trigger
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: interval,
            repeats: false,
        )

        // Create request with unique identifier
        let identifier = Self.notificationPrefix + UUID().uuidString
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger,
        )

        // Schedule the notification
        do {
            try await notificationCenter.add(request)
        } catch {
            lastError = error.localizedDescription
            throw ReminderError.scheduleFailed(error)
        }
    }

    // MARK: - Notification Handling

    /// Registers notification categories for page reminder actions.
    func registerNotificationCategories() {
        let openAction = UNNotificationAction(
            identifier: "OPEN_PAGE",
            title: "Open Page",
            options: [.foreground],
        )

        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: [],
        )

        let snoozeAction = UNNotificationAction(
            identifier: "SNOOZE_15",
            title: "Snooze 15 min",
            options: [],
        )

        let category = UNNotificationCategory(
            identifier: "PAGE_REMINDER",
            actions: [openAction, snoozeAction, dismissAction],
            intentIdentifiers: [],
            options: [],
        )

        notificationCenter.setNotificationCategories([category])
    }

    /// Handles a notification response (called from app delegate).
    ///
    /// - Parameters:
    ///   - response: The notification response.
    ///   - openURL: Callback to open a URL.
    func handleNotificationResponse(
        _ response: UNNotificationResponse,
        openURL: (URL) -> Void,
    ) {
        let userInfo = response.notification.request.content.userInfo

        guard let urlString = userInfo[Self.urlUserInfoKey] as? String,
              let url = URL(string: urlString)
        else {
            return
        }

        switch response.actionIdentifier {
        case "OPEN_PAGE", UNNotificationDefaultActionIdentifier:
            openURL(url)

        case "SNOOZE_15":
            // Reschedule for 15 minutes from now
            Task { @MainActor in
                let reminder = PageReminder(
                    pageURL: url,
                    pageTitle: response.notification.request.content.body,
                    reminderDate: Date().addingTimeInterval(15 * 60),
                    useSystemReminder: false,
                )
                try? await scheduleReminder(reminder)
            }

        case "DISMISS", _:
            break
        }

        // Refresh list after handling (notification was delivered, no longer pending)
        Task {
            await refreshPendingItems()
        }
    }

    // MARK: - Pending Reminders

    /// Gets all pending page reminder notifications.
    func pendingReminders() async -> [UNNotificationRequest] {
        let pending = await notificationCenter.pendingNotificationRequests()
        return pending.filter { $0.identifier.hasPrefix(Self.notificationPrefix) }
    }

    /// Refreshes the observable list of pending reminder items.
    func refreshPendingItems() async {
        let requests = await pendingReminders()
        let items = requests.compactMap { request -> PendingReminderItem? in
            guard let trigger = request.trigger as? UNTimeIntervalNotificationTrigger,
                  let nextDate = trigger.nextTriggerDate()
            else {
                return nil
            }

            let urlString = request.content.userInfo[Self.urlUserInfoKey] as? String
            let url = urlString.flatMap(URL.init(string:)) ?? .blank

            return PendingReminderItem(
                id: request.identifier,
                pageURL: url,
                pageTitle: request.content.body,
                fireDate: nextDate,
                isSystemReminder: false,
            )
        }
        .sorted { $0.fireDate < $1.fireDate }

        pendingItems = items
    }

    /// Cancels a pending reminder.
    func cancelReminder(identifier: String) async {
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [identifier])
        await refreshPendingItems()
    }

    /// Cancels all pending page reminders.
    func cancelAllReminders() async {
        let pending = await pendingReminders()
        let identifiers = pending.map(\.identifier)
        notificationCenter.removePendingNotificationRequests(withIdentifiers: identifiers)
        pendingItems = []
    }
}

// MARK: - Errors

enum ReminderError: LocalizedError {
    case accessDenied(AccessType)
    case noDefaultList
    case invalidTime
    case saveFailed(any Error)
    case scheduleFailed(any Error)

    enum AccessType {
        case reminders
        case notifications
    }

    var errorDescription: String? {
        switch self {
        case let .accessDenied(type):
            switch type {
            case .reminders:
                "Access to Reminders was denied. Please enable it in System Settings."
            case .notifications:
                "Notification permission was denied. Please enable it in System Settings."
            }
        case .noDefaultList:
            "No default reminders list found. Please set one in Reminders.app."
        case .invalidTime:
            "Reminder time must be in the future."
        case let .saveFailed(error):
            "Failed to save reminder: \(error.localizedDescription)"
        case let .scheduleFailed(error):
            "Failed to schedule notification: \(error.localizedDescription)"
        }
    }
}
