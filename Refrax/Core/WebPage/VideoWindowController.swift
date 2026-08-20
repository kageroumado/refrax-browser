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
    private weak var dragStrip: DragStripView?
    private var chromeFadeTask: Task<Void, Never>?

    /// Whether the video window is currently presenting the web view.
    private(set) var isPresented = false

    private enum Layout {
        static let minimumSize = NSSize(width: 640, height: 360)
        static let defaultSize = NSSize(width: 1024, height: 576)
        static let frameAutosaveName = "RefraxVideoWindow"
        static let dragStripHeight: CGFloat = 30
        static let chromeFadeDuration: TimeInterval = 0.2
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
                self.installDragStrip(in: contentView)
                window.makeKeyAndOrderFront(nil)
                self.revealChromeThenFade()
            }
        }
    }

    // MARK: - Window Chrome

    /// Sets the traffic-light reveal (0 hidden … 1 visible), animated.
    ///
    /// Skipped in native macOS fullscreen, where the system manages the
    /// titlebar reveal itself.
    private func setChromeRevealed(_ revealed: Bool) {
        guard let window, !window.styleMask.contains(.fullScreen),
              let themeFrame = window.contentView?.superview as? NSThemeFrame
        else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Layout.chromeFadeDuration
            themeFrame.animator().buttonRevealAmount = revealed ? 1.0 : 0.0
        }
    }

    /// Shows the traffic lights briefly on presentation so the close button
    /// is discoverable, then fades them out.
    private func revealChromeThenFade() {
        setChromeRevealed(true)
        chromeFadeTask?.cancel()
        chromeFadeTask = Task(name: "Video window chrome fade") { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.dragStrip?.isMouseInside != true else { return }
            self.setChromeRevealed(false)
        }
    }

    /// Adds the transparent top strip that makes the window draggable and
    /// reveals the traffic lights on hover. Sits above the web view (which
    /// swallows every mouse event) but below the titlebar buttons, which live
    /// in the theme frame's titlebar container.
    private func installDragStrip(in contentView: NSView) {
        let strip = DragStripView(frame: NSRect(
            x: 0,
            y: contentView.bounds.height - Layout.dragStripHeight,
            width: contentView.bounds.width,
            height: Layout.dragStripHeight,
        ))
        strip.autoresizingMask = [.width, .minYMargin]
        strip.onHoverChanged = { [weak self] inside in
            guard let self else { return }
            self.chromeFadeTask?.cancel()
            self.setChromeRevealed(inside)
        }
        contentView.addSubview(strip)
        dragStrip = strip
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

        chromeFadeTask?.cancel()
        chromeFadeTask = nil
        dragStrip?.removeFromSuperview()

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

    // MARK: - Drag Strip

    /// Transparent strip along the window's top edge: dragging it moves the
    /// window (the web view underneath consumes every mouse event, so
    /// `isMovableByWindowBackground` alone gives nothing to grab), and
    /// hovering it reveals the traffic lights. Clicks in the strip go to the
    /// drag, not the page — the tradeoff that makes the window movable.
    private final class DragStripView: NSView {
        var onHoverChanged: ((Bool) -> Void)?
        private(set) var isMouseInside = false

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self,
            ))
        }

        override func mouseEntered(with _: NSEvent) {
            isMouseInside = true
            onHoverChanged?(true)
        }

        override func mouseExited(with _: NSEvent) {
            isMouseInside = false
            onHoverChanged?(false)
        }

        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
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
