import Foundation
import Testing
@testable import Refrax

@Suite("Telemetry tier")
struct TelemetryTierTests {
    @Test
    func `Raw values match Digoxin's consent tiers`() {
        #expect(TelemetryTier.allCases.map(\.rawValue) == ["off", "counting", "crashReports"])
    }

    @Test
    func `A finished onboarding without a chosen tier asks once`() {
        #expect(TelemetryTier.needsPrompt(hasCompletedOnboarding: true, chosenTier: nil))
    }

    @Test(arguments: [
        (false, nil as String?),
        (false, "crashReports"),
        (true, "off"),
        (true, "counting"),
    ])
    func `A chosen tier or onboarding in progress never asks`(completed: Bool, chosen: String?) {
        #expect(!TelemetryTier.needsPrompt(hasCompletedOnboarding: completed, chosenTier: chosen))
    }

    @Test
    func `Each tier gates what it sends`() {
        #expect(!TelemetryTier.off.sendsCounting)
        #expect(!TelemetryTier.off.sendsCrashReports)
        #expect(TelemetryTier.counting.sendsCounting)
        #expect(!TelemetryTier.counting.sendsCrashReports)
        #expect(TelemetryTier.crashReports.sendsCounting)
        #expect(TelemetryTier.crashReports.sendsCrashReports)
    }
}

@Suite("Usage log")
struct UsageLogTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    private func date(_ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2_026, month: 10, day: day, hour: hour))!
    }

    @Test
    func `Several uses on one day count once`() {
        var log = UsageLog()
        let first = log.recordUse(at: date(5, hour: 9), calendar: calendar)
        let second = log.recordUse(at: date(5, hour: 23), calendar: calendar)
        #expect(first)
        #expect(!second)
        #expect(log.activeDays7(asOf: date(5), calendar: calendar) == 1)
    }

    @Test
    func `The window covers today and the six days before it`() {
        var log = UsageLog()
        for day in [1, 3, 4, 7] {
            log.recordUse(at: date(day), calendar: calendar)
        }
        #expect(log.activeDays7(asOf: date(7), calendar: calendar) == 4)
        #expect(log.activeDays7(asOf: date(8), calendar: calendar) == 3)
        #expect(log.activeDays7(asOf: date(10), calendar: calendar) == 2)
        #expect(log.activeDays7(asOf: date(11), calendar: calendar) == 1)
    }

    @Test
    func `Days older than the retained span are dropped`() {
        var log = UsageLog()
        for day in 1 ... 20 {
            log.recordUse(at: date(day), calendar: calendar)
        }
        #expect(log.activeDays.count == UsageLog.retainedDays)
        #expect(log.activeDays.first == "2026-10-13")
        #expect(log.activeDays.last == "2026-10-20")
    }

    @Test
    func `Use just before and after midnight lands on two days`() {
        var log = UsageLog()
        log.recordUse(at: date(5, hour: 23), calendar: calendar)
        log.recordUse(at: date(6, hour: 0), calendar: calendar)
        #expect(log.activeDays == ["2026-10-05", "2026-10-06"])
    }

    @Test
    func `Chromium counts as used within the 7-day window only`() {
        var log = UsageLog()
        #expect(!log.chromiumUsed7d(asOf: date(5), calendar: calendar))
        log.recordChromiumUse(at: date(5))
        #expect(log.chromiumUsed7d(asOf: date(5), calendar: calendar))
        #expect(log.chromiumUsed7d(asOf: date(11), calendar: calendar))
        #expect(!log.chromiumUsed7d(asOf: date(12), calendar: calendar))
    }

    @Test
    func `The default browser matches by resolved bundle URL`() {
        let app = URL(filePath: "/Applications/Refrax.app")
        #expect(HeartbeatProperties.isDefaultBrowser(handler: URL(filePath: "/Applications/Refrax.app/"), app: app))
        #expect(!HeartbeatProperties.isDefaultBrowser(handler: URL(filePath: "/Applications/Safari.app"), app: app))
        #expect(!HeartbeatProperties.isDefaultBrowser(handler: nil, app: app))
    }
}

@Suite("Crash context")
struct CrashContextTests {
    @Test(arguments: [
        ("/Applications/Refrax.app", CrashContext.InstallLocation.applications),
        ("/Users/someone/Applications/Refrax.app", .applications),
        ("/private/var/folders/x1/abc/T/AppTranslocation/1234-ABCD/d/Refrax.app", .translocated),
        ("/Users/someone/Downloads/Refrax.app", .other),
        ("/Applications Extra/Refrax.app", .other),
    ])
    func `Install location is classified from the bundle path`(path: String, expected: CrashContext.InstallLocation) {
        #expect(CrashContext.InstallLocation(bundlePath: path, homeDirectory: "/Users/someone") == expected)
    }

    @Test
    func `Seconds since launch come from the crash log's launch and capture times`() {
        let ips = """
        {"app_name":"Refrax","timestamp":"2026-10-05 00:10:46.00 +0200"}
        {
          "captureTime" : "2026-10-05 00:10:46.1200 +0200",
          "procLaunch" : "2026-10-05 00:08:31.0000 +0200"
        }
        """
        #expect(CrashContext.secondsSinceLaunch(ips: Data(ips.utf8)) == 135)
    }

    @Test
    func `A crash log without times yields no duration`() {
        #expect(CrashContext.secondsSinceLaunch(ips: Data("{}\n{}".utf8)) == nil)
        #expect(CrashContext.secondsSinceLaunch(ips: Data("not a crash log".utf8)) == nil)
    }

    @Test
    func `The previous version changes only when the running version does`() throws {
        let suite = "refrax-launch-history-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        LaunchHistory.recordLaunch(version: "1.0", defaults: defaults)
        #expect(LaunchHistory.previousVersion(defaults: defaults) == nil)
        LaunchHistory.recordLaunch(version: "1.0", defaults: defaults)
        #expect(LaunchHistory.previousVersion(defaults: defaults) == nil)
        LaunchHistory.recordLaunch(version: "1.1", defaults: defaults)
        #expect(LaunchHistory.previousVersion(defaults: defaults) == "1.0")
        LaunchHistory.recordLaunch(version: "1.1", defaults: defaults)
        #expect(LaunchHistory.previousVersion(defaults: defaults) == "1.0")
    }
}
