import CoreGraphics
import Foundation

nonisolated extension FloatingGroupLayout {
    /// The loose card a card dropped at `point` forms a group with: the topmost of `cards`,
    /// listed bottom to top, whose frame holds the point.
    static func cardDropTarget<ID>(at point: CGPoint, among cards: [(id: ID, frame: CGRect)]) -> ID? {
        cards.last { $0.frame.contains(point) }?.id
    }

    /// The nearest loose card beside a moved card, with the narrow seam that will connect them.
    static func adjacentCardDropTarget<ID>(beside moving: CGRect, among cards: [(id: ID, frame: CGRect)]) -> (id: ID, bridge: CGRect)? {
        let maximumGap: CGFloat = 24
        let bridgeThickness: CGFloat = 4
        let candidates = cards.compactMap { card -> (id: ID, bridge: CGRect, gap: CGFloat, offset: CGFloat)? in
            let frame = card.frame
            let horizontalOverlap = min(moving.maxY, frame.maxY) - max(moving.minY, frame.minY)
            let verticalOverlap = min(moving.maxX, frame.maxX) - max(moving.minX, frame.minX)
            let horizontalGap = max(frame.minX - moving.maxX, moving.minX - frame.maxX)
            let verticalGap = max(frame.minY - moving.maxY, moving.minY - frame.maxY)
            if horizontalGap >= 0, horizontalGap <= maximumGap,
               horizontalOverlap >= min(moving.height, frame.height) / 2 {
                let centerY = (max(moving.minY, frame.minY) + min(moving.maxY, frame.maxY)) / 2
                let bridge = CGRect(x: min(moving.maxX, frame.maxX), y: centerY - bridgeThickness / 2,
                                    width: horizontalGap, height: bridgeThickness)
                return (card.id, bridge, horizontalGap, abs(moving.midY - frame.midY))
            }
            if verticalGap >= 0, verticalGap <= maximumGap,
               verticalOverlap >= min(moving.width, frame.width) / 2 {
                let centerX = (max(moving.minX, frame.minX) + min(moving.maxX, frame.maxX)) / 2
                let bridge = CGRect(x: centerX - bridgeThickness / 2, y: min(moving.maxY, frame.maxY),
                                    width: bridgeThickness, height: verticalGap)
                return (card.id, bridge, verticalGap, abs(moving.midX - frame.midX))
            }
            return nil
        }
        return candidates.min { $0.gap == $1.gap ? $0.offset < $1.offset : $0.gap < $1.gap }
            .map { ($0.id, $0.bridge) }
    }
}

// MARK: - Grouping a Card onto a Card

extension TabCanvasManager {
    /// The loose card under `point` that `tabs` would group with: a card of this space, in no
    /// group, that is not one of `tabs`, while at least one of `tabs` can join a group.
    func floatingCardDropTarget(at point: CGPoint, dragging tabs: [Tab], in area: CGRect) -> Tab.ID? {
        FloatingGroupLayout.cardDropTarget(at: point, among: looseFloatingDropCards(excluding: tabs, in: area))
    }

    func floatingAdjacentCardDropTarget(dragging tabs: [Tab], in area: CGRect) -> (id: Tab.ID, bridge: CGRect)? {
        guard tabs.count == 1, let moving = tabs.first else { return nil }
        return FloatingGroupLayout.adjacentCardDropTarget(
            beside: floatingFrame(for: moving, in: area),
            among: looseFloatingDropCards(excluding: tabs, in: area),
        )
    }

    private func looseFloatingDropCards(excluding tabs: [Tab], in area: CGRect) -> [(id: Tab.ID, frame: CGRect)] {
        let moving = Set(tabs.map(\.id))
        guard tabs.contains(where: { !$0.isFavorite }) else { return [] }
        let cards = visibleFloatingTabs.filter {
            !moving.contains($0.id) && $0.group == nil && !$0.isFavorite
                && $0.space?.id == windowState.activeSpaceID && $0.id != windowState.activeTabID
        }
        return cards.map { (id: $0.id, frame: floatingFrame(for: $0, in: area)) }
    }

    /// Forms a new group of `card` and `tabs`, sets the cards together from `card`'s place,
    /// and opens the group's name for editing.
    func groupFloatingCard(_ card: Tab, with tabs: [Tab]) {
        guard let group = formFloatingGroup(card, with: tabs) else { return }
        arrangeFloatingGroupMembers(group, around: card)
        dissolveLoneSiteStacks()
        beginRenaming(group)
    }

    /// Connects cards placed side by side while retaining both positions on the table.
    func attachFloatingCard(_ card: Tab, with tabs: [Tab]) {
        guard formFloatingGroup(card, with: tabs) != nil else { return }
        dissolveLoneSiteStacks()
    }

    private func formFloatingGroup(_ card: Tab, with tabs: [Tab]) -> TabGroup? {
        let joining = tabs.filter { $0.id != card.id && !$0.isFavorite && $0.space?.id == card.space?.id }
        guard !joining.isEmpty,
              let group = try? groupManager.createGroup(in: card.space, name: "Group", color: Self.nextGroupColor()) else { return nil }
        for tab in [card] + joining {
            groupManager.moveTabToGroup(tab, group: group, in: card.space)
        }
        selectedFloatingTabIDs.subtract(joining.map(\.id))
        return group
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
