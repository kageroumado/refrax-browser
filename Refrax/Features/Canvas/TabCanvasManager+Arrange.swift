import AppKit
import SwiftUI

/// One thing Arrange places: a single card, or a whole group placed by its header or outline.
private struct ArrangedUnit {
    let tabs: [Tab]
    /// The frame Arrange aligns to the grid: the card, the folded header, or the outline.
    let frame: CGRect
    /// How far right and down from the frame's origin the unit's cards reach once placed.
    let reach: CGSize
    /// For a folded group, where its cards pile relative to the header's origin; `nil` moves
    /// the cards with the frame, keeping their places relative to it.
    let pileOffset: CGSize?
    let lastUsed: Date
}

// MARK: - Arrange

extension TabCanvasManager {
    /// Lays out the active space's floating layer, or only `selection` when one is given.
    ///
    /// Every arrangement ends in the grid, so stacks and loose cards line up in columns from the
    /// island's side, most recently used first. Stacks by Site turns the space's site stacks on;
    /// the others turn them off.
    func arrange(_ arrangement: FloatingArrangement, selection: [Tab]? = nil) {
        guard let space = windowState.activeSpace, !windowState.isSpaceLocked else { return }
        if !floatingVisibility.isRevealed {
            toggleFloatingTabs()
        }
        withAnimation(Self.foldAnimation) {
            switch arrangement {
            case .grid:
                space.stacksBySite = false
            case .stacksBySite:
                space.stacksBySite = true
                stackBySite(in: space, only: selection)
            case .stacksByGroup:
                space.stacksBySite = false
                let groups = selection.map { Set($0.compactMap(\.group?.id)) }
                for group in space.groups where !group.isArchive && !group.isCollapsed && (groups?.contains(group.id) ?? true) {
                    groupManager.toggleGroupCollapsed(group)
                }
            }
            dissolveLoneSiteStacks()
            layOutGrid(only: selection)
        }
        selectedFloatingTabIDs = []
        tabManager.state.scheduleSave()
    }

    /// Whether the active space keeps its cards in stacks by site.
    var stacksBySite: Bool {
        windowState.activeSpace?.stacksBySite == true
    }

    /// New tabs stop falling into site stacks; the stacks stay as they are.
    func stopStackingBySite() {
        windowState.activeSpace?.stacksBySite = false
        tabManager.state.scheduleSave()
    }

    // MARK: Grid

    private func layOutGrid(only selection: [Tab]?) {
        let bounds = floatingArea
        let units = arrangedUnits(in: bounds, only: selection).sorted { $0.lastUsed > $1.lastUsed }
        guard !units.isEmpty else { return }
        // The page card unfolds beside the rail while the layer shows, so cards line up past both.
        let controls = [windowState.controlIsland.railFrame, windowState.pageCardFrame].filter { !$0.isEmpty }
        let rail = showsFloatingControls ? controls.reduce(CGRect.null) { $0.union($1) } : .zero
        var area = FloatingArrangement.arrangeArea(in: bounds, rail: rail)
        var fromTrailing = FloatingArrangement.fillsFromTrailing(bounds: bounds, rail: rail)
        if selection != nil, let first = units.first?.frame {
            let start = units.dropFirst().reduce(first) { $0.union($1.frame) }.origin
            area = CGRect(x: start.x, y: start.y, width: max(1, area.maxX - start.x), height: max(1, area.maxY - start.y))
            fromTrailing = false
        }
        let origins = FloatingArrangement.gridOrigins(
            for: units.map(\.frame.size), reaching: units.map(\.reach), in: area, fromTrailing: fromTrailing,
        )
        for (unit, origin) in zip(units, origins) {
            let dx = origin.x - unit.frame.minX, dy = origin.y - unit.frame.minY
            for tab in unit.tabs {
                var placement = floatingPlacement(for: tab)
                let frame = placement.frame(in: bounds)
                let target = unit.pileOffset.map { CGPoint(x: origin.x + $0.width, y: origin.y + $0.height) }
                    ?? CGPoint(x: frame.minX + dx, y: frame.minY + dy)
                placement.move(to: target, in: bounds)
                updateFloatingPlacement(placement, for: tab)
            }
        }
    }

    /// The active space's placed cards as Arrange moves them: whole root groups, then loose cards.
    private func arrangedUnits(in bounds: CGRect, only selection: [Tab]?) -> [ArrangedUnit] {
        let chosen = selection.map { Set($0.map(\.id)) }
        func lastUsed(_ tabs: [Tab]) -> Date {
            tabs.map { $0.lastAccessed ?? $0.createdAt }.max() ?? .distantPast
        }
        var units: [ArrangedUnit] = []
        var grouped: Set<Tab.ID> = []
        for item in floatingGroupItems(in: bounds) {
            let members = item.allMembers
            grouped.formUnion(members.map(\.id))
            guard chosen.map({ chosen in members.contains { chosen.contains($0.id) } }) ?? true else { continue }
            if item.isFolded {
                units.append(foldedUnit(item, in: bounds, lastUsed: lastUsed(members)))
            } else if let outline = unclippedOutline(of: item, frame: { floatingFrame(for: $0, in: bounds) }) {
                units.append(ArrangedUnit(tabs: members, frame: outline, reach: outline.size, pileOffset: nil, lastUsed: lastUsed(members)))
            }
        }
        // The current page shows as the page card and a docked page in its column, so neither takes a cell.
        let loose = floatingTabs.filter {
            $0.space?.id == windowState.activeSpaceID && !grouped.contains($0.id) && storedFloatingPlacement(for: $0).map { !$0.isDocked } == true
                && !(showsFloatingControls && $0.id == windowState.activeTabID) && (chosen?.contains($0.id) ?? true)
        }
        units += loose.map {
            let frame = floatingFrame(for: $0, in: bounds)
            return ArrangedUnit(tabs: [$0], frame: frame, reach: frame.size, pileOffset: nil, lastUsed: lastUsed([$0]))
        }
        return units
    }

