import Foundation
import SwiftData

/// A single web page within a browser tab.
///
/// `TabPage` represents the persisted state of a web page. Each ``Tab`` contains
/// one or more pages, enabling split-view layouts where multiple pages display
/// side-by-side.
///
/// ## Overview
///
/// Tab pages store only persistent state—URL, title, favicon, and layout position.
/// Runtime state like loading progress and navigation history lives in ``WebPage``,
/// which is created on-demand when a page becomes active.
///
/// ```
/// ┌─────────────────────────────────────────┐
/// │ Tab                                     │
/// │  ├─ TabPage (topLeft)  ←→ WebPage       │
/// │  └─ TabPage (topRight) ←→ WebPage       │
/// └─────────────────────────────────────────┘
/// ```
///
/// ## Persistence
///
/// Tab pages are persisted with SwiftData. On app restart, pages restore their
/// URL and title, but navigation history (back/forward) resets since that state
/// lives in WebKit's runtime.
///
/// ## Layout Positioning
///
/// For multi-page tabs, each page has a ``position`` indicating where it renders:
///
/// ```swift
/// // Single page (default)
/// let page = TabPage(url: url)  // position = .single
///
/// // Split view
/// let leftPage = TabPage(url: url1, layoutPosition: .topLeft)
/// let rightPage = TabPage(url: url2, layoutPosition: .topRight)
/// ```
///
/// ## Lifecycle
///
/// - **Creation**: Via ``Tab/init(spaceID:url:title:isPinned:isFavorite:isReferenceTab:groupID:position:)``
///   or when adding pages to an existing tab
/// - **Activation**: ``TabManager/session(for:)`` creates a runtime session
/// - **Persistence**: Automatic via SwiftData when properties change
/// - **Deletion**: Cascade-deleted when parent ``Tab`` is deleted
///
/// - Important: Modify pages through ``TabManager`` methods to ensure proper
///   session lifecycle management.
@Model
final class TabPage: Identifiable {
    // MARK: - Identity

    /// Unique identifier for this page.
    ///
    /// Used as the key for session pooling in ``TabManager`` and history tracking
    /// in ``HistoryManager``.
    @Attribute(.unique, .preserveValueOnDeletion)
    var id: UUID
    
    /// Parent tab containing this page.
    ///
    /// Set automatically by SwiftData's inverse relationship from ``Tab/pages``.
    /// May be `nil` briefly during initialization.
    ///
    /// - Note: Use ``parentTab`` for non-optional access with precondition checking.
    var tab: Tab?

    /// The parent tab, with a precondition that it exists.
    ///
    /// Use this accessor when you need non-optional access to the parent tab.
    /// The precondition will fail if the page hasn't been added to a tab yet.
    ///
    /// - Precondition: The page must have been added to a tab's ``Tab/pages`` array.
    var parentTab: Tab {
        guard let tab else {
            preconditionFailure("TabPage accessed before being added to a Tab")
        }
        return tab
    }
    
    // MARK: - Content
    
    /// The URL this page displays.
    ///
    /// Updated by ``WebPage`` during navigation. For deep link URLs
    /// (e.g., `refrax://settings`), no runtime page is created and native views
    /// render instead.
    var url: URL

    /// The page title extracted from HTML `<title>`.
    ///
    /// Updated by ``WebPage`` when navigation commits or finishes.
    /// Falls back to "New Tab" for blank pages.
    var title: String
    
    /// Small favicon image data (PNG format, ~64px).
    ///
    /// Populated by ``IconLoadingDelegateAdapter`` during page load via WebKit's
    /// native icon loading. Used in tab list and tab switcher UI. May be `nil`
    /// if the page has no favicon or loading fails.
    var faviconData: Data?

    /// Large favicon image data (PNG format, ~180px).
    ///
    /// Populated by ``IconLoadingDelegateAdapter`` from Apple Touch Icons or other
    /// high-resolution icon sources. Used in favorites grid and drag overlays.
    /// Falls back to ``faviconData`` if unavailable.
    var largeFaviconData: Data?

