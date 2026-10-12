import Foundation

/// The entries of a page's actions menu, in order, decided from the card that shows it.
///
/// A floating card's header carries the pin and the presentation toggle, so its menu holds
/// verbs only; the current page's card beside the rail has no floating card to act on and
/// keeps the presentation item. Region and zoom entries appear behind the
/// `app.floatingTabs.regionsEnabled` flag.
nonisolated enum PageActionsMenuPlan {
    /// The surface that shows the menu.
    enum Host: Sendable {
        /// A floating card, whose header toggles compact and preview in place.
        case floatingCard
        /// The current page's card beside the rail.
        case pageCard
        /// A row of the recent list, for a page without a place.
        case recentList
    }

    /// Everything the menu's contents depend on.
    struct Context: Sendable {
        var host: Host
        var isCurrentPage = false
        var hasPage = false
        var isReaderActive = false
        var canUpdateSavedAddress = false
        var isCompact = true
        var isPinned = false
        var hasRegion = false
        var regionsEnabled = false
        var canGroup = false
        var isSelectedForGroup = false
        var selectionCount = 0
        var canShowInEverySpace = false
        var showsInEverySpace = false
    }

    enum Entry: Equatable, Sendable {
        case copyAddress
        case copyMarkdownLink
        case share
        case findOnPage
        case reader
        case updateSavedAddress
        case look
        case divider
        case keepVisible
        case presentation
        case region
        case previewZoom
        case selectForGroup
        case groupSelectedTabs
        case showInEverySpace
        case duplicateTab
        case closeTab
    }

    /// The menu's entries for `context`, with a divider between each pair of groups that have entries.
    static func entries(for context: Context) -> [Entry] {
        var page: [Entry] = [.copyAddress, .copyMarkdownLink, .share]
        if context.isCurrentPage, context.hasPage {
            page += [.findOnPage, .reader]
        }
        if context.canUpdateSavedAddress {
            page.append(.updateSavedAddress)
        }
        if !context.isCurrentPage {
            page.append(.look)
        }

        var presentation: [Entry] = [.keepVisible]
        if context.host != .floatingCard {
            presentation.append(.presentation)
        }
        if context.regionsEnabled {
            presentation.append(.region)
            if context.hasRegion {
                presentation.append(.previewZoom)
            }
        }

        var grouping: [Entry] = []
        if context.canGroup {
            grouping.append(.selectForGroup)
            if context.selectionCount > 1 {
                grouping.append(.groupSelectedTabs)
            }
        }
        if context.canShowInEverySpace {
            grouping.append(.showInEverySpace)
        }

        let tab: [Entry] = [.duplicateTab, .closeTab]
        return Array([page, presentation, grouping, tab].filter { !$0.isEmpty }.joined(separator: [.divider]))
    }

    /// The titles of `entries(for:)`, with `"─"` standing for a divider.
    static func titles(for context: Context) -> [String] {
        entries(for: context).map { title(of: $0, in: context) }
    }

    static func title(of entry: Entry, in context: Context) -> String {
        switch entry {
        case .copyAddress: "Copy Address"
        case .copyMarkdownLink: "Copy as Markdown Link"
        case .share: "Share…"
        case .findOnPage: "Find on Page…"
        case .reader: context.isReaderActive ? "Leave Reader" : "Reader"
        case .updateSavedAddress: "Update Saved Address"
        case .look: PageVisitState.lookActionTitle
        case .divider: "─"
        case .keepVisible: context.isPinned ? "Hide Preview" : "Keep Visible"
        case .presentation: context.isCompact ? "Show as Preview" : "Show as Compact Tab"
        case .region: context.hasRegion ? "Adjust Region…" : "Keep Part Visible… (Experimental)"
        case .previewZoom: "Preview Zoom"
        case .selectForGroup: context.isSelectedForGroup ? "Deselect for Group" : "Select for Group"
        case .groupSelectedTabs: "Group Selected Tabs"
        case .showInEverySpace: context.showsInEverySpace ? "Show in This Space" : "Show in Every Space"
        case .duplicateTab: "Duplicate Tab"
        case .closeTab: "Close Tab"
        }
    }
}
