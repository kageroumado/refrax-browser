import Foundation

// MARK: - Page Events

/// Everything an engine reports about a page. The only way page state leaves an engine.
///
/// Events are facts in the order they happened; ``PageReducer`` folds them into
/// ``PageSnapshot``. Engines emit a fact once when it changes, never on a timer.
nonisolated enum PageEvent: Codable, Hashable, Sendable {
    /// A main-frame navigation began (provisional; nothing on screen changed yet).
    case navigationStarted(url: URL)
    /// The provisional main-frame navigation was redirected by the server.
    case navigationRedirected(url: URL)
    /// A main-frame navigation committed: the page now shows `url`.
    case navigationCommitted(url: URL, isBackForward: Bool)
    /// The page's visible URL changed: a navigation began showing its destination,
    /// a navigation committed, or the document changed its own URL (fragment,
    /// `history.pushState`). Distinct from ``navigationCommitted``, which marks a new document.
    case urlChanged(url: URL)
    /// The main frame finished loading. `statusCode` is nil for non-HTTP loads.
    case navigationFinished(url: URL, statusCode: Int?)
    /// A main-frame navigation failed.
    case navigationFailed(failure: NavigationFailure)
    case titleChanged(title: String)
    /// Estimated load progress, 0…1.
    case progressChanged(progress: Double)
    case loadingChanged(isLoading: Bool)
    case backForwardChanged(canGoBack: Bool, canGoForward: Bool)
    case securityChanged(security: PageSecurity)
    case faviconsChanged(urls: [URL])
    case themeColorChanged(color: RGBAColor?)
    /// Color sampled along the top edge of the page, used to tint the chrome.
    case topEdgeColorChanged(color: RGBAColor?)
    /// The link under the pointer, or nil when the pointer leaves it.
    case hoveredLinkChanged(url: URL?)
    case zoomChanged(factor: Double)
    case mediaChanged(media: PageMedia)
    case fullscreenChanged(state: PageFullscreen)
    case rendererHealthChanged(health: RendererHealth)
}

/// Why a main-frame navigation failed, in engine-neutral terms.
nonisolated struct NavigationFailure: Codable, Hashable, Sendable {
    nonisolated enum Kind: String, Codable, Hashable, Sendable {
        case cancelled
        case cannotFindHost
        case cannotConnectToHost
        case notConnectedToInternet
        case connectionLost
        case timedOut
        case certificateInvalid
        case httpError
        case blockedByPolicy
        case other
    }

    let kind: Kind
    let url: URL?
    /// Whether the failure happened before commit (the previous page is still shown).
    let isProvisional: Bool
    /// The engine's own code (`NSURLError`, `net::Error`, …), for diagnostics only.
    let engineCode: Int
    let description: String

    /// The equivalent `NSURLError` code, which the error page renders.
    var urlErrorCode: Int {
        switch kind {
        case .cancelled: NSURLErrorCancelled
        case .cannotFindHost: NSURLErrorCannotFindHost
        case .cannotConnectToHost: NSURLErrorCannotConnectToHost
        case .notConnectedToInternet: NSURLErrorNotConnectedToInternet
        case .connectionLost: NSURLErrorNetworkConnectionLost
        case .timedOut: NSURLErrorTimedOut
        case .certificateInvalid: NSURLErrorServerCertificateUntrusted
        case .httpError, .blockedByPolicy, .other: engineCode
        }
    }
}

/// Transport security of the committed page.
nonisolated enum PageSecurity: String, Codable, Hashable, Sendable {
    /// HTTPS with a trusted certificate and no insecure subresources.
    case secure
    /// HTTPS with a trusted certificate that loaded some subresources over HTTP.
    case mixedContent
    /// HTTP, or HTTPS whose certificate is not trusted.
    case insecure
    /// No transport: `about:`, `data:`, `file:`, internal pages.
    case notApplicable
}

nonisolated struct RGBAColor: Codable, Hashable, Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double
}

nonisolated struct PageMedia: Codable, Hashable, Sendable {
    nonisolated enum CaptureState: String, Codable, Hashable, Sendable {
        case none
        case active
        case muted
    }

    var isPlayingAudio = false
    var isAudioMuted = false
    var camera: CaptureState = .none
    var microphone: CaptureState = .none
    var screen: CaptureState = .none

    static let idle = PageMedia()
}

nonisolated enum PageFullscreen: String, Codable, Hashable, Sendable {
    case none
    case entering
    case active
    case exiting
}

/// Health of the process rendering a page.
nonisolated enum RendererHealth: Codable, Hashable, Sendable {
    case running
    /// The renderer stopped responding; `since` is when the engine noticed.
    case unresponsive(since: Date)
    /// The renderer is gone. The page shows its last frame until reloaded.
    case terminated(reason: RendererTerminationReason)
    /// The engine suspended the renderer to save resources (background tab).
    case suspended
}

nonisolated enum RendererTerminationReason: String, Codable, Hashable, Sendable {
    case crashed
    /// A process shared by several pages crashed too often and the engine stopped relaunching it.
    case sharedProcessCrashed
    case exceededMemoryLimit
    case exceededCPULimit
    /// Refrax or the engine asked for it (watchdog kill, memory pressure eviction).
    case requestedByBrowser
    case unknown
}

