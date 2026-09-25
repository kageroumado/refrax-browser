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
            .autoFill, .processInfo, .rendererControl,
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

    let enginesDirectory: URL
    let dataDirectory: URL

    init(applicationSupport: URL) {
        enginesDirectory = applicationSupport.appending(path: "Engines", directoryHint: .isDirectory)
        dataDirectory = applicationSupport.appending(path: "EngineData", directoryHint: .isDirectory)
        refresh()
    }

    /// Rescans the engines directory.
    func refresh() {
        let fileManager = FileManager.default
        let engineDirectories = (try? fileManager.contentsOfDirectory(at: enginesDirectory, includingPropertiesForKeys: nil)) ?? []
        var found: [EngineID: EngineBundle] = [:]
        for directory in engineDirectories {
            let candidates = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for url in candidates where url.pathExtension == "engine" {
                guard let bundle = EngineBundle(url: url), bundle.descriptor.id != .systemWebKit else { continue }
                found[bundle.descriptor.id] = bundle
            }
        }
        bundles = found
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

    /// The running host for an installed engine, started on first use.
    func host(for id: EngineID) async throws -> ExternalEngineHost {
        if let host = hosts[id] {
            try await host.start()
            return host
        }
        guard let bundle = bundles[id] else { throw EngineError.notInstalled(id) }
        let configuration = EngineConfiguration(
            storageDirectory: dataDirectory.appending(path: id.rawValue, directoryHint: .isDirectory),
            logFile: dataDirectory.appending(path: "\(id.rawValue).log"),
            languages: Locale.preferredLanguages,
        )
        let host = ExternalEngineHost(bundle: bundle, configuration: configuration)
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
