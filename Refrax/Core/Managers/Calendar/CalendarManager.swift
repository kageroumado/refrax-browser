import EventKit
import Foundation
import Observation

/// Represents a calendar event for display in the sidebar widget.
struct CalendarEvent: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
    let calendarColor: CGColor
    let calendarTitle: String
    let url: URL?
    let notes: String?
    let meetingURL: URL?

    /// Whether the event is currently happening.
    var isOngoing: Bool {
        let now = Date()
        return startDate <= now && endDate > now
    }

    /// Whether the event starts within the given number of minutes.
    func startsWithin(minutes: Int) -> Bool {
        let now = Date()
        let threshold = now.addingTimeInterval(TimeInterval(minutes * 60))
        return startDate > now && startDate <= threshold
    }

    /// Formatted time string for display.
    var formattedTime: String {
        if isAllDay {
            return "All Day"
        }

        let calendar = Calendar.current

        if calendar.isDateInToday(startDate) {
            return startDate.formatted(date: .omitted, time: .shortened)
        } else if calendar.isDateInTomorrow(startDate) {
            return "Tomorrow, \(startDate.formatted(date: .omitted, time: .shortened))"
        } else {
            return startDate.formatted(date: .abbreviated, time: .shortened)
        }
    }

    /// Formatted duration string.
    var formattedDuration: String? {
        guard !isAllDay else { return nil }
        let duration = endDate.timeIntervalSince(startDate)
        let hours = Int(duration) / 3_600
        let minutes = (Int(duration) % 3_600) / 60

        if hours > 0, minutes > 0 {
            return "\(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(minutes)m"
        }
    }

    /// Whether the event has a video meeting link.
    var hasMeeting: Bool {
        meetingURL != nil
    }

    // MARK: - Meeting URL Extraction

    /// Known video conferencing hosts.
    private static let meetingHosts = [
        "zoom.us",
        "meet.google.com",
        "teams.microsoft.com",
        "webex.com",
        "whereby.com",
        "around.co",
        "tuple.app",
        "facetime.apple.com",
        "chime.aws",
        "gotomeeting.com",
        "discord.com",
        "slack.com",
    ]

    /// Checks if a URL is a video meeting link.
    static func isMeetingURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return meetingHosts.contains { host.contains($0) }
    }

    /// Extracts a meeting URL from event fields.
    ///
    /// Checks in order:
    /// 1. Event URL field
    /// 2. Location field (if it's a URL)
    /// 3. Notes field (scans for URLs)
    static func extractMeetingURL(url: URL?, location: String?, notes: String?) -> URL? {
        // Check URL field first
        if let url, isMeetingURL(url) {
            return url
        }

        // Check location for URL
        if let location,
           let locationURL = URL(string: location),
           isMeetingURL(locationURL) {
            return locationURL
        }

        // Parse notes for meeting links
        if let notes {
            let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            let range = NSRange(notes.startIndex..., in: notes)
            let matches = detector?.matches(in: notes, range: range) ?? []

            for match in matches {
                if let matchURL = match.url, isMeetingURL(matchURL) {
                    return matchURL
                }
            }
        }

        return nil
    }
}

/// Represents a calendar for selection in settings.
struct CalendarInfo: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let color: CGColor
    let isSubscribed: Bool
    let source: String
}

/// Authorization status for calendar access.
enum CalendarAuthorizationStatus: Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted

    init(from ekStatus: EKAuthorizationStatus) {
        switch ekStatus {
        case .notDetermined:
            self = .notDetermined
        case .fullAccess, .writeOnly:
            self = .authorized
        case .denied:
            self = .denied
        case .restricted:
            self = .restricted
        @unknown default:
            self = .denied
        }
    }
}

/// Manages calendar integration via EventKit.
///
/// Provides access to the user's calendars and upcoming events for display
/// in the sidebar widget. Observes calendar changes and automatically
/// refreshes the event list.
///
/// ## Usage
///
/// ```swift
/// let manager = CalendarManager(settings: browserSettings)
/// await manager.requestAccess()
/// // Events are automatically populated in upcomingEvents
/// ```
@Observable
final class CalendarManager {
    // MARK: - Dependencies

