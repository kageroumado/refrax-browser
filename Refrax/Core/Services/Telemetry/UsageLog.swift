import Foundation

/// The days Refrax was used and when the Chromium engine last rendered a page.
///
/// Kept on this Mac only. The daily check-in sends counts derived from it
/// (``activeDays7(asOf:calendar:)``, ``chromiumUsed7d(asOf:calendar:)``),
/// never the dates themselves.
nonisolated struct UsageLog: Codable, Equatable, Sendable {
    /// Days kept: the 7-day window plus one, so a check-in sent just after
    /// midnight still sees the whole previous week.
    static let retainedDays = 8

    /// The days in the window the check-in reports on, today included.
    static let windowDays = 7

    /// Local calendar days with use, as `yyyy-MM-dd`, oldest first.
    private(set) var activeDays: [String] = []

    /// When a Chromium-engine page was last used.
    private(set) var chromiumLastUsed: Date?

    /// Records use on `date`'s local day and drops days older than ``retainedDays``.
    ///
    /// - Returns: Whether the log changed, so callers persist only when needed.
    @discardableResult
    mutating func recordUse(at date: Date, calendar: Calendar = .current) -> Bool {
        let key = Self.dayKey(for: date, calendar: calendar)
        guard !activeDays.contains(key) else { return false }
        activeDays.append(key)
        activeDays.sort()
        let earliestKept = Self.dayKey(for: Self.day(offset: -(Self.retainedDays - 1), from: date, calendar: calendar), calendar: calendar)
        activeDays.removeAll { $0 < earliestKept }
        return true
    }

    /// Records that a Chromium-engine page was used at `date`.
    mutating func recordChromiumUse(at date: Date) {
        chromiumLastUsed = date
    }

    /// How many of the 7 local days ending on `date` had use.
    func activeDays7(asOf date: Date, calendar: Calendar = .current) -> Int {
        let window = Self.windowKeys(endingOn: date, calendar: calendar)
        return activeDays.count { window.contains($0) }
    }

    /// Whether a Chromium-engine page was used in the 7 local days ending on `date`.
    func chromiumUsed7d(asOf date: Date, calendar: Calendar = .current) -> Bool {
        guard let chromiumLastUsed, chromiumLastUsed <= date else { return false }
        return Self.windowKeys(endingOn: date, calendar: calendar)
            .contains(Self.dayKey(for: chromiumLastUsed, calendar: calendar))
    }

    // MARK: - Days

    private static func windowKeys(endingOn date: Date, calendar: Calendar) -> Set<String> {
        Set((0 ..< windowDays).map { dayKey(for: day(offset: -$0, from: date, calendar: calendar), calendar: calendar) })
    }

    private static func day(offset: Int, from date: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date)) ?? date
    }

    static func dayKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

/// Persists the ``UsageLog`` in user defaults and records use while telemetry is on.
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

    /// Records use today, when the tier shares counts.
    static func recordUse(tier: TelemetryTier, defaults: UserDefaults = .standard) {
        guard tier.sendsCounting else { return }
        var log = load(from: defaults)
        if log.recordUse(at: Date()) {
            save(log, to: defaults)
        }
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
