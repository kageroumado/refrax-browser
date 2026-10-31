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

    /// The appearance recorded under exactly `key`.
    func appearance(of key: Key) -> ExtensionActionAppearance? {
        appearances[key]
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
///
/// Observation is per action: a view that reads one tab's actions redraws when one of those
/// changes, not when uBlock Origin's badge counts another tab's blocked requests. An update
/// that changes nothing visible changes nothing observed. Icons are drawn when read.
@Observable
final class ExtensionActionStore {
    /// One action's observable revision, bumped when its appearance or icon changes.
    @Observable
    final class Slot {
        fileprivate(set) var revision = 0
        /// The action, for its icon.
        @ObservationIgnored fileprivate weak var action: WKWebExtension.Action?
        @ObservationIgnored fileprivate var icon: NSImage?
        @ObservationIgnored fileprivate var iconIsCurrent = false
    }

    /// The appearances, read through the slots so readers observe them.
    @ObservationIgnored private var board = ExtensionActionBoard()
    private var slots: [ExtensionActionBoard.Key: Slot] = [:]

    /// Where the next popup of each context opens: the control that performed its action, in
    /// its window. Keyed by context identifier.
    @ObservationIgnored var pendingPopupAnchors: [String: ActionPopupAnchor] = [:]

    static let iconSize = CGSize(width: 32, height: 32)

    /// Takes in an action WebKit reports changed.
    func update(from action: WKWebExtension.Action) {
        guard let context = action.webExtensionContext else { return }
        let tabPageID = (action.associatedTab as? RefraxExtensionTab)?.tabPage?.id
        if action.associatedTab != nil, tabPageID == nil {
            return
        }
        record(action, key: .init(contextID: context.uniqueIdentifier, tabPageID: tabPageID))

        // A default action's change shows through in every tab without its own value.
        if tabPageID == nil {
            for tabPageID in board.tabPageIDs(withActionsFor: context.uniqueIdentifier) {
                guard let tab = context.openTabs.lazy.compactMap({ $0.base as? RefraxExtensionTab })
                    .first(where: { $0.tabPage?.id == tabPageID }),
                    let tabAction = context.action(for: tab)
                else { continue }
                record(tabAction, key: .init(contextID: context.uniqueIdentifier, tabPageID: tabPageID))
            }
        }
    }

    /// Records `action` under `key`. WebKit reports icon changes through the same callback as
    /// the rest, so each update also marks the icon for redrawing on its next read.
    private func record(_ action: WKWebExtension.Action, key: ExtensionActionBoard.Key) {
        let appearance = Self.appearance(of: action)
        let slot = slots[key] ?? {
            let slot = Slot()
            slots[key] = slot
            return slot
        }()
        slot.action = action
        slot.iconIsCurrent = false
        if board.appearance(of: key) != appearance {
            board.record(appearance, for: key)
        }
        slot.revision += 1
    }

    /// Records a newly loaded context's default action, before it first changes.
    func refresh(_ context: WKWebExtensionContext) {
        guard let action = context.action(for: nil) else { return }
        update(from: action)
    }

    /// The appearance of `contextID`'s action in `tabPageID`: the tab's own, else the default.
    func appearance(contextID: String, tabPageID: UUID?) -> ExtensionActionAppearance? {
        observe(contextID: contextID, tabPageID: tabPageID)
        return board.appearance(contextID: contextID, tabPageID: tabPageID)
    }

    /// Whether any of `contextIDs` shows a badge the user has not seen in `tabPageID`.
    func hasUnreadBadge(among contextIDs: [String], tabPageID: UUID?) -> Bool {
        for contextID in contextIDs {
            observe(contextID: contextID, tabPageID: tabPageID)
        }
        return board.hasUnreadBadge(among: contextIDs, tabPageID: tabPageID)
    }

    /// The icon `contextID`'s action shows in `tabPageID`, drawn on first read after a change.
    func icon(contextID: String, tabPageID: UUID?) -> NSImage? {
        let key = tabPageID.map { ExtensionActionBoard.Key(contextID: contextID, tabPageID: $0) }
            .flatMap { slots[$0] == nil ? nil : $0 } ?? ExtensionActionBoard.Key(contextID: contextID, tabPageID: nil)
        guard let slot = slots[key] else { return nil }
        _ = slot.revision
        if !slot.iconIsCurrent {
            slot.icon = slot.action?.icon(for: Self.iconSize)
            slot.iconIsCurrent = true
        }
        return slot.icon
    }

    /// Marks the badges of `contexts` in `tab` seen, here and in WebKit.
    func markRead(_ contexts: [WKWebExtensionContext], tab: RefraxExtensionTab?) {
        let tabPageID = tab?.tabPage?.id
        for context in contexts {
            context.action(for: tab)?.hasUnreadBadgeText = false
        }
        let before = contexts.map { board.appearance(contextID: $0.uniqueIdentifier, tabPageID: tabPageID) }
        board.markRead(contexts.map(\.uniqueIdentifier), tabPageID: tabPageID)
        for (context, previous) in zip(contexts, before)
            where board.appearance(contextID: context.uniqueIdentifier, tabPageID: tabPageID) != previous {
            slot(contextID: context.uniqueIdentifier, tabPageID: tabPageID)?.revision += 1
        }
    }

    func removeTabPage(_ tabPageID: UUID) {
        board.removeTabPage(tabPageID)
        if slots.keys.contains(where: { $0.tabPageID == tabPageID }) {
            slots = slots.filter { $0.key.tabPageID != tabPageID }
        }
    }

    func removeContext(_ contextID: String) {
        board.removeContext(contextID)
        pendingPopupAnchors[contextID] = nil
        if slots.keys.contains(where: { $0.contextID == contextID }) {
            slots = slots.filter { $0.key.contextID != contextID }
        }
    }

    /// Registers the reader on the slots `appearance(contextID:tabPageID:)` reads from.
    private func observe(contextID: String, tabPageID: UUID?) {
        if let tabPageID {
            _ = slots[.init(contextID: contextID, tabPageID: tabPageID)]?.revision
        }
        _ = slots[.init(contextID: contextID, tabPageID: nil)]?.revision
    }

    /// The slot whose appearance `tabPageID` shows for `contextID`.
    private func slot(contextID: String, tabPageID: UUID?) -> Slot? {
        tabPageID.flatMap { slots[.init(contextID: contextID, tabPageID: $0)] } ?? slots[.init(contextID: contextID, tabPageID: nil)]
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
