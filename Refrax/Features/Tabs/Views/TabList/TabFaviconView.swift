import AppKit
import SwiftUI

/// Displays the favicon for a tab or specific page, with intelligent fallbacks.
///
/// Shows the downloaded favicon image if available, otherwise displays:
/// - `ProgressView` spinner when tab is loading
/// - `LetterIconView` with domain initial when no favicon is available
/// - Globe icon for special pages (about:blank, deep links)
///
/// Supports `.faviconBackground()` modifier for compact sidebar styling.
struct TabFaviconView: View {
    @Environment(WebPagePool.self) private var pagePool
    @Environment(\.faviconBackgroundColor) private var backgroundColor

    let tab: Tab
    let page: TabPage?
    let size: CGFloat

    // MARK: - State Snapshot for Equatable

    /// Favicon data byte count captured at init time.
    /// SwiftUI keeps old view structs for comparison, so this enables detecting
    /// when favicon data changes between the cached old view and new view.
    private let _snapshotFaviconCount: Int

    /// URL hash captured at init time for detecting navigation changes.
    private let _snapshotURLHash: Int

    // MARK: - Cached Display Values

    /// Cached favicon image to prevent flash during deletion animation.
    @State private var cachedFaviconImage: DecodedFavicon?

    /// Cached host for fallback letter icon.
    @State private var cachedHost: String?

    /// Whether to delay showing the fallback (true briefly after loading finishes).
    @State private var delayFallback = false

    init(tab: Tab, page: TabPage? = nil, size: CGFloat = Constants.Layout.tabFaviconSize) {
        self.tab = tab
        self.page = page
        self.size = size

        // Capture state snapshot for Equatable comparison.
        // SwiftUI compares old (cached) struct vs new struct - these captured values
        // let us detect when underlying model data has changed.
        let targetPage = page ?? tab.activePage
        self._snapshotFaviconCount = targetPage.faviconData?.count ?? -1
        self._snapshotURLHash = targetPage.url.hashValue
    }

    private var targetPage: TabPage? {
        page ?? (tab.pages.isEmpty ? nil : tab.activePage)
    }

    /// Whether the tab is being deleted (pages cascade-deleted).
    private var isBeingDeleted: Bool {
        tab.pages.isEmpty
    }

    /// Whether the target page is currently loading.
    private var isLoading: Bool {
        guard let targetPage else { return false }
        return pagePool.existingPage(for: targetPage)?.isLoading == true
    }

    var body: some View {
        // Read faviconData early to establish SwiftUI observation.
        // Without this, if the view shows loadingIndicator (which doesn't read faviconData),
        // SwiftUI won't observe changes to faviconData, and onChange won't fire.
        let currentFaviconData = targetPage?.faviconData

        ZStack {
            if isBeingDeleted {
                cachedContent
            } else if let targetPage {
                if isLoading {
                    loadingIndicator
                } else if isWebURL(targetPage.url) {
                    FaviconView(data: currentFaviconData, url: targetPage.url, size: size)
                        .environment(\.delayFaviconFallback, delayFallback)
                } else {
                    LetterFallbackView(host: "")
                }
            } else {
                LetterFallbackView(host: "")
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            if tab.isArchived {
                ArchivedTabBadge()
            }
        }
        .accessibilityHidden(true)
        .onAppear { updateDecodedFavicon() }
        .onChange(of: currentFaviconData) { _, _ in updateDecodedFavicon() }
        .onChange(of: targetPage?.url) { _, _ in updateDecodedFavicon() }
        .onChange(of: isLoading) { _, isNowLoading in
            if isNowLoading {
                // Loading started - set flag now so it's ready when loading finishes
                delayFallback = true
            }
        }
    }

    // MARK: - Loading Indicator

    @ViewBuilder
    private var loadingIndicator: some View {
        if let backgroundColor {
            SquircleShape()
                .fill(backgroundColor)

            ProgressView()
                .controlSize(.small)
        } else {
            ProgressView()
                .controlSize(.small)
        }
    }

    // MARK: - Cached Content

    @ViewBuilder
    private var cachedContent: some View {
        if let cachedImage = cachedFaviconImage {
            cachedFaviconView(cachedImage)
        } else if let host = cachedHost {
            letterFallback(host: host)
        } else {
            letterFallback(host: "")
        }
    }

    @ViewBuilder
    private func cachedFaviconView(_ favicon: DecodedFavicon) -> some View {
        let showBackground = backgroundColor != nil && favicon.hasAlphaChannel
        let insetSize = size * 0.75

        if showBackground {
            SquircleShape()
                .fill(backgroundColor!)

            Image(nsImage: favicon.image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: insetSize, height: insetSize)
                .clipToSquircle()
        } else {
            Image(nsImage: favicon.image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipToSquircle()
        }
    }

    @ViewBuilder
    private func letterFallback(host: String) -> some View {
        if let backgroundColor {
            SquircleShape()
                .fill(backgroundColor)

            LetterFallbackView(host: host)
                .frame(width: size, height: size)
        } else {
            LetterFallbackView(host: host)
        }
    }

    /// Updates cached favicon values only when the tab has valid pages.
    private func updateDecodedFavicon() {
        guard !tab.pages.isEmpty, let targetPage else { return }

        if let data = targetPage.faviconData {
            // Check global cache first to avoid redundant PNG decode + alpha detection
            let favicon = DecodedFaviconCache[data] ?? {
                guard let decoded = DecodedFavicon(data: data) else { return nil }
                DecodedFaviconCache[data] = decoded
                return decoded
            }()
            cachedFaviconImage = favicon
            cachedHost = nil
        } else if let host = targetPage.url.host, isWebURL(targetPage.url) {
            cachedFaviconImage = nil
            cachedHost = host
        } else {
            cachedFaviconImage = nil
            cachedHost = nil
        }
    }

    /// Checks if a URL is a regular web page (not a special scheme).
    private func isWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "file"
    }
}

// MARK: - Equatable

extension TabFaviconView: Equatable {
    /// Custom equality that compares captured state snapshots.
    ///
    /// SwiftUI caches view body results and compares old vs new view structs to decide
    /// whether to re-evaluate. With reference types (Tab, TabPage), the default comparison
    /// just checks pointer equality, which is always true for the same model object.
    ///
    /// By capturing state values at init time and comparing them here, we enable SwiftUI
    /// to detect when the underlying model data has actually changed, triggering body
    /// re-evaluation when needed.
    static func == (lhs: TabFaviconView, rhs: TabFaviconView) -> Bool {
        // Identity checks
        guard lhs.tab.id == rhs.tab.id else { return false }
        guard lhs.page?.id == rhs.page?.id else { return false }
        guard lhs.size == rhs.size else { return false }

        // State snapshot comparisons - these detect actual data changes
        guard lhs._snapshotFaviconCount == rhs._snapshotFaviconCount else { return false }
        guard lhs._snapshotURLHash == rhs._snapshotURLHash else { return false }

        return true
    }
}

// MARK: - Archived Tab Badge

/// Small trash icon badge displayed on archived tab favicons.
private struct ArchivedTabBadge: View {
    var body: some View {
        Image(systemName: "trash.fill")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.white)
            .padding(2)
            .background(
                Circle()
                    .fill(Color.secondary.opacity(0.9)),
            )
            .offset(x: 2, y: 2)
    }
}
