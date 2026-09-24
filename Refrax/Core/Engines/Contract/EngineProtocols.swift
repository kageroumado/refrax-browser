import AppKit

// MARK: - Policy

/// Browser-wide configuration Refrax pushes into every engine.
///
/// Refrax is the source of truth for all of it. Engines apply updates to every
/// page, existing and future, and never persist or fetch these on their own.
nonisolated enum PolicyUpdate: Codable, Hashable, Sendable {
    case contentBlocking(policy: ContentBlockingPolicy)
    case scripts(scripts: [InjectedScript])
    case extensions(extensions: [ExtensionPackage])
    case siteSettings(rules: [SiteSettingsRule])
}

nonisolated extension PolicyUpdate {
    /// Which part of the engine's configuration an update replaces.
    enum Category: Hashable, Sendable {
        case contentBlocking
        case scripts
        case extensions
        case siteSettings
    }

    var category: Category {
        switch self {
        case .contentBlocking: .contentBlocking
        case .scripts: .scripts
        case .extensions: .extensions
        case .siteSettings: .siteSettings
        }
    }
}

nonisolated struct ContentBlockingPolicy: Codable, Hashable, Sendable {
    nonisolated struct FilterList: Codable, Hashable, Sendable {
        /// Stable identifier, e.g. "easylist".
        let id: String
        /// Adblock Plus / uBlock syntax, as downloaded.
        let contents: String
    }

    var isEnabled = true
    var lists: [FilterList] = []
    /// Hosts where blocking is off (per-site bypass).
    var allowlistedHosts: [String] = []
}

nonisolated struct InjectedScript: Codable, Hashable, Sendable {
    nonisolated enum InjectionTime: String, Codable, Hashable, Sendable {
        case documentStart
        case documentEnd
    }

    /// Stable identifier, e.g. "refrax.gpc" or "userscript.<namespace>.<name>".
    let id: String
    let source: String
    let injectionTime: InjectionTime
    let world: ScriptRequest.World
    let mainFrameOnly: Bool
    /// Match patterns (`*://*.example.com/*`); empty means every page.
    let matches: [String]
    let excludes: [String]
    /// Names of message channels this script may post to (see ``EnginePage/messages``).
    let channels: [String]
}

nonisolated extension InjectedScript {
    /// The same script, allowed to post to `channels`.
    func granting(_ channels: [String]) -> InjectedScript {
        InjectedScript(
            id: id, source: source, injectionTime: injectionTime, world: world, mainFrameOnly: mainFrameOnly,
            matches: matches, excludes: excludes, channels: channels,
        )
    }
}

nonisolated struct ExtensionPackage: Codable, Hashable, Sendable {
    let id: String
    /// Unpacked extension directory. Read-only for the engine.
    let directory: URL
    let grantedPermissions: [String]
    let grantedHostPatterns: [String]
    let isEnabled: Bool
}

nonisolated struct SiteSettingsRule: Codable, Hashable, Sendable {
    let host: String
    var javaScriptEnabled: Bool?
    var zoom: Double?
    var userAgent: String?
    var contentBlockingEnabled: Bool?
}

// MARK: - Script Messages

/// A message a Refrax-injected script posted on a named channel.
///
/// Arrives from untrusted page context: handlers validate `body` like any
/// other external input.
nonisolated struct ScriptMessage: Codable, Hashable, Sendable {
    let channel: String
    let body: ScriptValue
    let frameURL: URL?
    let isMainFrame: Bool
}

/// What a script's `postMessage` promise settles with.
nonisolated enum ScriptReply: Codable, Hashable, Sendable {
    /// Resolves the promise with `value`.
    case value(value: ScriptValue)
    /// Rejects the promise with an `Error` carrying `message`.
    case error(message: String)
}

/// A script message plus the one-shot reply its `postMessage` promise waits on.
nonisolated struct ScriptMessageDelivery: Sendable {
    let message: ScriptMessage
    let reply: @Sendable (ScriptReply) -> Void
}

// MARK: - Host

nonisolated enum HostEvent: Hashable, Sendable {
    /// The engine process exited or stopped answering; every page it hosted is gone.
    case terminated(reason: String)
    /// The engine asks to be restarted (e.g. an update was installed).
    case restartRequested
}

nonisolated struct EngineProcessInfo: Hashable, Sendable {
    nonisolated enum Kind: String, Hashable, Sendable {
        case browser
        case renderer
        case gpu
        case network
        case utility
    }

    let pid: pid_t
    let kind: Kind
    let physicalFootprint: UInt64
    let cpuTime: Duration
    let pageIDs: [EnginePageID]
}

/// A rendering engine runtime. One instance per installed engine.
@MainActor
protocol EngineHost: AnyObject {
    var descriptor: EngineDescriptor { get }
    var events: AsyncStream<HostEvent> { get }

    /// Loads and starts the engine. Idempotent.
    func start() async throws

    func makePage(_ spec: EnginePageSpec) throws -> any EnginePage

    func apply(_ update: PolicyUpdate)

    /// Deletes everything the engine stored for a profile (space deleted, data cleared).
    func removeProfile(_ profile: EngineProfileSpec) async

    func processInfo() async -> [EngineProcessInfo]

    /// Closes every page and stops the engine. Synchronous so it completes during app termination.
    func shutdown()
}

/// One browsing context in an engine.
@MainActor
protocol EnginePage: AnyObject {
    var id: EnginePageID { get }
    var engine: EngineDescriptor { get }

    /// Facts about the page, in order. Finishes when the page closes.
    var events: AsyncStream<PageEvent> { get }
    /// Decisions the engine is waiting on.
    var requests: AsyncStream<PageRequest> { get }
    /// Messages from Refrax-injected scripts (``InjectedScript/channels``). Each is replied to once.
    var messages: AsyncStream<ScriptMessageDelivery> { get }

    /// The view that displays the page. Owned by the page; hosts re-parent it.
    var view: NSView { get }

    func perform(_ command: PageCommand)
    func evaluate(_ request: ScriptRequest) async throws -> ScriptValue
    func snapshot(of rect: CGRect?) async throws -> CGImage

    /// Tears the page down. Its streams finish.
    func close()
}
