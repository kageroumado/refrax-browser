import Foundation

/// When the Chromium engine last rendered a page.
///
/// Kept on this Mac only. The daily check-in sends whether that falls in the
/// last week (``chromiumUsed7d(asOf:calendar:)``), never the date itself.
nonisolated struct UsageLog: Codable, Equatable, Sendable {
    /// The days in the window the check-in reports on, today included.
    static let windowDays = 7

    /// When a Chromium-engine page was last used.
    private(set) var chromiumLastUsed: Date?

    /// Records that a Chromium-engine page was used at `date`.
    mutating func recordChromiumUse(at date: Date) {
        chromiumLastUsed = date
    }

    /// Whether a Chromium-engine page was used in the 7 local days ending on `date`.
    func chromiumUsed7d(asOf date: Date, calendar: Calendar = .current) -> Bool {
        guard let chromiumLastUsed, chromiumLastUsed <= date,
              let windowStart = calendar.date(byAdding: .day, value: -(Self.windowDays - 1), to: calendar.startOfDay(for: date))
        else {
            return false
        }
        return chromiumLastUsed >= windowStart
    }
}

/// Persists the ``UsageLog`` in user defaults while telemetry is on.
nonisolated enum UsageLogStore {
    private static let key = "telemetryUsageLog"

    /// The stored log, empty when none was recorded.
    static func load(from defaults: UserDefaults = .standard) -> UsageLog {
        guard let data = defaults.data(forKey: key),
              let log = try? JSONDecoder().decode(UsageLog.self, from: data)
        else {
            return UsageLog()
        }
        return log
    }

    /// Records a Chromium-engine page being used, when the tier shares counts.
    static func recordChromiumUse(tier: TelemetryTier, defaults: UserDefaults = .standard) {
        guard tier.sendsCounting else { return }
        var log = load(from: defaults)
        log.recordChromiumUse(at: Date())
        save(log, to: defaults)
    }

    /// Forgets all recorded use; called when telemetry is turned off.
    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key)
    }

    private static func save(_ log: UsageLog, to defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(log) {
            defaults.set(data, forKey: key)
        }
    }
}
