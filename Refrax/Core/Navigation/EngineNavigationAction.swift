import Foundation

/// A navigation a plug-in engine asks Refrax about, as the navigation handlers read it.
///
/// Built from the contract's `navigation` and `openURL` requests, whose fields carry what the
/// handlers need from WebKit's `WKNavigationAction`: the kind of navigation, who started it, and,
/// for URLs the page wants opened elsewhere, whether a modifier click or the page asked.
struct EngineNavigationAction: NavigationActionInput {
    let url: URL?
    let redirectChain: RedirectChain?
    let isMainFrame: Bool
    let isNewWindowRequest: Bool
    let isCommandClick: Bool
    let isShiftHeld: Bool
    let kind: NavigationKind

    /// The initiating document's origin scheme; empty when Refrax or the user started the
    /// navigation, `"null"` for an opaque origin, as WebKit's `securityOrigin.protocol` reads.
    let sourceSecurityOriginProtocol: String

    var isMiddleClick: Bool {
        false
    }

    var isUserInitiated: Bool {
        kind != .other
    }

    var isLinkActivated: Bool {
        kind == .link
    }

    var isFormSubmission: Bool {
        kind == .formSubmission
    }

    var isBackForward: Bool {
        kind == .backForward
    }

    var isReload: Bool {
        kind == .reload
    }

    /// Engines report `download` links as downloads (the `download` request), never here.
    var shouldPerformDownload: Bool {
        false
    }

    var shouldActivateNewTab: Bool {
        if isCommandClick {
            return isShiftHeld
        }
        return isNewWindowRequest
    }

    var targetIsMainFrame: Bool? {
        isNewWindowRequest ? nil : isMainFrame
    }

    /// A main-frame navigation the engine is about to start in the page.
    init(url: URL, kind: NavigationKind, initiatorOrigin: String?) {
        self.url = url
        self.kind = kind
        var chain = RedirectChain()
        chain.append(url)
        redirectChain = chain
        isMainFrame = true
        isNewWindowRequest = false
        isCommandClick = false
        isShiftHeld = false
        sourceSecurityOriginProtocol = initiatorOrigin.map { URL(string: $0)?.scheme ?? "null" } ?? ""
    }

    /// A URL the page showing `sourceURL` wants opened outside itself.
    ///
    /// A modifier click reads as ⌘-click, with Shift when it opens in front; a page's own request
    /// for a new browsing context reads as a new-window request, as WebKit reports `target=_blank`.
    init(url: URL, disposition: OpenDisposition, userGesture: Bool, isNewWindowRequest: Bool?, sourceURL: URL?) {
        let byModifierClick = !(isNewWindowRequest ?? (disposition != .backgroundTab))
        self.url = url
        kind = userGesture ? .link : .other
        redirectChain = nil
        isMainFrame = false
        self.isNewWindowRequest = !byModifierClick
        isCommandClick = byModifierClick
        isShiftHeld = byModifierClick && disposition != .backgroundTab
        sourceSecurityOriginProtocol = sourceURL?.scheme ?? "null"
    }
}
