import AppKit
import SwiftUI

// MARK: - Overlay Container

/// Main overlay container for window-level overlays including sidebar and lenses.
///
/// Each overlay component handles its own observation scope to minimize re-renders.
/// The parent container orchestrates layout and coordinates animations.
///
/// ## Architecture
///
/// The container is hosted in a `TransparentHostingView` that sits above all window
/// content. When no overlay is active, clicks pass through to the content below.
/// Individual overlays handle their own hit testing regions.
///
/// ## Observation Isolation
///
/// Each overlay is extracted to its own file to isolate observation scope:
/// - `CommandLensOverlay` - Observes `showsCommandLens`
/// - `AddressLensOverlay` - Observes `showsAddressLens`, `addressBarFrame`
/// - `ScreenshotPreviewOverlay` - Observes `screenshotCoordinator.currentPreview`
/// - `RecordingPreviewOverlay` - Observes `recordingCoordinator.currentPreview`
/// - `ToastOverlay` - Observes `toastMessage`, `sidebarThickness`
/// - `SearchEngineDetectedOverlay` - Observes `pendingSearchEngineDetection`
struct OverlayContainer: View {
    @Environment(WindowState.self) private var windowState: WindowState
    @Environment(TabSwitcherManager.self) private var tabSwitcherManager: TabSwitcherManager
    @Environment(GuidedTourManager.self) private var guidedTourManager: GuidedTourManager

    /// The active space if it requires authentication, otherwise nil.
    private var lockedSpace: Space? {
        windowState.lockedSpaceRequiringAuth
    }

    /// Whether any overlay requires hit testing.
    ///
    /// When true, the hosting AppKit view passes clicks through to SwiftUI.
    /// The actual hit regions are handled by individual overlays.
    private var requiresHitTesting: Bool {
        windowState.showsCommandLens
            || windowState.showsAddressLens
            || windowState.toastMessage != nil
            || windowState.pendingSearchEngineDetection != nil
            || tabSwitcherManager.isActive
            || lockedSpace != nil
            || windowState.showsCompactAddressBar
            || guidedTourManager.isActive
    }

    var body: some View {
        // Read the lock version counter to ensure this body re-evaluates when the
        // reliable AppKit lock state observer fires. Without this, the transitive
        // observation chain through @ObservationIgnored intermediates may not
        // trigger re-renders in the NSHostingView context.
        let _ = windowState.spaceLockVersion

        ZStack(alignment: .topLeading) {
            // Tab preview overlay (rendered first so it appears behind lenses)
            TabPreviewOverlay()

            // Tab switcher overlay (Control+Tab)
            TabSwitcherOverlay()
            
            // Compact sidebar address bar overlay
            CompactAddressBarOverlay()

            // Command lens (Cmd+K)
            CommandLensOverlay()

            // Address lens (click address bar)
            AddressLensOverlay()

            // Guided tour instruction bubble
            GuidedTourOverlay()

            // Toast notification (top-right corner)
            ToastOverlay()

            // Search engine detection pill (top center)
            SearchEngineDetectedOverlay()

            // Screenshot preview (bottom-right corner)
            ScreenshotPreviewOverlay()

            // Recording preview (bottom-right corner)
            RecordingPreviewOverlay()

            // Compact sidebar tab title tooltip
            CompactTabTitleOverlay()

            // Space lock overlay (highest z-order - covers entire window)
            if let space = lockedSpace {
                LockedSpaceOverlayView(space: space)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.2), value: tabSwitcherManager.isActive)
        .animation(.easeInOut(duration: 0.2), value: lockedSpace != nil)
        .allowsHitTesting(requiresHitTesting)
        .accessibilityElement(children: .contain)
        .sheet(isPresented: browserImportBinding) {
            ImportWizardView()
        }
        .sheet(item: remindMeBinding) { pageInfo in
            RemindMeSheet(
                pageURL: pageInfo.url,
                pageTitle: pageInfo.title,
                isPresented: Binding(
                    get: { windowState.remindMePageInfo != nil },
                    set: { if !$0 { windowState.dismissRemindMeSheet() } },
                ),
            )
        }
        .sheet(item: gifPickerBinding) { context in
            GiphyPickerView { gif in
                Task {
                    await insertGIF(gif, into: context.page)
                }
            }
        }
    }

    // MARK: - Sheet Bindings

    private var browserImportBinding: Binding<Bool> {
        Binding(
            get: { windowState.showsBrowserImport },
            set: { windowState.showsBrowserImport = $0 },
        )
    }

    private var remindMeBinding: Binding<WindowState.RemindMePageInfo?> {
        Binding(
            get: { windowState.remindMePageInfo },
            set: { windowState.remindMePageInfo = $0 },
        )
    }

    private var gifPickerBinding: Binding<WindowState.GifPickerContext?> {
        Binding(
            get: { windowState.gifPickerContext },
            set: { windowState.gifPickerContext = $0 },
        )
    }

    // MARK: - GIF Insertion

    /// Inserts a GIF into the web page's focused input field.
    @MainActor
    private func insertGIF(_ gif: GiphyGIF, into page: WebPage) async {
        let script = JavaScriptSnippets.insertGIF(
            url: gif.originalURL.absoluteString,
            altText: gif.title,
        )

        do {
            let result = try await page.evaluateJavaScript(script)
            let success = (result as? Bool) ?? false

            if !success {
                copyGIFURLToClipboard(gif)
            }
        } catch {
            copyGIFURLToClipboard(gif)
        }
    }

    private func copyGIFURLToClipboard(_ gif: GiphyGIF) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(gif.originalURL.absoluteString, forType: .string)
        windowState.showToast("GIF URL copied to clipboard")
    }
}