    /// The ID of the TabPage that opened this page via window.open().
    ///
    /// Used to restore focus when popups close and to visualize relationships.
    var openerTabPageID: UUID?
    
    // MARK: - Layout
    
    /// Raw layout position string for SwiftData compatibility.
    ///
    /// Use the computed ``position`` property for type-safe access.
    /// Stores ``PanePosition/rawValue`` or `nil` for single-page tabs.
    var layoutPosition: String?
    
    /// Position within a multi-page tab layout.
    ///
    /// - `nil` or `.single`: Standard single-page tab
    /// - `.topLeft`, `.topRight`, etc.: Position in split-view grid
    ///
    /// ## Layout Grid
    ///
    /// ```
    /// ┌──────────┬──────────┐
    /// │ topLeft  │ topRight │
    /// ├──────────┼──────────┤
    /// │bottomLeft│bottomRight│
    /// └──────────┴──────────┘
    /// ```
    var position: PanePosition? {
        get { layoutPosition.flatMap(PanePosition.init) }
        set { layoutPosition = newValue?.rawValue }
    }
    
    // MARK: - Metadata
    
    /// When this page was created.
    ///
    /// Set once during initialization. Used for sorting and analytics.
    var createdAt: Date

    // MARK: - Scroll Position

    /// Saved scroll position (Y offset) for restoration.
    ///
    /// Persisted when the page becomes hidden or when the WebPage session ends.
    /// Used to restore the user's reading position when the tab is reopened
    /// after app restart or WebPage eviction.
    ///
    /// - Note: Set to `nil` after restoration to prevent re-applying on
    ///   subsequent navigations within the same session.
    var scrollPositionY: Double?

    // MARK: - Initialization
    
    /// Creates a new tab page.
    ///
    /// - Parameters:
    ///   - url: The URL to display. Defaults to `about:blank`.
    ///   - title: Initial page title. Defaults to "New Tab".
    ///   - layoutPosition: Position in split-view layout, or `nil` for single-page tabs.
    init(
        url: URL = .blank,
        title: String = "New Page",
        layoutPosition: PanePosition? = nil,
    ) {
        self.id = UUID()
        self.url = url
        self.title = title
        self.faviconData = nil
        self.layoutPosition = layoutPosition?.rawValue
        self.createdAt = Date()
    }
    
    // MARK: - Computed Properties
    
    /// Whether the page uses HTTPS.
    ///
    /// Used for security indicator UI in the address bar.
    var isSecure: Bool {
        url.scheme == "https"
    }
}

// MARK: - Pane Position

/// Position of a page within a multi-page tab layout.
///
/// Tabs can display up to four pages simultaneously in a grid layout.
/// Single-page tabs use `.single` (the default).
///
/// ## Supported Layouts
///
/// | Page Count | Positions Used |
/// |------------|----------------|
/// | 1 | `.single` |
/// | 2 | `.topLeft`, `.topRight` (horizontal split) |
/// | 2 | `.topLeft`, `.bottomLeft` (vertical split) |
/// | 4 | All four corners |
///
/// ## Sort Order
///
/// Positions sort left-to-right, top-to-bottom for consistent UI ordering.
nonisolated enum PanePosition: String, Codable, CaseIterable, Sendable {
    /// Single page filling the entire tab (default).
    case single
    
    /// Top-left quadrant in a multi-page layout.
    case topLeft
    
    /// Top-right quadrant in a multi-page layout.
    case topRight
    
    /// Bottom-left quadrant in a multi-page layout.
    case bottomLeft
    
    /// Bottom-right quadrant in a multi-page layout.
    case bottomRight
    
    /// Sort order for consistent page ordering in UI.
    ///
    /// Orders: single (0), topLeft (1), topRight (2), bottomLeft (3), bottomRight (4)
    var sortOrder: Int {
        switch self {
        case .single: 0
        case .topLeft: 1
        case .topRight: 2
        case .bottomLeft: 3
        case .bottomRight: 4
        }
    }
}
