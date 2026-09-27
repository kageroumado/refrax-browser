import Foundation
import Observation

/// What the engine catalog offers this copy of Refrax, and the installs it has started.
@Observable
final class EngineDistribution {
    enum CatalogState: Equatable {
        case unchecked
        case checking
        case loaded(checkedAt: Date)
        case failed(String)
    }

    enum InstallState: Equatable {
        case downloading(fraction: Double)
        case verifying
        case installing
        /// Downloaded and verified; replaces the running engine at the next launch.
        case pendingRelaunch
        case failed(String)
    }

    /// An engine the catalog offers, and how it relates to what is installed.
    struct Offer: Identifiable, Equatable {
        let id: EngineID
        let displayName: String
        let release: EngineCatalog.Release
        /// The installed release, when there is one.
        let installedVersion: String?

        var isUpdate: Bool {
            installedVersion != nil
        }
    }

    private(set) var catalogState: CatalogState = .unchecked
    private(set) var catalog: EngineCatalog?
    private(set) var installs: [EngineID: InstallState] = [:]
    /// The engines installed this session, and whether each replaced an older release.
    private(set) var completed: [Completion] = []

    struct Completion: Equatable {
        let displayName: String
        let version: String
        let isUpdate: Bool
    }

    @ObservationIgnored private unowned let registry: EngineRegistry
    @ObservationIgnored private var tasks: [EngineID: Task<Void, Never>] = [:]

    init(registry: EngineRegistry) {
        self.registry = registry
    }

    /// Engines to install, and installed engines the catalog has a newer release of.
    var offers: [Offer] {
        guard let catalog else { return [] }
        return Self.offers(in: catalog) { self.registry.descriptor(for: $0)?.version }
    }

    /// The offers `catalog` makes given the installed release of each engine. A release this
    /// Refrax or this macOS can't run is left out.
    static func offers(in catalog: EngineCatalog, installedVersion: (EngineID) -> String?) -> [Offer] {
        catalog.engines.compactMap { key, engine -> Offer? in
            let id = EngineID(rawValue: key)
            guard let release = catalog.release(for: id), canRun(release) else { return nil }
            let installed = installedVersion(id)
            if let installed {
                // A local build (dev-28) has no release version; the catalog's release replaces
                // it only when someone asks, never as an update.
                guard let installedVersion = EngineReleaseVersion(installed),
                      let offered = EngineReleaseVersion(release.version),
                      offered > installedVersion
                else { return nil }
            }
            return Offer(id: id, displayName: engine.displayName, release: release, installedVersion: installed)
        }
        .sorted { $0.displayName < $1.displayName }
    }

    /// Fetches the catalog again; failures stay in ``catalogState``.
    func checkForUpdates() async {
        guard catalogState != .checking else { return }
        catalogState = .checking
        do {
            catalog = try await EngineCatalog.fetch()
            catalogState = .loaded(checkedAt: .now)
        } catch {
            Logger.warning("Engine catalog check failed: \(error.localizedDescription)", category: Logger.engines)
            catalogState = .failed(error.localizedDescription)
        }
    }

    /// Downloads and installs `offer`. Progress and failure land in ``installs``.
    func install(_ offer: Offer) {
        guard tasks[offer.id] == nil else { return }
        let id = offer.id
        installs[id] = .downloading(fraction: 0)
        let isRunning = registry.runningEngines.contains(id)
        let enginesDirectory = registry.enginesDirectory
        tasks[id] = Task(name: "Install engine \(id)") { [weak self] in
            do {
                let outcome = try await EngineInstaller.install(
                    offer.release, engine: id, into: enginesDirectory, replacingRunningEngine: isRunning,
                    stage: { stage in
                        DispatchQueue.main.async { self?.report(stage, for: id) }
                    },
                )
                self?.finish(offer, outcome: outcome)
            } catch is CancellationError {
                self?.installs[id] = nil
                self?.tasks[id] = nil
            } catch {
                Logger.warning("Engine \(id) install failed: \(error.localizedDescription)", category: Logger.engines)
                self?.installs[id] = .failed(error.localizedDescription)
                self?.tasks[id] = nil
            }
        }
    }

    func cancelInstall(_ id: EngineID) {
        tasks[id]?.cancel()
    }

    private func report(_ stage: EngineInstaller.Stage, for id: EngineID) {
        guard tasks[id] != nil else { return }
        installs[id] = switch stage {
        case let .downloading(fraction): .downloading(fraction: fraction)
        case .verifying: .verifying
        case .installing: .installing
        }
    }

    private func finish(_ offer: Offer, outcome: EngineInstaller.Outcome) {
        let id = offer.id
        tasks[id] = nil
        switch outcome {
        case .installed:
            installs[id] = nil
            registry.refresh()
            completed.append(Completion(displayName: offer.displayName, version: offer.release.version, isUpdate: offer.isUpdate))
            Logger.info("Installed engine \(id) \(offer.release.version)", category: Logger.engines)
        case .pendingRelaunch:
            installs[id] = .pendingRelaunch
        }
    }

    static func canRun(_ release: EngineCatalog.Release) -> Bool {
        guard let contract = EngineContractVersion(string: release.contract),
              EngineContractVersion.current.accepts(contract)
        else { return false }
        let parts = release.minimumSystemVersion.split(separator: ".").compactMap { Int($0) }
        let minimum = OperatingSystemVersion(
            majorVersion: parts.first ?? 0, minorVersion: parts.count > 1 ? parts[1] : 0, patchVersion: parts.count > 2 ? parts[2] : 0,
        )
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(minimum)
    }
}
