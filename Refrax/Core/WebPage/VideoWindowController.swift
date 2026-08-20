import AppKit
import WebKit

/// Hosts a fullscreened page in a separate floating window.
///
/// The windowed presentation of ``FullscreenPresentationMode``: when a page
/// enters element fullscreen and the mode is `.windowed`, the tab's adapter
/// freezes into a GPU snapshot and the live `WKWebView` moves into a plain
/// Refrax-owned window — traffic lights only, movable, resizable, remembered
/// frame, green button for real macOS fullscreen. Closing the window (red
/// button, Cmd+W) asks the page to exit fullscreen; the exit callbacks then
/// move the web view back into the tab.
///
/// This is WebKit's own placeholder technique (snapshot + view move) with the
/// adapter's existing snapshot machinery standing in for
/// `WKFullScreenPlaceholderView`.
@MainActor
final class VideoWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private weak var webView: WebPageWebView?
    private weak var webPage: WebPage?
    private weak var tabAdapter: CocoaWebViewAdapter?

    /// Whether the video window is currently presenting the web view.
    private(set) var isPresented = false

    private enum Layout {
        static let minimumSize = NSSize(width: 640, height: 360)
        static let defaultSize = NSSize(width: 1024, height: 576)
        static let frameAutosaveName = "RefraxVideoWindow"
    }

    // MARK: - Presentation

    /// Moves the web view into the video window.
    ///
    /// The tab's adapter is frozen into a snapshot first (which detaches the
    /// web view), then the web view is prepared for the cross-window move and
    /// added to the video window.
    func present(webView: WebPageWebView, webPage: WebPage) {
        guard !isPresented else { return }
        isPresented = true
        self.webView = webView
        self.webPage = webPage

        // Freeze the tab into a snapshot; this detaches the web view.
        if let adapter = webView.delegate as? CocoaWebViewAdapter {
            tabAdapter = adapter
            adapter.setSnapshotMode(for: webPage)
        } else {
            webView.removeFromSuperview()
        }
        webPage.isWebViewInVideoWindow = true

        let window = makeWindow(title: webPage.title.isEmpty ? "Video" : webPage.title)
        self.window = window

        webView._prepareForMove(to: window) { [weak self, weak webView, weak window] in
            MainActor.assumeIsolated {
                guard let self, self.isPresented, let webView, let window,
                      let contentView = window.contentView
                else { return }
                webView.translatesAutoresizingMaskIntoConstraints = true
                webView.autoresizingMask = [.width, .height]
                webView.frame = contentView.bounds
                webView.isHidden = false
                contentView.addSubview(webView)
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    /// Returns the web view to its tab and closes the video window.
    ///
    /// If the tab's adapter still shows this page's snapshot, the web view is
    /// handed back through `setActiveMode` (which performs the cross-window
    /// preparation). Otherwise the web view is left detached and the normal
    /// display-mode flow reattaches it when its tab next becomes visible.
    func dismiss() {
        guard isPresented else { return }
        isPresented = false

        if let window {
            window.delegate = nil
            window.saveFrame(usingName: Layout.frameAutosaveName)
            window.orderOut(nil)
        }

        webPage?.isWebViewInVideoWindow = false

        if let webView {
            webView.removeFromSuperview()
            if let webPage,
               let adapter = tabAdapter,
               adapter.window != nil,
               case let .snapshot(pageID) = adapter.displayMode,
               pageID == webPage.id {
                adapter.setActiveMode(webView: webView, expectedFrame: adapter.bounds)
            }
        }

        window?.close()
        window = nil
        tabAdapter = nil
    }

    // MARK: - Window

    private func makeWindow(title: String) -> NSWindow {
        let window = VideoWindow(
            contentRect: NSRect(origin: .zero, size: Layout.defaultSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false,
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = title
        window.isMovableByWindowBackground = true
        window.backgroundColor = .black
        window.minSize = Layout.minimumSize
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .documentWindow
        window.delegate = self

        if !window.setFrameUsingName(Layout.frameAutosaveName) {
            window.center()
        }
        window.setFrameAutosaveName(Layout.frameAutosaveName)
        return window
    }

    // MARK: - Window Subclass

    /// Intercepts Cmd+W before the main menu's "Close Tab" item can claim it —
    /// with the video window key, Cmd+W must close this window (via the
    /// fullscreen exit in `windowShouldClose`), not the browser tab.
    private final class VideoWindow: NSWindow {
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
               event.charactersIgnoringModifiers == "w" {
                performClose(nil)
                return true
            }
            return super.performKeyEquivalent(with: event)
        }
    }

    // MARK: - NSWindowDelegate

    func windowShouldClose(_: NSWindow) -> Bool {
        // Route the close through the page's fullscreen exit so DOM state,
        // the site's own UI, and our client callbacks all stay consistent.
        // The exit callbacks call dismiss(), which closes the window.
        if let webView {
            WKPageRequestExitFullScreen(webView._pageRefForTransitionToWKWebView)
            return false
        }
        return true
    }
}
