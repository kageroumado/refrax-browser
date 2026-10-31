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
    case siteSettings(policy: SiteSettingsPolicy)
    case notifications(policy: NotificationPolicy)
}

nonisolated extension PolicyUpdate {
    /// Which part of the engine's configuration an update replaces.
    enum Category: Hashable, Sendable {
        case contentBlocking
        case scripts
        case extensions
        case siteSettings
        case notifications
    }

    var category: Category {
        switch self {
        case .contentBlocking: .contentBlocking
        case .scripts: .scripts
        case .extensions: .extensions
        case .siteSettings: .siteSettings
        case .notifications: .notifications
        }
    }
}

/// Content blocking as one compiled Shields engine (`Engines/CONTRACT.md` §4.5).
///
/// Refrax parses every filter list; engines load the serialized engine (a DAT) it names and
/// match with the same adblock-rust build, so both engines decide alike.
nonisolated struct ContentBlockingPolicy: Codable, Hashable, Sendable {
    nonisolated enum Mode: String, Codable, Hashable, Sendable {
        /// Every network filter applies, first-party requests included, as WebKit's rule lists
        /// apply them, so a page is filtered alike in both engines.
        case standard
    }

    /// A file Refrax wrote and will not rewrite while a policy names it.
    nonisolated struct Artifact: Codable, Hashable, Sendable {
        /// A `file:` URL.
        let path: URL
        /// Lowercase hex SHA-256 of the file; a new value means a new file.
        let sha256: String
    }

    nonisolated struct Engine: Codable, Hashable, Sendable {
        let path: URL
        let sha256: String
        /// The writer's `shields_engine_format()`; an engine refuses a DAT in another format.
        let format: String
    }

    /// One filter list in the engine, so a log entry can name the list a rule came from.
    nonisolated struct FilterList: Codable, Hashable, Sendable {
        /// Stable identifier, e.g. "easylist".
        let id: String
        /// The list's `rule_source_index` in the engine.
        let sourceIndex: Int
    }

    var isEnabled = true
    var mode = Mode.standard
    /// Required while enabled.
    var engine: Engine?
    /// Redirect and scriptlet resources; without them `$redirect` and `+js()` do nothing.
    var resources: Artifact?
    var lists: [FilterList] = []
    /// Hosts where blocking is off (per-site bypass); each covers its subdomains.
    var allowlistedHosts: [String] = []
}

/// One request an engine decided, for the request logger (`refrax-ctl page requests`).
nonisolated struct RequestLogEntry: Codable, Hashable, Sendable {
    nonisolated enum Decision: String, Codable, Hashable, Sendable {
        case blocked
        /// Answered with a redirect resource in place of the load.
        case redirected
        /// Loaded from a rewritten URL (`$removeparam`).
        case rewritten
        case allowed
        /// A blocking filter matched and an exception lifted it.
        case excepted
        /// A `$csp` filter added a Content-Security-Policy.
        case csp
    }

    nonisolated enum Exactness: String, Codable, Hashable, Sendable {
        /// The engine reported the decision as it made it.
        case exact
        /// The engine reported only that it acted; Refrax re-ran the URL through its own
        /// engine to name the rule, guessing the request type from the URL.
        case attributed
    }

    /// Increases by one per entry within a page.
    let seq: Int64
    let time: Date
    let frameURL: URL?
    let url: URL
    /// adblock-rust's request type name (`script`, `image`, `xmlhttprequest`, …).
    let type: String
    let method: String
    let decision: Decision
    /// The deciding filter as written, when known.
    var rule: String?
    /// The id of the list `rule` came from.
    var list: String?
    /// `rule`'s zero-based line in that list.
    var line: Int?
    var exceptionRule: String?
    /// The URL loaded instead, for `rewritten`.
    var rewrittenURL: URL?
    /// The policy added, for `csp`.
    var csp: String?
    /// Standard mode let a first-party request through that a filter matched (`allowed`).
    var sparedFirstParty: Bool?
    let exactness: Exactness
}

