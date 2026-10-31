import AppKit
import Observation
import WebKit

/// What an extension's toolbar action shows for one tab, or for every tab without its own
/// values: the title, the badge, and whether it can be clicked.
nonisolated struct ExtensionActionAppearance: Equatable, Sendable {
    var label: String
    var badgeText: String
    var isEnabled: Bool
    /// The badge changed since the user last saw the action, which WebKit tracks per action.
    var hasUnreadBadgeText: Bool
}

/// The last known appearance of every extension's action, per tab and as the default, as
/// WebKit reports them through `didUpdate`.
///
/// WebKit resolves a tab's action against the default itself, so each record is the action
/// as that tab shows it. A tab without a record shows the default.
nonisolated struct ExtensionActionBoard: Equatable, Sendable {
    /// Identifies an action: its extension context, and the tab page whose action it is,
    /// `nil` for the default action.
    struct Key: Hashable, Sendable {
        let contextID: String
        let tabPageID: UUID?
    }

    private var appearances: [Key: ExtensionActionAppearance] = [:]

    init() {}

    /// Records `appearance` for the action `key` names.
    mutating func record(_ appearance: ExtensionActionAppearance, for key: Key) {
        appearances[key] = appearance
    }

    /// The appearance of `contextID`'s action in `tabPageID`: the tab's own, else the default.
    func appearance(contextID: String, tabPageID: UUID?) -> ExtensionActionAppearance? {
        tabPageID.flatMap { appearances[Key(contextID: contextID, tabPageID: $0)] }
            ?? appearances[Key(contextID: contextID, tabPageID: nil)]
    }

    /// The tab pages that have an action of their own for `contextID`.
    func tabPageIDs(withActionsFor contextID: String) -> [UUID] {
        appearances.keys.compactMap { $0.contextID == contextID ? $0.tabPageID : nil }
    }

    /// Whether any of `contextIDs` shows a badge the user has not seen in `tabPageID`.
    func hasUnreadBadge(among contextIDs: some Sequence<String>, tabPageID: UUID?) -> Bool {
        contextIDs.contains { contextID in
            guard let appearance = appearance(contextID: contextID, tabPageID: tabPageID) else { return false }
            return appearance.hasUnreadBadgeText && !appearance.badgeText.isEmpty
        }
    }

    /// Marks the badges of `contextIDs` in `tabPageID` as seen.
    mutating func markRead(_ contextIDs: some Sequence<String>, tabPageID: UUID?) {
        for contextID in contextIDs {
            let key = tabPageID.map { Key(contextID: contextID, tabPageID: $0) }
                .flatMap { appearances[$0] == nil ? nil : $0 }
                ?? Key(contextID: contextID, tabPageID: nil)
            appearances[key]?.hasUnreadBadgeText = false
        }
    }

    /// Forgets a closed tab page's actions.
    mutating func removeTabPage(_ tabPageID: UUID) {
        appearances = appearances.filter { $0.key.tabPageID != tabPageID }
    }

    /// Forgets an unloaded context's actions.
    mutating func removeContext(_ contextID: String) {
        appearances = appearances.filter { $0.key.contextID != contextID }
    }
}

/// An extension action as the rail and the page menu list it.
struct ExtensionActionEntry: Identifiable {
    /// The extension context's unique identifier.
    let id: String
    let name: String
    let icon: NSImage?
    let appearance: ExtensionActionAppearance
}

/// Keeps every extension action's appearance current for the UI, and remembers where the
/// user clicked an action so its popup opens there.
@Observable
final class ExtensionActionStore {
    private(set) var board = ExtensionActionBoard()
    /// Action icons, per action, at ``iconSize``.
    @ObservationIgnored private var icons: [ExtensionActionBoard.Key: NSImage] = [:]
    /// Bumped when an icon changes, so views reading icons redraw.
    private(set) var iconRevision = 0

    /// Where the next popup opens: the control that performed the action, in its window.
    @ObservationIgnored var pendingPopupAnchor: ActionPopupAnchor?

    static let iconSize = CGSize(width: 32, height: 32)

    /// Takes in an action WebKit reports changed.
    func update(from action: WKWebExtension.Action) {
        guard let context = action.webExtensionContext else { return }
        let tabPageID = (action.associatedTab as? RefraxExtensionTab)?.tabPage?.id
        if action.associatedTab != nil, tabPageID == nil {
            return
        }
        let key = ExtensionActionBoard.Key(contextID: context.uniqueIdentifier, tabPageID: tabPageID)
        board.record(Self.appearance(of: action), for: key)
        icons[key] = action.icon(for: Self.iconSize)
        iconRevision += 1

        // A default action's change shows through in every tab without its own value.
        if tabPageID == nil {
            for tabPageID in board.tabPageIDs(withActionsFor: context.uniqueIdentifier) {
                guard let tab = context.openTabs.lazy.compactMap({ $0.base as? RefraxExtensionTab })
                    .first(where: { $0.tabPage?.id == tabPageID }),
                    let tabAction = context.action(for: tab) else { continue }
                let tabKey = ExtensionActionBoard.Key(contextID: context.uniqueIdentifier, tabPageID: tabPageID)
                board.record(Self.appearance(of: tabAction), for: tabKey)
                icons[tabKey] = tabAction.icon(for: Self.iconSize)
            }
        }
    }

    /// Records a newly loaded context's default action, before it first changes.
    func refresh(_ context: WKWebExtensionContext) {
        guard let action = context.action(for: nil) else { return }
        update(from: action)
    }

    func icon(contextID: String, tabPageID: UUID?) -> NSImage? {
        _ = iconRevision
        return tabPageID.flatMap { icons[.init(contextID: contextID, tabPageID: $0)] }
            ?? icons[.init(contextID: contextID, tabPageID: nil)]
    }

    /// Marks the badges of `contexts` in `tabPage` seen, here and in WebKit.
    func markRead(_ contexts: [WKWebExtensionContext], tab: RefraxExtensionTab?) {
        for context in contexts {
            context.action(for: tab)?.hasUnreadBadgeText = false
        }
        board.markRead(contexts.map(\.uniqueIdentifier), tabPageID: tab?.tabPage?.id)
    }

    func removeTabPage(_ tabPageID: UUID) {
        board.removeTabPage(tabPageID)
        icons = icons.filter { $0.key.tabPageID != tabPageID }
    }

    func removeContext(_ contextID: String) {
        board.removeContext(contextID)
        icons = icons.filter { $0.key.contextID != contextID }
    }

    static func appearance(of action: WKWebExtension.Action) -> ExtensionActionAppearance {
        ExtensionActionAppearance(
            label: action.label,
            badgeText: action.badgeText,
            isEnabled: action.isEnabled,
            hasUnreadBadgeText: action.hasUnreadBadgeText,
        )
    }
}

/// The control an action was performed from, in SwiftUI's global coordinates of its window.
struct ActionPopupAnchor {
    weak var window: NSWindow?
    let rect: CGRect
}
