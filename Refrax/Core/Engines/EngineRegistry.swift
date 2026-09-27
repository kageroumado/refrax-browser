import AppKit
import Observation

/// Installed engines and their running hosts.
///
/// System WebKit is always present. Other engines are bundles under
/// `~/Library/Application Support/<bundle id>/Engines/<engine id>/*.engine`,
/// discovered by reading their Info.plist only; an engine's code loads the
/// first time a page asks for it.
@Observable
final class EngineRegistry {
    static let systemWebKit = EngineDescriptor(
        id: .systemWebKit,
        displayName: "WebKit",
        version: ProcessInfo.processInfo.operatingSystemVersionString,
        engineVersion: "System WebKit",
        vendor: "Apple",
        contractVersion: .current,
        capabilities: [
            .javaScriptEvaluation, .findInPage, .zoom, .snapshots, .devTools, .downloads, .contentBlocking,
            .userScripts, .webExtensions, .pictureInPicture, .mediaCapture, .readerMode, .agentPerception,
            .autoFill, .processInfo, .rendererControl, .notifications,
        ],
        isOutOfProcess: false,
    )

    /// Every usable engine, system WebKit first.
    private(set) var descriptors: [EngineDescriptor] = [EngineRegistry.systemWebKit]

    /// Engines whose code is loaded and running in this session.
    private(set) var runningEngines: Set<EngineID> = [.systemWebKit]

    @ObservationIgnored private var bundles: [EngineID: EngineBundle] = [:]
    /// The latest policy per category, replayed to each engine as it starts.
    @ObservationIgnored private var policy: [PolicyUpdate.Category: PolicyUpdate] = [:]
    @ObservationIgnored private var hosts: [EngineID: ExternalEngineHost] = [:]
    @ObservationIgnored private var icons: [EngineID: NSImage] = [:]
    /// Each installed bundle's code-signature check, run once off the main thread: a strict
    /// check hashes every file in the bundle, hundreds of megabytes for Chromium.
    @ObservationIgnored private var signatureChecks: [EngineBundle: Task<Void, any Error>] = [:]

    /// Receives every running engine's events that belong to no page.
    @ObservationIgnored var engineEventHandler: ((EngineID, EngineEvent) -> Void)?

    let enginesDirectory: URL
    let dataDirectory: URL

    /// Each engine's security floor, from the last verified engine catalog.
    private(set) var securityFloors: [EngineID: EngineReleaseVersion] = [:]

    /// Where the last verified engine catalog is kept, hidden from the engine scan.
    var catalogCacheDirectory: URL {
        enginesDirectory.appending(path: ".catalog", directoryHint: .isDirectory)
    }

    init(applicationSupport: URL) {
        enginesDirectory = applicationSupport.appending(path: "Engines", directoryHint: .isDirectory)
        dataDirectory = applicationSupport.appending(path: "EngineData", directoryHint: .isDirectory)
        refresh()
        if let catalog = EngineCatalog.cached(in: catalogCacheDirectory) {
            securityFloors = catalog.securityFloors
        }
    }

    func updateSecurityFloors(from catalog: EngineCatalog) {
        securityFloors = catalog.securityFloors
    }

    /// The floor an installed engine's release is below, if it is. A local build (dev-28)
    /// carries no release version and is never held to one.
    func securityFloor(blocking id: EngineID) -> EngineReleaseVersion? {
        guard let floor = securityFloors[id],
              let installed = descriptor(for: id).flatMap({ EngineReleaseVersion($0.version) }),
              installed < floor
        else { return nil }
        return floor
    }

    /// Downloads and installs engines from the engine catalog.
    @ObservationIgnored private(set) lazy var distribution = EngineDistribution(registry: self)

    /// Rescans the engines directory, first installing any engine downloaded while its
    /// predecessor ran.
    func refresh() {
        EngineInstaller.applyPending(in: enginesDirectory, skipping: runningEngines)
        let fileManager = FileManager.default
        let engineDirectories = (try? fileManager.contentsOfDirectory(at: enginesDirectory, includingPropertiesForKeys: nil)) ?? []
        var found: [EngineID: EngineBundle] = [:]
        for directory in engineDirectories where !directory.lastPathComponent.hasPrefix(".") {
            let candidates = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for url in candidates where url.pathExtension == "engine" {
                guard let bundle = EngineBundle(url: url), bundle.descriptor.id != .systemWebKit else { continue }
                found[bundle.descriptor.id] = bundle
            }
        }
        bundles = found
        // A bundle installed in place of another may carry the same version, so every check
        // runs again on the bundles now on disk.
        signatureChecks.removeAll()
        descriptors = [Self.systemWebKit] + found.values.map(\.descriptor).sorted { $0.displayName < $1.displayName }
    }