/// A page's request log entries after a sequence number, oldest first.
nonisolated struct RequestLog: Codable, Hashable, Sendable {
    let entries: [RequestLogEntry]
    /// The sequence number to ask from next time.
    let nextSequence: Int64
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

/// Refrax's per-site settings an engine enforces itself. Zoom is set per page (`setZoom`),
/// permissions are answered per request, and popups arrive as `openURL` requests, so none of
/// them are here.
nonisolated struct SiteSettingsPolicy: Codable, Hashable, Sendable {
    /// Whether pages run JavaScript where no rule says otherwise.
    var javaScriptEnabled = true
    var rules: [SiteSettingsRule] = []
}

/// Overrides for one site. `host` is a registrable domain and covers its subdomains; an absent
/// field leaves the default.
nonisolated struct SiteSettingsRule: Codable, Hashable, Sendable {
    let host: String
    var javaScriptEnabled: Bool?
    var contentBlockingEnabled: Bool?
    /// Media may play with sound before the user interacts with the page.
    var autoplayWithSound: Bool?

    var hasOverrides: Bool {
        javaScriptEnabled != nil || contentBlockingEnabled != nil || autoplayWithSound != nil
    }
}

/// Every notification decision Refrax holds. Engines answer notification permission from it
/// alone and store no decision of their own.
nonisolated struct NotificationPolicy: Codable, Hashable, Sendable {
    /// Serialized origins (`scheme://host[:port]`).
    var granted: [String] = []
    var denied: [String] = []
    /// Whether an origin in neither list may ask; otherwise it is denied.
    var asksByDefault = true
}

// MARK: - Script Messages

/// A message a Refrax-injected script posted on a named channel.
///
/// Arrives from untrusted page context: handlers validate `body` like any
/// other external input.
nonisolated struct ScriptMessage: Codable, Hashable, Sendable {
    let channel: String
    /// The world of the script that posted. Engines report it; the page can't choose it.
    let world: ScriptRequest.World
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

/// Something that happened in an engine outside any page (`Engines/CONTRACT.md` §4.6).
nonisolated enum EngineEvent: Codable, Hashable, Sendable {
    /// A service worker showed a notification, or a page did and the engine can't name the page.
    case notificationShown(profile: EngineProfileSpec, notification: EngineNotification)
    /// The worker or page closed a notification it showed.
    case notificationClosed(id: String)
    /// Sent once per `contentBlocking` policy: the engine loaded the DAT with this `sha256`
    /// (`applied`), or filters nothing (`unfiltered`, with the reason).
    case contentBlockingStatus(status: ContentBlockingStatus, sha256: String?, reason: String?)
}

nonisolated enum ContentBlockingStatus: String, Codable, Hashable, Sendable {
    case applied
    case unfiltered
}

/// A command for an engine that concerns no one page.
nonisolated enum EngineCommand: Codable, Hashable, Sendable {
    /// The user clicked the notification; the engine fires its `notificationclick` or `click` event.
    case notificationClicked(id: String)
    /// The user dismissed the notification; the engine fires its `notificationclose` or `close` event.
    case notificationClosed(id: String)
}

/// A question an engine asks Refrax that concerns no one page, answered once.
nonisolated enum EngineRequest: Codable, Hashable, Sendable {
    /// Key material Refrax keeps in its keychain for the engine (``EngineSecrets``).
    case secret(name: String)
}

nonisolated enum EngineRequestAnswer: Codable, Hashable, Sendable {
    /// Base64 in JSON.
    case secret(value: Data)
    /// The keychain can't be read now.
    case unavailable
}

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

    func perform(_ command: EngineCommand)

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

    /// Content-blocking decisions numbered after `sequence`, oldest first. Throws
    /// ``EngineError/unsupported(_:)`` for engines without ``EngineCapabilities/requestLog``.
    func requestLog(since sequence: Int64) async throws -> RequestLog

    /// Tears the page down. Its streams finish.
    func close()
}