    private let settings: BrowserSettings
    private let eventStore: EKEventStore

    // MARK: - State

    /// Current authorization status for calendar access.
    private(set) var authorizationStatus: CalendarAuthorizationStatus = .notDetermined

    /// Available calendars for selection.
    private(set) var availableCalendars: [CalendarInfo] = []

    /// Upcoming events within the look-ahead window.
    private(set) var upcomingEvents: [CalendarEvent] = []

    /// Whether a refresh is in progress.
    private(set) var isRefreshing: Bool = false

    /// Error message from the last failed operation.
    private(set) var lastError: String?

    // MARK: - Private State

    private var notificationObserver: (any NSObjectProtocol)?
    private var refreshTask: Task<Void, Never>?

    // MARK: - Initialization

    init(settings: BrowserSettings) {
        self.settings = settings
        self.eventStore = EKEventStore()

        // Check current authorization status
        let status = EKEventStore.authorizationStatus(for: .event)
        self.authorizationStatus = CalendarAuthorizationStatus(from: status)

        // If already authorized, load calendars and events
        if authorizationStatus == .authorized {
            loadCalendars()
            scheduleRefresh()
        }

        // Observe calendar store changes
        setupNotificationObserver()

        Logger.info("CalendarManager initialized", category: Logger.calendar)
    }

