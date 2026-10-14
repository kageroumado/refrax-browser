import SwiftUI

struct MainContentView: View {
    @Environment(BrowserSettings.self) private var settings
    @Environment(ClipboardMonitor.self) private var clipboardMonitor
    @Environment(WindowState.self) private var windowState
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(TabManager.self) private var tabManager
    @Environment(TableController.self) private var table

    @State private var showClipboardToast = false
    @State private var size: CGSize = .zero

    /// The page's area beside pages docked to the window's sides.
    private var dockedPageFrame: CGRect {
        let bounds = CGRect(origin: .zero, size: size)
        guard !bounds.isEmpty else { return bounds }
        return canvas.dockedPageFrame(in: bounds)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            contentRouter

            AutoFillOverlayView()
            AgentCursorOverlay()
        }
        .padding(.leading, dockedPageFrame.minX)
        .padding(.trailing, max(0, size.width - dockedPageFrame.maxX))
        .ignoresSafeArea(edges: .vertical)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .overlay(alignment: .bottom) {
            clipboardToastOverlay
        }
        .overlay(alignment: .top) {
            HumanInterventionBanner()
        }
        .onChange(of: clipboardMonitor.detectedURL) { _, url in
            showClipboardToast = url != nil
        }
        .onChange(of: settings.clipboardLinkMonitoring) { _, _ in
            clipboardMonitor.syncWithSettings()
        }
        .tabCloseConfirmation(tabManager: tabManager, windowState: windowState)
    }

    /// Displays the active page at its shared table anchor.
    @ViewBuilder
    private var contentRouter: some View {
        if let activeTab = windowState.activeTab {
            if table.holds(activeTab) {
                TableView()
            } else {
                UnifiedContentView(tab: activeTab)
            }
        } else {
            FloatingStartPage()
        }
    }

    @ViewBuilder
    private var clipboardToastOverlay: some View {
        if showClipboardToast, let url = clipboardMonitor.detectedURL {
            ClipboardURLToast(url: url) {
                showClipboardToast = false
            }
            .padding(.bottom, Constants.clipboardToastBottomPadding)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(duration: 0.3), value: showClipboardToast)
        }
    }
}

// MARK: - Constants

private extension MainContentView {
    enum Constants {
        static let clipboardToastBottomPadding: CGFloat = 24
    }
}

// MARK: - AutoFill Overlay

/// Isolated view for autofill menu overlay.
///
/// Displays a SwiftUI-based autofill menu positioned below the focused field.
/// Uses overlay positioning based on field rect from JavaScript.
///
/// By extracting AutoFillState observation into a separate view struct,
/// changes to autofill context only invalidate this view, not the entire
/// MainContentView hierarchy.
private struct AutoFillOverlayView: View {
    @Environment(AutoFillState.self) private var autoFillState

    var body: some View {
        if let context = autoFillState.context, context.hasContent {
            Color.clear
                .overlay(alignment: .topLeading) {
                    // Position menu below the field
                    AutoFillMenuView(context: context)
                        .offset(
                            x: context.rect.minX,
                            y: context.rect.maxY + Constants.menuVerticalOffset,
                        )
                }
                .overlay(alignment: .topLeading) {
                    // Key icon at the trailing edge of credential fields
                    if context.fieldType == .credential {
                        AutoFillFieldKeyIcon(rect: context.rect)
                    }
                }
        }
    }

    private enum Constants {
        static let menuVerticalOffset: CGFloat = 4
    }
}
