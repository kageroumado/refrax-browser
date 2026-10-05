import Digoxin
import Foundation

/// Owns Refrax's ``Digoxin`` client: applies the user's ``TelemetryTier``,
/// records use, queues crash reports, and keeps the client's status for
/// Settings to show.
///
/// The client is an actor doing file I/O, Secure Enclave signing, and network;
/// every call here hands it work with `await` and returns to the main actor.
@MainActor
@Observable
final class TelemetryReporter {
    /// The service root for this build. Debug builds talk to a local server,
    /// or to `REFRAX_DIGOXIN_URL` when set, so they never reach production.
    nonisolated static let baseURL: URL = {
        #if DEBUG
            if let override = ProcessInfo.processInfo.environment["REFRAX_DIGOXIN_URL"],
               let url = URL(string: override) {
                return url
            }
            return URL(string: "http://127.0.0.1:9130/api/digoxin")!
        #else
            return URL(string: "https://kagerou.glass/api/digoxin")!
        #endif
    }()

    /// The longest `engines` value the server's string fields accept.
    nonisolated static let maxEnginesLength = 64

    /// Where the client stands, as of the last ``refreshStatus()``.
    private(set) var status: DigoxinStatus = .off

    @ObservationIgnored private let client: Digoxin
    @ObservationIgnored private let registry: EngineRegistry
    /// Applies the tier stored in settings before anything else reaches the client.
    @ObservationIgnored private var initialTier: Task<Void, Never>?
    @ObservationIgnored private var tierChanges: Task<Void, Never>?

    init(registry: EngineRegistry) {
        self.registry = registry
        self.client = Digoxin(configuration: .init(
            app: "refrax",
            baseURL: Self.baseURL,
            storageDirectory: Directories.appStorage,
            propertiesProvider: { await HeartbeatProperties.current(registry: registry).values },
        ))
    }

    /// Applies `settings`' tier now and on every change, recording use each
    /// time so a newly chosen tier sends today's check-in at once.
    ///
    /// Choosing ``TelemetryTier/off`` makes the client sign a delete for
    /// everything this install sent, then destroy its key.
    func start(settings: BrowserSettings) {
        guard tierChanges == nil else { return }
        let client = client
        let initialTier = Task(name: "Telemetry tier at launch") {
            await client.setTier(ConsentTier(settings.telemetryTier))
        }
        self.initialTier = initialTier
        tierChanges = Task(name: "Telemetry tier changes") { [weak self] in
            await initialTier.value
            for await tier in Observations({ settings.telemetryTier }) {
                await client.setTier(ConsentTier(tier))
                await client.recordUse()
                await self?.refreshStatus()
            }
        }
    }

    /// Counts today as a day Refrax was used; sends the day's check-in on the first call.
    func recordUse() {
        Task(name: "Telemetry use") { [client, initialTier] in
            await initialTier?.value
            await client.recordUse()
            await refreshStatus()
        }
    }

    /// Queues the previous session's crash logs and sends them, when the
    /// tier includes crash reports.
    ///
    /// - Parameter files: `.ips` crash logs newest first, then the exception log.
    func submitCrashReport(files: [URL]) async {
        let context: [String: TelemetryValue] = [
            "engines": .string(Self.engines(registry.descriptors)),
            "consecutiveLaunchCrashes": .int(CrashMonitor.consecutiveLaunchCrashes),
        ]
        await initialTier?.value
        await client.submitCrashReport(files: files, context: context)
        await refreshStatus()
    }

    /// Reads the client's current status.
    func refreshStatus() async {
        status = await client.status
    }

    /// Installed engines other than system WebKit, as `name version` pairs
    /// (`chromium 155.0.8059.12-1`), cut to the server's string limit.
    nonisolated static func engines(_ descriptors: [EngineDescriptor]) -> String {
        let list = descriptors
            .filter { $0.id != .systemWebKit }
            .map { "\($0.id.rawValue.split(separator: ".").last ?? "") \($0.version)" }
            .joined(separator: ", ")
        return String(list.prefix(maxEnginesLength))
    }
}

extension ConsentTier {
    /// The Digoxin tier with the same raw value.
    nonisolated init(_ tier: TelemetryTier) {
        self = ConsentTier(rawValue: tier.rawValue) ?? .off
    }
}