    isolated deinit {
        refreshTask?.cancel()
        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
        }
    }

    // MARK: - Authorization

    /// Request access to the user's calendars.
    ///
    /// - Returns: Whether access was granted.
    @discardableResult
    func requestAccess() async -> Bool {
        Logger.info("Requesting calendar access", category: Logger.calendar)

        do {
            let granted = try await eventStore.requestFullAccessToEvents()

            let status = EKEventStore.authorizationStatus(for: .event)
            authorizationStatus = CalendarAuthorizationStatus(from: status)

            if granted {
                Logger.info("Calendar access granted", category: Logger.calendar)
                loadCalendars()
                scheduleRefresh()
            } else {
                Logger.warning("Calendar access denied by user", category: Logger.calendar)
            }

            return granted
        } catch {
            Logger.error("Failed to request calendar access: \(error.localizedDescription)", category: Logger.calendar)
            authorizationStatus = .denied
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Calendar Management

    /// Load available calendars from EventKit.
    private func loadCalendars() {
        let calendars = eventStore.calendars(for: .event)

        availableCalendars = calendars.map { calendar in
            CalendarInfo(
                id: calendar.calendarIdentifier,
                title: calendar.title,
                color: calendar.cgColor,
                isSubscribed: calendar.type == .subscription,
                source: calendar.source?.title ?? "Unknown",
            )
        }.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        Logger.debug("Loaded \(availableCalendars.count) calendars", category: Logger.calendar)
    }

    /// Toggle a calendar's enabled state.
    func toggleCalendar(_ calendarID: String) {
        var ids = settings.enabledCalendarIDs
        if ids.contains(calendarID) {
            ids.remove(calendarID)
        } else {
            ids.insert(calendarID)
        }
        settings.enabledCalendarIDs = ids
        scheduleRefresh()
    }

    /// Enable all available calendars.
    func enableAllCalendars() {
        settings.enabledCalendarIDs = Set(availableCalendars.map(\.id))
        scheduleRefresh()
    }

    /// Disable all calendars.
    func disableAllCalendars() {
        settings.enabledCalendarIDs = []
        scheduleRefresh()
    }

    // MARK: - Event Fetching

    /// Refresh the list of upcoming events.
    func refresh() {
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await fetchUpcomingEvents()
        }
    }

    private func fetchUpcomingEvents() async {
        guard authorizationStatus == .authorized else {
            upcomingEvents = []
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        let enabledIDs = settings.enabledCalendarIDs

        // Get calendars: if no IDs are explicitly enabled, show all calendars (per spec)
        let allCalendars = eventStore.calendars(for: .event)
        let calendars = enabledIDs.isEmpty
            ? allCalendars
            : allCalendars.filter { enabledIDs.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else {
            upcomingEvents = []
            return
        }

        // Calculate date range
        let now = Date()
        let lookAheadHours = settings.calendarLookAheadHours
        let endDate = Calendar.current.date(byAdding: .hour, value: lookAheadHours, to: now) ?? now.addingTimeInterval(TimeInterval(lookAheadHours * 3_600))

        // Start from beginning of today for all-day events
        let startOfToday = Calendar.current.startOfDay(for: now)

        // Create predicate
        let predicate = eventStore.predicateForEvents(withStart: startOfToday, end: endDate, calendars: calendars)

        // Fetch events
        let ekEvents = eventStore.events(matching: predicate)

        // Convert to CalendarEvent and filter
        let events = ekEvents.compactMap { event -> CalendarEvent? in
            // Skip cancelled events
            guard event.status != .canceled else { return nil }

            // Skip all-day events that ended before today
            if event.isAllDay {
                let endOfYesterday = Calendar.current.date(byAdding: .day, value: -1, to: startOfToday)!
                if event.endDate <= endOfYesterday {
                    return nil
                }
            } else {
                // Skip non-all-day events that have already ended
                if event.endDate <= now {
                    return nil
                }
            }

            let meetingURL = CalendarEvent.extractMeetingURL(
                url: event.url,
                location: event.location,
                notes: event.notes,
            )

            return CalendarEvent(
                id: event.eventIdentifier,
                title: event.title ?? "Untitled Event",
                startDate: event.startDate,
                endDate: event.endDate,
                isAllDay: event.isAllDay,
                location: event.location,
                calendarColor: event.calendar.cgColor,
                calendarTitle: event.calendar.title,
                url: event.url,
                notes: event.notes,
                meetingURL: meetingURL,
            )
        }.sorted { event1, event2 in
            // Sort by: all-day first, then by start date
            if event1.isAllDay != event2.isAllDay {
                return event1.isAllDay
            }
            return event1.startDate < event2.startDate
        }

        upcomingEvents = events
        Logger.debug("Fetched \(events.count) upcoming events", category: Logger.calendar)
    }

    // MARK: - Event Actions

    /// Open an event's meeting URL or the Calendar app.
    ///
    /// If the event has a meeting URL, opens it directly. Otherwise, opens
    /// the event in the Calendar app.
    func openEvent(_ event: CalendarEvent) {
        // If there's a meeting URL, open it directly
        if let meetingURL = event.meetingURL {
            Logger.info("Opening meeting URL: \(meetingURL)", category: Logger.calendar)
            NSWorkspace.shared.open(meetingURL)
            return
        }

        // Otherwise, open in Calendar app
        openEventInCalendar(event)
    }

    /// Open an event in the Calendar app (bypassing meeting URL).
    func openEventInCalendar(_ event: CalendarEvent) {
        guard let ekEvent = eventStore.event(withIdentifier: event.id) else {
            Logger.warning("Could not find event to open: \(event.id)", category: Logger.calendar)
            return
        }

        // Open in Calendar app using calshow URL scheme
        let timestamp = ekEvent.startDate.timeIntervalSinceReferenceDate
        if let url = URL(string: "calshow:\(timestamp)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Check if there's an imminent event (within 15 minutes).
    var hasImminentEvent: Bool {
        upcomingEvents.contains { $0.startsWithin(minutes: 15) }
    }

    /// The next imminent event, if any.
    var imminentEvent: CalendarEvent? {
        upcomingEvents.first { $0.startsWithin(minutes: 15) }
    }

    // MARK: - Notification Observer

    private func setupNotificationObserver() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Logger.debug("Calendar store changed, refreshing", category: Logger.calendar)
                self.loadCalendars()
                self.scheduleRefresh()
            }
        }
    }
}