// MARK: - Page Commands

/// Everything Refrax can ask an engine to do to a page.
nonisolated enum PageCommand: Codable, Hashable, Sendable {
    case load(request: URLRequestSpec)
    case goBack
    case goForward
    case reload(fromOrigin: Bool)
    case stopLoading
    case setZoom(factor: Double)
    case setAudioMuted(muted: Bool)
    case setMediaSuspended(suspended: Bool)
    case find(query: FindQuery)
    case stopFinding
    case setVisibility(visibility: PageVisibility)
    case focus
    case devTools(command: DevToolsCommand)
    /// Watchdog: terminate the renderer; the page reports `.terminated(.requestedByBrowser)`.
    case terminateRenderer
}

nonisolated struct URLRequestSpec: Codable, Hashable, Sendable {
    let url: URL
    var headers: [String: String] = [:]
    var referrer: URL?
}

nonisolated struct FindQuery: Codable, Hashable, Sendable {
    let text: String
    var forward = true
    var matchCase = false
    /// Continue from the current match rather than starting over.
    var findNext = false
}

nonisolated enum PageVisibility: String, Codable, Hashable, Sendable {
    case visible
    /// Off screen but alive: timers throttled, rendering paused.
    case hidden
}

nonisolated enum DevToolsCommand: Codable, Hashable, Sendable {
    case show
    case hide
    case showConsole
    case toggleElementSelection
}

// MARK: - Script Evaluation

nonisolated struct ScriptRequest: Codable, Hashable, Sendable {
    nonisolated enum World: Codable, Hashable, Sendable {
        /// The page's own JavaScript world.
        case page
        /// A named isolated world, invisible to page scripts.
        case isolated(name: String)
    }

    let source: String
    var world: World = .page
    /// Run with a synthesized user gesture. Off by default: a synthesized gesture
    /// erases the page's real transient activation in WebKit.
    var userGesture = false
}

/// A JSON-compatible value returned from a script.
nonisolated enum ScriptValue: Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([ScriptValue])
    case object([String: ScriptValue])

    /// Converts a Foundation JSON object (`NSNumber`, `NSString`, `NSArray`, `NSDictionary`, `NSNull`).
    init(foundation value: Any?) {
        switch value {
        case nil, is NSNull:
            self = .null
        case let number as NSNumber:
            self = CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool(number.boolValue) : .number(number.doubleValue)
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = .array(array.map { ScriptValue(foundation: $0) })
        case let dictionary as [String: Any]:
            self = .object(dictionary.mapValues { ScriptValue(foundation: $0) })
        default:
            self = .string(String(describing: value!))
        }
    }

    /// The Foundation form callers that predate the contract expect.
    var foundationValue: Any? {
        switch self {
        case .null: nil
        case let .bool(value): value
        case let .number(value): value
        case let .string(value): value
        case let .array(values): values.map { $0.foundationValue ?? NSNull() }
        case let .object(values): values.mapValues { $0.foundationValue ?? NSNull() }
        }
    }
}

// MARK: - Page Requests

/// A decision an engine needs from Refrax before it can continue.
///
/// Every request is answered exactly once. An engine that receives no answer
/// within its own timeout applies the safe default (deny / cancel).
nonisolated enum PageRequestKind: Codable, Hashable, Sendable {
    /// The page wants a URL opened outside itself (`window.open`, ⌘-click, `target=_blank`).
    case openURL(url: URL, disposition: OpenDisposition, userGesture: Bool)
    case permission(kind: PermissionKind, origin: URL)
    case javaScriptDialog(dialog: JavaScriptDialog)
    /// Where to save a download; answered with a destination or a cancel.
    case download(url: URL, suggestedFilename: String, mimeType: String?)
}

nonisolated enum OpenDisposition: String, Codable, Hashable, Sendable {
    case currentTab
    case foregroundTab
    case backgroundTab
    case popup
    case newWindow
}

nonisolated enum PermissionKind: String, Codable, Hashable, Sendable {
    case camera
    case microphone
    case cameraAndMicrophone
    case geolocation
    case notifications
    case screenCapture
    case clipboardRead
}

nonisolated struct JavaScriptDialog: Codable, Hashable, Sendable {
    nonisolated enum Kind: String, Codable, Hashable, Sendable {
        case alert
        case confirm
        case prompt
        case beforeUnload
    }

    let kind: Kind
    let message: String
    let defaultText: String?
    let origin: URL?
}

nonisolated enum PageRequestAnswer: Codable, Hashable, Sendable {
    case handled
    case allow
    case deny
    case confirm(text: String?)
    case cancel
    case saveTo(url: URL)
}

/// A request plus the one-shot reply the engine is waiting on.
nonisolated struct PageRequest: Sendable {
    let kind: PageRequestKind
    let reply: @Sendable (PageRequestAnswer) -> Void
}

// Encodes as the plain JSON value, not as a tagged enum.
nonisolated extension ScriptValue: Codable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([ScriptValue].self) {
            self = .array(value)
        } else {
            self = try .object(container.decode([String: ScriptValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(values): try container.encode(values)
        case let .object(values): try container.encode(values)
        }
    }
}
