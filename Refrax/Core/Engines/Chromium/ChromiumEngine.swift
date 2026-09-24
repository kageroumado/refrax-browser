import AppKit
import Darwin

/// The Chromium rendering engine, backed by the Chromium Embedded Framework.
///
/// Nothing Chromium-related is linked into the app. The engine lives in
/// `~/Library/Application Support/<bundle id>/Engines/Chromium/` (installed by
/// `Scripts/build-chromium-engine.sh`) and is loaded the first time a page
/// switches to it:
///
/// 1. `dlopen` the plug-in (`RefraxChromium.dylib`), which registers its
///    Objective-C classes.
/// 2. The plug-in `dlopen`s the framework and resolves every `cef_*` symbol
///    (`cef_load_library`), then moves `NSApp` into a runtime subclass that
///    adopts `CefAppProtocol`.
/// 3. `CefInitialize` runs with an external message pump driven from the main
///    run loop. Browsers can be created once `OnContextInitialized` fires; the
///    plug-in queues any created earlier.
///
/// CEF can be initialized once per process, and only after `NSApp` exists,
/// which is why the engine starts lazily rather than during app launch.
@MainActor
final class ChromiumEngine: RenderingEngine {
    static let shared = ChromiumEngine()

    private enum Constants {
        static let pluginClassName = "RFXChromiumEngineImpl"
        static let manifestName = "engine.json"
        static let profilesDirectory = "Profiles"
    }

    private struct Manifest: Decodable {
        let cefVersion: String
        let chromiumVersion: String
        let plugin: String
        let helper: String
    }

    let kind: RenderingEngineKind = .chromium

    private var runtime: (any RFXChromiumEngine)?
    private var pluginHandle: UnsafeMutableRawPointer?

    private init() {}

    /// `~/Library/Application Support/<bundle id>/Engines/Chromium`.
    var installDirectory: URL {
        let bundleID = Bundle.main.bundleIdentifier ?? "website.refrax.browser"
        return URL.applicationSupportDirectory
            .appending(path: bundleID, directoryHint: .isDirectory)
            .appending(path: "Engines/Chromium", directoryHint: .isDirectory)
    }

    private var manifest: Manifest? {
        guard let data = try? Data(contentsOf: installDirectory.appending(path: Constants.manifestName)) else {
            return nil
        }
        return try? JSONDecoder().decode(Manifest.self, from: data)
    }

    var isInstalled: Bool {
        manifest != nil
    }

    var isRunning: Bool {
        runtime?.isRunning ?? false
    }

    var versionDescription: String? {
        manifest.map { "Chromium \($0.chromiumVersion)" }
    }

    func start() throws {
        if isRunning { return }
        guard let manifest else { throw RenderingEngineError.notInstalled(.chromium) }

        let directory = installDirectory
        let runtime = try loadPlugin(at: directory.appending(path: manifest.plugin))

        let profiles = directory.appending(path: Constants.profilesDirectory, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: profiles, withIntermediateDirectories: true)

        let configuration: [RFXChromiumConfigurationKey: Any] = [
            .frameworkPath: directory.appending(path: "Chromium Embedded Framework.framework").path(percentEncoded: false),
            .helperPath: directory.appending(path: manifest.helper).path(percentEncoded: false),
            .rootCachePath: profiles.path(percentEncoded: false),
            .logPath: directory.appending(path: "chromium.log").path(percentEncoded: false),
        ]
        do {
            try runtime.start(withConfiguration: configuration)
        } catch {
            throw RenderingEngineError.failedToStart(.chromium, error.localizedDescription)
        }
        self.runtime = runtime
        Logger.info("Chromium engine started: \(runtime.version)", category: Logger.engines)
    }

    private func loadPlugin(at url: URL) throws -> any RFXChromiumEngine {
        if pluginHandle == nil {
            guard let handle = dlopen(url.path(percentEncoded: false), RTLD_NOW | RTLD_LOCAL) else {
                let reason = dlerror().map { String(cString: $0) } ?? "unknown dlopen error"
                throw RenderingEngineError.failedToLoad(.chromium, reason)
            }
            pluginHandle = handle
        }
        guard let pluginClass = NSClassFromString(Constants.pluginClassName) as? NSObject.Type,
              let runtime = pluginClass.init() as? any RFXChromiumEngine else {
            throw RenderingEngineError.failedToLoad(.chromium, "\(Constants.pluginClassName) is missing from the plug-in")
        }
        return runtime
    }

    func makeSession(url: URL?, profile: EngineProfile) throws -> any EnginePageSession {
        try start()
        guard let runtime else { throw RenderingEngineError.notInstalled(.chromium) }
        let profilePath: String? = switch profile {
        case let .persistent(identifier): identifier
        case .ephemeral: nil
        }
        return ChromiumPageSession(browser: runtime.makeBrowser(with: url, profilePath: profilePath))
    }

    func shutdown() {
        runtime?.shutdown()
    }
}

extension EngineProfile {
    /// The profile matching a space's data store, so a space's Chromium pages
    /// share storage with each other and never with another isolated space.
    init(space: Space?) {
        switch space?.dataStoreMode {
        case .separate?:
            self = .persistent(space?.id.uuidString ?? "Default")
        case .private?:
            self = .ephemeral
        default:
            self = .persistent("Default")
        }
    }
}
