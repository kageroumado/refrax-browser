import Foundation
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

    @ObservationIgnored private var bundles: [EngineID: EngineBundle] = [:]
    @ObservationIgnored private var hosts: [EngineID: ExternalEngineHost] = [:]

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
        return host
    }

    /// Stops every running engine. Called once, at quit.
    func shutdown() {
        for host in hosts.values {
            host.shutdown()
        }
        hosts.removeAll()
    }
}
