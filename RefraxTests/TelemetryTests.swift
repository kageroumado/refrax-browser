import Digoxin
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
    func `Chromium counts as used within the 7-day window only`() {
        var log = UsageLog()
        #expect(!log.chromiumUsed7d(asOf: date(5), calendar: calendar))
        log.recordChromiumUse(at: date(5))
        #expect(log.chromiumUsed7d(asOf: date(5), calendar: calendar))
        #expect(log.chromiumUsed7d(asOf: date(11), calendar: calendar))
        #expect(!log.chromiumUsed7d(asOf: date(12), calendar: calendar))
    }

    @Test
    func `Chromium use late at night counts for that whole local day`() {
        var log = UsageLog()
        log.recordChromiumUse(at: date(5, hour: 0))
        #expect(log.chromiumUsed7d(asOf: date(11, hour: 23), calendar: calendar))
    }
}

@Suite("Heartbeat properties")
struct HeartbeatPropertiesTests {
    @Test
    func `The default browser matches by resolved bundle URL`() {
        let app = URL(filePath: "/Applications/Refrax.app")
        #expect(HeartbeatProperties.isDefaultBrowser(handler: URL(filePath: "/Applications/Refrax.app/"), app: app))
        #expect(!HeartbeatProperties.isDefaultBrowser(handler: URL(filePath: "/Applications/Safari.app"), app: app))
        #expect(!HeartbeatProperties.isDefaultBrowser(handler: nil, app: app))
    }

    @Test
    func `Properties use the keys on the server's allowlist`() {
        let properties = HeartbeatProperties(chromiumInstalled: true, chromiumUsed7d: false, isDefaultBrowser: true)
        #expect(properties.values == [
            "chromiumInstalled": .bool(true),
            "chromiumUsed7d": .bool(false),
            "isDefaultBrowser": .bool(true),
        ])
    }
}

@Suite("Telemetry reporter")
struct TelemetryReporterTests {
    private func engine(_ id: String, version: String) -> EngineDescriptor {
        EngineDescriptor(
            id: EngineID(rawValue: id), displayName: id, version: version, engineVersion: id, vendor: "Test",
            contractVersion: .current, capabilities: [], isOutOfProcess: true,
        )
    }

    @Test
    func `Tiers map to Digoxin's by raw value`() {
        #expect(TelemetryTier.allCases.map(ConsentTier.init) == [.off, .counting, .crashReports])
    }

    @Test
    func `The engines field lists installed engines without system WebKit`() {
        let engines = [EngineRegistry.systemWebKit, engine("website.refrax.engine.chromium", version: "155.0.8059.12-1")]
        #expect(TelemetryReporter.engines(engines) == "chromium 155.0.8059.12-1")
        #expect(TelemetryReporter.engines([EngineRegistry.systemWebKit]).isEmpty)
    }

    @Test
    func `The engines field fits the server's string limit`() {
        let engines = (0 ..< 8).map { engine("engine\($0)", version: "1.0.0-\($0)") }
        #expect(TelemetryReporter.engines(engines).count == TelemetryReporter.maxEnginesLength)
    }

    @Test(arguments: [
        (DigoxinStatus.off, TelemetryTier.off, nil as String?),
        (.deletionPending, .off, "Deleting your data\u{2026}"),
        (.secureEnclaveUnavailable, .counting, "Not sent: this Mac has no Secure Enclave"),
        (.waiting, .counting, "Waiting to send"),
        (.registered(trust: "attested"), .counting, "Counting \u{00B7} verified"),
        (.registered(trust: "unverified"), .crashReports, "Counting and crash reports"),
        (.failing(reason: "offline"), .counting, "Not sent yet; Refrax will retry"),
    ])
    func `Settings describe each status in one short line`(status: DigoxinStatus, tier: TelemetryTier, expected: String?) {
        #expect(TelemetryStatusLine.text(for: status, tier: tier) == expected)
    }
}
