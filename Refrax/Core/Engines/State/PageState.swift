import Foundation
import Observation

// MARK: - Snapshot

/// Everything the chrome knows about a page, as a value.
///
/// Built only by ``PageReducer`` from ``PageEvent``s, so it can never disagree
/// with what the engine reported.
nonisolated struct PageSnapshot: Hashable, Sendable {
    /// The URL the page shows: the visible URL the engine last reported.
    var url: URL?
    /// The URL a provisional navigation is heading to, before it commits.
    var pendingURL: URL?
    var title = ""
    var isLoading = false
    var progress = 0.0
    var canGoBack = false
    var canGoForward = false
    var security: PageSecurity = .notApplicable
    var faviconURLs: [URL] = []
    var themeColor: RGBAColor?
    var topEdgeColor: RGBAColor?
    var hoveredLink: URL?
    var zoom = 1.0
    var media: PageMedia = .idle
    var fullscreen: PageFullscreen = .none
    var rendererHealth: RendererHealth = .running
    /// The failure the error page shows, if the last navigation failed before committing.
    var failure: NavigationFailure?
    /// HTTP status of the last finished main-frame load.
    var statusCode: Int?
}

// MARK: - Reducer

/// Folds engine events into a ``PageSnapshot``. Pure: no I/O, no engine access.
nonisolated enum PageReducer {
    static func reduce(_ state: inout PageSnapshot, _ event: PageEvent) {
        switch event {
        case let .navigationStarted(url):
            state.pendingURL = url
            state.failure = nil

        case let .navigationRedirected(url):
            state.pendingURL = url

        case let .navigationCommitted(url, _):
            state.url = url
            state.pendingURL = nil
            state.failure = nil
            state.statusCode = nil
            state.hoveredLink = nil
            state.faviconURLs = []
            state.themeColor = nil
            state.topEdgeColor = nil
            // A commit proves a live renderer: this is how a crashed page recovers.
            state.rendererHealth = .running

        case let .urlChanged(url):
            state.url = url

        case let .navigationFinished(_, statusCode):
            state.pendingURL = nil
            state.statusCode = statusCode

        case let .navigationFailed(failure):
            state.pendingURL = nil
            if failure.isProvisional, failure.kind != .cancelled {
                state.failure = failure
            }

        case let .titleChanged(title):
            state.title = title

        case let .progressChanged(progress):
            state.progress = min(max(progress, 0), 1)

        case let .loadingChanged(isLoading):
            state.isLoading = isLoading
            if !isLoading {
                state.progress = 1
            }

        case let .backForwardChanged(canGoBack, canGoForward):
            state.canGoBack = canGoBack
            state.canGoForward = canGoForward

        case let .securityChanged(security):
            state.security = security

        case let .faviconsChanged(urls):
            state.faviconURLs = urls

        case let .themeColorChanged(color):
            state.themeColor = color

        case let .topEdgeColorChanged(color):
            state.topEdgeColor = color

        case let .hoveredLinkChanged(url):
            state.hoveredLink = url

        case let .zoomChanged(zoom):
            state.zoom = zoom

        case let .mediaChanged(media):
            state.media = media

        case let .fullscreenChanged(fullscreen):
            state.fullscreen = fullscreen

        case let .rendererHealthChanged(health):
            state.rendererHealth = health
        }
    }
}

// MARK: - Observable State

/// The observable page state SwiftUI reads. The single source of truth for page UI.
///
/// Each field is stored separately so views are invalidated only by the fields
/// they read, and a field is written only when its value changes. Nothing but
/// ``apply(_:)`` writes to it.
@Observable
final class PageState {
    private(set) var url: URL?
    private(set) var pendingURL: URL?
    private(set) var title = ""
    private(set) var isLoading = false
    private(set) var progress = 0.0
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var security: PageSecurity = .notApplicable
    private(set) var faviconURLs: [URL] = []
    private(set) var themeColor: RGBAColor?
    private(set) var topEdgeColor: RGBAColor?
    private(set) var hoveredLink: URL?
    private(set) var zoom = 1.0
    private(set) var media: PageMedia = .idle
    private(set) var fullscreen: PageFullscreen = .none
    private(set) var rendererHealth: RendererHealth = .running
    private(set) var failure: NavigationFailure?
    private(set) var statusCode: Int?

    init(initialURL: URL? = nil) {
        url = initialURL
    }

    /// The state as one value, for tests and diffing.
    var snapshot: PageSnapshot {
        PageSnapshot(
            url: url, pendingURL: pendingURL, title: title, isLoading: isLoading, progress: progress,
            canGoBack: canGoBack, canGoForward: canGoForward, security: security, faviconURLs: faviconURLs,
            themeColor: themeColor, topEdgeColor: topEdgeColor, hoveredLink: hoveredLink, zoom: zoom,
            media: media, fullscreen: fullscreen, rendererHealth: rendererHealth, failure: failure,
            statusCode: statusCode,
        )
    }

    func apply(_ event: PageEvent) {
        var next = snapshot
        PageReducer.reduce(&next, event)
        assign(next)
    }

    /// Replaces the whole state, e.g. when a page moves to another engine.
    func reset(to snapshot: PageSnapshot) {
        assign(snapshot)
    }

    private func assign(_ next: PageSnapshot) {
        if url != next.url { url = next.url }
        if pendingURL != next.pendingURL { pendingURL = next.pendingURL }
        if title != next.title { title = next.title }
        if isLoading != next.isLoading { isLoading = next.isLoading }
        if progress != next.progress { progress = next.progress }
        if canGoBack != next.canGoBack { canGoBack = next.canGoBack }
        if canGoForward != next.canGoForward { canGoForward = next.canGoForward }
        if security != next.security { security = next.security }
        if faviconURLs != next.faviconURLs { faviconURLs = next.faviconURLs }
        if themeColor != next.themeColor { themeColor = next.themeColor }
        if topEdgeColor != next.topEdgeColor { topEdgeColor = next.topEdgeColor }
        if hoveredLink != next.hoveredLink { hoveredLink = next.hoveredLink }
        if zoom != next.zoom { zoom = next.zoom }
        if media != next.media { media = next.media }
        if fullscreen != next.fullscreen { fullscreen = next.fullscreen }
        if rendererHealth != next.rendererHealth { rendererHealth = next.rendererHealth }
        if failure != next.failure { failure = next.failure }
        if statusCode != next.statusCode { statusCode = next.statusCode }
    }
}
