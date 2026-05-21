import Foundation

/// Quick filter types for filtering tabs in the sidebar.
///
/// Quick filters provide one-click access to common filter conditions like
/// media playback state, camera/microphone usage, and read status. Unlike
/// saved filters which persist across sessions, quick filters are ephemeral
/// and reset when the filter is cleared.
///
/// ## WebPage-Based Filters
///
/// Some filters (media, camera, microphone) require access to `WebPage`
/// state which is only available for active tabs. Inactive tabs without
/// active pages are excluded from these filters.
///
/// ## Usage
///
/// ```swift
/// filterManager.quickFilter = .playingAudio
/// filterManager.quickFilter = .unread
/// filterManager.quickFilter = nil  // Clear filter
/// ```
enum QuickFilter: Hashable, Identifiable, CaseIterable {
    /// Show only unread tabs (opened in background, not yet viewed).
    case unread

    /// Show only read tabs (previously viewed).
    case read

    /// Show only tabs with audio (playing or muted).
    case audible

    /// Show only tabs using camera or microphone.
    case mediaCapture

    // MARK: - Identifiable

    var id: Self { self }

    // MARK: - Display

    /// User-facing name for the filter.
    var displayName: String {
        switch self {
        case .unread: "Unread"
        case .read: "Read"
        case .audible: "Audible"
        case .mediaCapture: "Using Mic/Camera"
        }
    }

    /// SF Symbol icon name for the filter.
    var iconName: String {
        switch self {
        case .unread: "circle.fill"
        case .read: "circle"
        case .audible: "speaker.wave.2"
        case .mediaCapture: "video"
        }
    }

    /// Whether this filter requires access to WebPage.
    ///
    /// Page-based filters can only match tabs that have an active page.
    /// Tabs without pages are excluded from results.
    var requiresWebPage: Bool {
        switch self {
        case .unread, .read:
            false
        case .audible, .mediaCapture:
            true
        }
    }

    /// Keywords that trigger autocomplete for this filter.
    ///
    /// Used by the filter search field to suggest this filter when the user
    /// types any of these keywords. Keywords are matched as prefixes.
    var autocompleteKeywords: [String] {
        switch self {
        case .unread:
            ["unread"]
        case .read:
            ["read"]
        case .audible:
            ["audible", "audio", "sound", "playing", "music"]
        case .mediaCapture:
            ["mic", "microphone", "camera", "video", "recording", "capture"]
        }
    }

    /// Returns the quick filter matching the given search text, if any.
    ///
    /// Matches against `autocompleteKeywords` using prefix matching.
    /// - Parameter text: The search text to match.
    /// - Returns: The first matching filter, or `nil` if no match.
    static func matching(searchText text: String) -> QuickFilter? {
        let lowercased = text.lowercased()
        for filter in allCases {
            for keyword in filter.autocompleteKeywords {
                if keyword.hasPrefix(lowercased) {
                    return filter
                }
            }
        }
        return nil
    }
}