    func descriptor(for id: EngineID) -> EngineDescriptor? {
        descriptors.first { $0.id == id }
    }

    /// Resolves a user-typed name ("chromium", "webkit") or an exact engine ID.
    func resolve(_ name: String) -> EngineID? {
        let needle = name.lowercased()
        return descriptors.first { $0.id.rawValue.lowercased() == needle }?.id
            ?? descriptors.first { $0.displayName.lowercased() == needle }?.id
    }

    /// Checks every installed engine's code signature at background priority, so an engine's
    /// first page doesn't wait on it. Called once Refrax has finished launching.
    func verifyInstalledEngines() {
        for bundle in bundles.values {
            _ = signatureCheck(for: bundle, priority: .background)
        }
    }

    /// The signature check of `bundle`, started at `priority` unless already under way. Awaiting
    /// it from higher-priority work raises its priority.
    private func signatureCheck(for bundle: EngineBundle, priority: TaskPriority) -> Task<Void, any Error> {
        if let check = signatureChecks[bundle] {
            return check
        }
        let check = Task.detached(name: "Verify \(bundle.descriptor.displayName) signature", priority: priority) {
            try bundle.verifySignature()
        }
        signatureChecks[bundle] = check
        return check
    }

    /// The running host for an installed engine, started on first use.
    func host(for id: EngineID) async throws -> ExternalEngineHost {
        if let host = hosts[id] {
            try await host.start()
            return host
        }
        guard let bundle = bundles[id] else { throw EngineError.notInstalled(id) }
        if let floor = securityFloor(blocking: id) {
            throw EngineError.belowSecurityFloor(engine: bundle.descriptor.displayName, floor: floor.description)
        }
        try await signatureCheck(for: bundle, priority: .userInitiated).value
        if let host = hosts[id] {
            try await host.start()
            return host
        }
        let configuration = EngineConfiguration(
            storageDirectory: dataDirectory.appending(path: id.rawValue, directoryHint: .isDirectory),
            logFile: dataDirectory.appending(path: "\(id.rawValue).log"),
            languages: Locale.preferredLanguages,
        )
        let host = ExternalEngineHost(bundle: bundle, configuration: configuration)
        host.engineEventHandler = { [weak self] event in
            self?.engineEventHandler?(id, event)
        }
        hosts[id] = host
        do {
            try await host.start()
        } catch {
            hosts[id] = nil
            throw error
        }
        runningEngines.insert(id)
        for update in policy.values {
            host.apply(update)
        }
        return host
    }

    /// Sends policy to every running engine now and every engine that starts later.
    func apply(_ update: PolicyUpdate) {
        policy[update.category] = update
        for host in hosts.values {
            host.apply(update)
        }
    }

    /// Sends a command to a running engine; an engine that isn't running has nothing to act on.
    func perform(_ command: EngineCommand, on id: EngineID) {
        hosts[id]?.perform(command)
    }

    /// Where an installed engine's bundle lives.
    func bundleURL(for id: EngineID) -> URL? {
        bundles[id]?.url
    }

    /// An installed engine's icon (its bundle's `CFBundleIconFile`), read without loading the
    /// engine's code; nil for system WebKit and for engines without one.
    func icon(for id: EngineID) -> NSImage? {
        if let cached = icons[id] { return cached }
        guard let url = bundles[id]?.url,
              let bundle = Bundle(url: url),
              let name = bundle.infoDictionary?["CFBundleIconFile"] as? String,
              let image = bundle.image(forResource: name)
        else { return nil }
        icons[id] = image
        return image
    }

    /// Moves an installed engine to the Trash, and with `removingData`, everything it stored.
    ///
    /// An engine loaded in this session can't be unloaded, so removing it waits for a relaunch.
    func uninstall(_ id: EngineID, removingData: Bool) throws {
        guard let bundle = bundles[id] else { throw EngineError.notInstalled(id) }
        guard !runningEngines.contains(id) else { throw EngineError.inUse(id) }
        let fileManager = FileManager.default
        try fileManager.trashItem(at: bundle.url.deletingLastPathComponent(), resultingItemURL: nil)
        if removingData {
            let data = dataDirectory.appending(path: id.rawValue, directoryHint: .isDirectory)
            if fileManager.fileExists(atPath: data.path(percentEncoded: false)) {
                try fileManager.trashItem(at: data, resultingItemURL: nil)
            }
            // They only unlock the data just trashed.
            EngineSecrets.removeSecrets(for: id)
        }
        Logger.info("Removed engine \(id)\(removingData ? " and its data" : "")", category: Logger.engines)
        refresh()
    }

    /// Stops every running engine. Called once, at quit.
    func shutdown() {
        for host in hosts.values {
            host.shutdown()
        }
        hosts.removeAll()
        runningEngines = [.systemWebKit]
    }
}
