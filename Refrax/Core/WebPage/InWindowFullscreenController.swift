import AppKit
import Carbon.HIToolbox
import WebKit

/// Contains element fullscreen inside the tab instead of a macOS fullscreen Space.
///
/// Installs a replacement fullscreen client on the page via WebKit's exported
/// `WKPageSetFullScreenClientForTesting` C API. With it installed, WebKit never
/// constructs `WKFullScreenWindowController` — no separate window, no Space —
/// while the web process still runs the complete Fullscreen API sequence:
/// `document.fullscreenElement` is set, `fullscreenchange` fires, `:fullscreen`
/// styles apply, and the fullscreened element covers the viewport at the web
/// view's current size. The site's own fullscreen layout (e.g. YouTube's player
/// chrome) fills the tab.
///
/// Esc exits: the system's Esc handling lives in the fullscreen window WebKit
/// no longer creates, so this controller monitors Esc while fullscreen is
/// active and asks the page to exit via `WKPageRequestExitFullScreen`.
///
/// One controller per `WebPage`, created at web view creation when the
/// in-window fullscreen setting is enabled. `clientInfo` holds an unretained
/// pointer to this controller, so the owning `WebPage` must keep it alive for
/// the web view's lifetime.
@MainActor
final class InWindowFullscreenController {
    private weak var webView: WKWebView?
    private var escapeMonitor: Any?

    /// Whether the page is currently in in-window fullscreen.
    private(set) var isActive = false

    init(webView: WKWebView) {
        self.webView = webView

        var client = WKPageFullScreenClientV0()
        client.base.version = 0
        client.base.clientInfo = UnsafeRawPointer(Unmanaged.passUnretained(self).toOpaque())

        client.willEnterFullScreen = { _, listener, clientInfo in
            MainActor.assumeIsolated {
                controller(from: clientInfo)?.fullscreenDidBegin()
            }
            WKCompletionListenerComplete(listener, nil)
        }
        client.beganEnterFullScreen = { _, _, _, _ in }
        client.exitFullScreen = { _, clientInfo in
            MainActor.assumeIsolated {
                controller(from: clientInfo)?.fullscreenDidEnd()
            }
        }
        client.beganExitFullScreen = { _, _, _, listener, clientInfo in
            MainActor.assumeIsolated {
                controller(from: clientInfo)?.fullscreenDidEnd()
            }
            WKCompletionListenerComplete(listener, nil)
        }

        withUnsafePointer(to: &client) { pointer in
            pointer.withMemoryRebound(to: WKPageFullScreenClientBase.self, capacity: 1) { basePointer in
                WKPageSetFullScreenClientForTesting(webView._pageRefForTransitionToWKWebView, basePointer)
            }
        }
    }

    isolated deinit {
        removeEscapeMonitor()
    }

    // MARK: - State Transitions

    private func fullscreenDidBegin() {
        isActive = true
        installEscapeMonitor()
        Logger.info("In-window fullscreen entered", category: Logger.webview)
    }

    private func fullscreenDidEnd() {
        guard isActive else { return }
        isActive = false
        removeEscapeMonitor()
        Logger.info("In-window fullscreen exited", category: Logger.webview)
    }

    // MARK: - Escape Handling

    private func installEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            let handled = MainActor.assumeIsolated { [weak self] () -> Bool in
                guard let self,
                      self.isActive,
                      let webView = self.webView,
                      webView.window?.isKeyWindow == true
                else { return false }
                WKPageRequestExitFullScreen(webView._pageRefForTransitionToWKWebView)
                return true
            }
            return handled ? nil : event
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
    }
}

/// Recovers the controller from a fullscreen client callback's `clientInfo`.
@MainActor
private func controller(from clientInfo: UnsafeRawPointer?) -> InWindowFullscreenController? {
    guard let clientInfo else { return nil }
    return Unmanaged<InWindowFullscreenController>.fromOpaque(clientInfo).takeUnretainedValue()
}
