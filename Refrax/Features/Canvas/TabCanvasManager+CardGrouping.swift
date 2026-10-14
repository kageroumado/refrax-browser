import CoreGraphics
import Foundation

nonisolated extension FloatingGroupLayout {
    /// The loose card a card dropped at `point` forms a group with: the topmost of `cards`,
    /// listed bottom to top, whose frame holds the point.
    static func cardDropTarget<ID>(at point: CGPoint, among cards: [(id: ID, frame: CGRect)]) -> ID? {
        cards.last { $0.frame.contains(point) }?.id
    }
}

// MARK: - Grouping a Card onto a Card

extension TabCanvasManager {
    /// The loose card under `point` that `tabs` would group with: a card of this space, in no
    /// group, that is not one of `tabs`, while at least one of `tabs` can join a group.
    func floatingCardDropTarget(at point: CGPoint, dragging tabs: [Tab], in area: CGRect) -> Tab.ID? {
        let moving = Set(tabs.map(\.id))
        guard tabs.contains(where: { !$0.isFavorite }) else { return nil }
        let cards = visibleFloatingTabs.filter {
            !moving.contains($0.id) && $0.group == nil && !$0.isFavorite
                && $0.space?.id == windowState.activeSpaceID && $0.id != windowState.activeTabID
        }
        return FloatingGroupLayout.cardDropTarget(at: point, among: cards.map { (id: $0.id, frame: floatingFrame(for: $0, in: area)) })
    }

    /// Forms a new group of `card` and `tabs`, sets the cards together from `card`'s place,
    /// and opens the group's name for editing.
    func groupFloatingCard(_ card: Tab, with tabs: [Tab]) {
        let joining = tabs.filter { $0.id != card.id && !$0.isFavorite && $0.space?.id == card.space?.id }
        guard !joining.isEmpty,
              let group = try? groupManager.createGroup(in: card.space, name: "Group", color: Self.nextGroupColor()) else { return }
        for tab in [card] + joining {
            groupManager.moveTabToGroup(tab, group: group, in: card.space)
        }
        arrangeFloatingGroupMembers(group, around: card)
        selectedFloatingTabIDs.subtract(joining.map(\.id))
        dissolveLoneSiteStacks()
        beginRenaming(group)
    }

    /// Adds `tab` to `group` from a menu, and sets the group's cards together, so a card from
    /// across the window never stretches the group's outline over the page.
    func joinFloatingGroup(_ tab: Tab, group: TabGroup) {
        addToFloatingGroup([tab], group: group)
        guard tab.group?.id == group.id else { return }
        arrangeFloatingGroupMembers(group, around: group.sortedTabs.first { $0.id != tab.id && showsAsGroupCard($0) })
    }

    /// Lays `group`'s cards out together in rows under its header, from `anchor`'s place, or
    /// from the first shown member's, or from the first free cell beside the rail when none
    /// has a place yet.
    func arrangeFloatingGroupMembers(_ group: TabGroup, around anchor: Tab? = nil) {
        let area = floatingArea
        var members = group.sortedTabs.filter { showsAsGroupCard($0) }
        if let anchor, let index = members.firstIndex(where: { $0.id == anchor.id }) {
            members.insert(members.remove(at: index), at: 0)
        } else if let index = members.firstIndex(where: { storedFloatingPlacement(for: $0) != nil }) {
            members.insert(members.remove(at: index), at: 0)
        }
        guard let first = members.first else { return }
        let start: CGPoint
        if storedFloatingPlacement(for: first) != nil {
            start = floatingFrame(for: first, in: area).origin
        } else {
            let occupied = floatingTabs.filter { $0.group?.id != group.id && storedFloatingPlacement(for: $0) != nil }.map { floatingPlacement(for: $0) }
            guard let placement = startingPlacement(for: first, avoiding: occupied) else { return }
            start = placement.frame(in: area).origin
        }
        // The header sits above the first row; a row at the window's top would push it out.
        let origin = CGPoint(x: start.x, y: max(start.y, area.minY + FloatingGroupLayout.topPadding))
        let size = members.map { floatingFrame(for: $0, in: area).size }
            .reduce(CGSize.zero) { CGSize(width: max($0.width, $1.width), height: max($0.height, $1.height)) }
        let origins = FloatingGroupLayout.fanOrigins(count: members.count, size: size, from: origin, in: area)
        for (tab, origin) in zip(members, origins) {
            var placement = floatingPlacement(for: tab)
            placement.move(to: origin, in: area)
            updateFloatingPlacement(placement, for: tab)
        }
    }

    /// Whether `tab` shows as a card in its group: a page of this window that is neither the
    /// current page, shown as the page card, nor docked.
    private func showsAsGroupCard(_ tab: Tab) -> Bool {
        !tab.isArchived && !(showsFloatingControls && tab.id == windowState.activeTabID)
            && storedFloatingPlacement(for: tab)?.isDocked != true
            && !tabManager.isShownInAnotherWindow(tab, besides: windowState)
    }
}