    /// A folded group placed by its header, its cards piled under the header so the header
    /// lands exactly on its cell whatever their sizes.
    private func foldedUnit(_ item: FloatingGroupItem, in bounds: CGRect, lastUsed: Date) -> ArrangedUnit {
        let size = { (tab: Tab) in self.floatingFrame(for: tab, in: bounds).size }
        let piled = unclippedOutline(of: item) { CGRect(origin: .zero, size: size($0)) } ?? .zero
        let width = floatingHeaderWidths[item.id] ?? FloatingGroupLayout.nominalHeaderWidth
        let header = FloatingGroupLayout.foldedHeaderFrame(in: piled, width: width)
        let cards = item.allMembers.map(size).reduce(CGSize.zero) { CGSize(width: max($0.width, $1.width), height: max($0.height, $1.height)) }
        return ArrangedUnit(
            tabs: item.allMembers,
            frame: header,
            reach: CGSize(width: cards.width - header.minX, height: cards.height - header.minY),
            pileOffset: CGSize(width: -header.minX, height: -header.minY),
            lastUsed: lastUsed,
        )
    }

    /// The outline around `item`'s cards at the frames `frame` gives, and around its nested
    /// groups', past the window's edges where they reach.
    private func unclippedOutline(of item: FloatingGroupItem, frame: (Tab) -> CGRect) -> CGRect? {
        let frames = item.members.map(frame) + item.children.compactMap { unclippedOutline(of: $0, frame: frame) }
        return FloatingGroupLayout.outlineFrame(around: frames, in: .infinite)
    }

    // MARK: Stacks by Site

    /// The site a card stacks under: its registrable domain.
    static func stackSite(for tab: Tab) -> String? {
        let url = tab.activePage.url
        guard let host = url.host(), !host.isEmpty else { return nil }
        return url.registrableDomain
    }

    /// Gathers loose cards and existing site stacks by site: each site with two or more cards
    /// becomes a folded stack named by the site, its cards piled under the header.
    private func stackBySite(in space: Space, only selection: [Tab]?) {
        let chosen = selection.map { Set($0.map(\.id)) }
        let candidates = floatingTabs.filter { tab in
            tab.space?.id == space.id && storedFloatingPlacement(for: tab) != nil && !tab.isFavorite
                && (tab.group == nil || tab.group?.stackSite != nil) && (chosen?.contains(tab.id) ?? true)
        }
        let stacks = FloatingArrangement.siteStacks(candidates.map { (id: $0.id, site: Self.stackSite(for: $0)) })
        let area = floatingArea
        for stack in stacks {
            let members = stack.ids.compactMap { id in candidates.first { $0.id == id } }
            guard let group = siteStack(for: stack.site, in: space) else { continue }
            for tab in members where tab.group?.id != group.id {
                groupManager.moveTabToGroup(tab, group: group, in: space)
            }
            group.isCollapsed = true
            let pile = members.map { floatingPlacement(for: $0).frame(in: area).origin }.first ?? .zero
            for tab in members {
                var placement = floatingPlacement(for: tab)
                placement.move(to: pile, in: area)
                updateFloatingPlacement(placement, for: tab)
            }
        }
    }

    /// The space's stack for `site`, made when there is none.
    private func siteStack(for site: String, in space: Space) -> TabGroup? {
        if let existing = space.groups.first(where: { $0.stackSite == site }) {
            return existing
        }
        guard let group = try? groupManager.createGroup(in: space, name: site, color: Self.nextGroupColor()) else { return nil }
        group.stackSite = site
        return group
    }

    /// Puts a loose card into its site's stack while the space keeps stacks by site, on top of
    /// the stack's pile.
    func fileIntoSiteStack(_ tab: Tab) {
        guard let space = tab.space, space.stacksBySite, space.id == windowState.activeSpaceID,
              tab.group == nil, !tab.isFavorite, let site = Self.stackSite(for: tab),
              let group = space.groups.first(where: { $0.stackSite == site }) else { return }
        let pile = group.sortedTabs.first { $0.id != tab.id && storedFloatingPlacement(for: $0) != nil }
        groupManager.moveTabToGroup(tab, group: group, in: space)
        guard let pile else { return }
        let area = floatingArea
        var placement = floatingPlacement(for: tab)
        placement.move(to: floatingPlacement(for: pile).frame(in: area).origin, in: area)
        updateFloatingPlacement(placement, for: tab)
    }

    /// Dissolves site stacks of the active space that hold one tab or none, so a lone card
    /// stands on its own.
    func dissolveLoneSiteStacks() {
        guard let space = windowState.activeSpace else { return }
        for group in space.groups where group.stackSite != nil && group.tabs.count(where: { !$0.isArchived }) <= 1 {
            for tab in group.tabs {
                groupManager.moveTabToGroup(tab, group: nil, in: space, skipReordering: true)
            }
            groupManager.deleteGroup(group, in: space)
        }
    }
}
