import AppKit

// MARK: - Engine Identity

/// A rendering engine a page can run on.
///
/// WebKit is built in and hosts every page by default. Other engines are
/// installed plug-ins that a page switches to on demand; the page keeps its
/// tab, history, and chrome and only the content view and navigation source
/// change hands.
nonisolated enum RenderingEngineKind: String, CaseIterable, Codable, Sendable {
    case webKit
    case chromium

    var displayName: String {
        switch self {
        case .webKit: "WebKit"
        case .chromium: "Chromium"
        }
    }
}

/// Browser features whose availability depends on the engine hosting the page.
///
/// The chrome asks the active engine before offering a feature, so an engine
/// declares what it can do rather than every call site checking engine kinds.
nonisolated struct EngineCapabilities: OptionSet, Sendable {
    let rawValue: Int

    static let navigation = EngineCapabilities(rawValue: 1 << 0)
    static let javaScriptEvaluation = EngineCapabilities(rawValue: 1 << 1)
    static let zoom = EngineCapabilities(rawValue: 1 << 2)
    static let findInPage = EngineCapabilities(rawValue: 1 << 3)
    static let downloads = EngineCapabilities(rawValue: 1 << 4)
    static let devTools = EngineCapabilities(rawValue: 1 << 5)
    static let webExtensions = EngineCapabilities(rawValue: 1 << 6)
    static let contentBlocking = EngineCapabilities(rawValue: 1 << 7)
    static let userScripts = EngineCapabilities(rawValue: 1 << 8)
    static let readerMode = EngineCapabilities(rawValue: 1 << 9)
    static let pictureInPicture = EngineCapabilities(rawValue: 1 << 10)
    static let thumbnails = EngineCapabilities(rawValue: 1 << 11)
    static let agentPerception = EngineCapabilities(rawValue: 1 << 12)
    static let autoFill = EngineCapabilities(rawValue: 1 << 13)
}

// MARK: - Page Session

/// How a page asked for a URL to be opened outside its own browsing context.
nonisolated enum EngineOpenDisposition: Sendable {
    case currentTab
    case foregroundTab
    case backgroundTab
    case popup
    case newWindow
}

/// One page's content running on an engine other than the page's built-in WebKit view.
///
/// This is the surface the browser chrome consumes: navigation, observable
/// page state, script evaluation, and the view to display. Everything else a
/// `WebPage` offers is WebKit-specific and gated by ``EngineCapabilities``.
@MainActor
protocol EnginePageSession: AnyObject {
    var engine: RenderingEngineKind { get }
    var capabilities: EngineCapabilities { get }

    /// The view that displays the page. Owned by the session; hosts re-parent it.
    var contentView: NSView { get }

    var delegate: (any EnginePageSessionDelegate)? { get set }

    var url: URL? { get }
    var title: String { get }
    var isLoading: Bool { get }
    var estimatedProgress: Double { get }
    var canGoBack: Bool { get }
    var canGoForward: Bool { get }

    /// Page zoom as a multiplier, 1.0 being 100%.
    var zoomFactor: Double { get set }

    func load(_ url: URL)
    func goBack()
    func goForward()
    func reload(fromOrigin: Bool)
    func stopLoading()

    /// Evaluates `script` in the main frame and returns its JSON-compatible value.
    func evaluateJavaScript(_ script: String) async throws -> Any?

    /// Throttles rendering and timers while the page is off screen.
    func setHidden(_ hidden: Bool)
    func focus()
    func showDevTools()

    /// Tears the session down. The session is inert afterwards.
    func close()
}

/// Navigation and page events a session reports to the page that owns it.
@MainActor
protocol EnginePageSessionDelegate: AnyObject {
    func engineSession(_ session: any EnginePageSession, didCommitNavigationTo url: URL, isBackForward: Bool)
    func engineSession(_ session: any EnginePageSession, didFinishNavigationWithStatusCode statusCode: Int)
    func engineSession(_ session: any EnginePageSession, didFailNavigationTo url: URL?, code: Int, description: String)
    func engineSession(_ session: any EnginePageSession, didChangeTitle title: String)
    func engineSession(_ session: any EnginePageSession, didChangeFaviconURLs urls: [URL])
    func engineSession(_ session: any EnginePageSession, didHoverLink url: URL?)
    func engineSession(_ session: any EnginePageSession, requestsOpening url: URL, disposition: EngineOpenDisposition)
    func engineSessionRenderProcessDidTerminate(_ session: any EnginePageSession)
    func engineSession(_ session: any EnginePageSession, destinationForDownloadOf url: URL, suggestedFilename: String) -> URL?
}

// MARK: - Engine

nonisolated enum RenderingEngineError: LocalizedError {
    case notInstalled(RenderingEngineKind)
    case failedToLoad(RenderingEngineKind, String)
    case failedToStart(RenderingEngineKind, String)

    var errorDescription: String? {
        switch self {
        case let .notInstalled(kind):
            "\(kind.displayName) is not installed."
        case let .failedToLoad(kind, reason):
            "\(kind.displayName) could not be loaded: \(reason)"
        case let .failedToStart(kind, reason):
            "\(kind.displayName) could not start: \(reason)"
        }
    }
}

/// A plug-in rendering engine: a process-wide runtime that vends page sessions.
@MainActor
protocol RenderingEngine: AnyObject {
    var kind: RenderingEngineKind { get }
    var isInstalled: Bool { get }
    var isRunning: Bool { get }
    /// Engine build identifier for display, e.g. "Chromium 154.0.8037.17".
    var versionDescription: String? { get }

    /// Loads and starts the engine. Idempotent.
    func start() throws

    /// Creates a session for a page. `profile` groups sessions that share cookies and storage.
    func makeSession(url: URL?, profile: EngineProfile) throws -> any EnginePageSession

    func shutdown()
}

/// The storage partition a session runs in, mirroring a space's data store.
nonisolated enum EngineProfile: Hashable, Sendable {
    /// Persistent storage, keyed by an identifier (a space's data-store ID).
    case persistent(String)
    /// In-memory storage discarded when the engine shuts down.
    case ephemeral
}
