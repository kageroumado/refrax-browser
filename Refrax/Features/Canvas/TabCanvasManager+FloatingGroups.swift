import AppKit
import SwiftUI

/// A group on the floating layer: its placed cards, its nested groups, and its outline.
struct FloatingGroupItem: Identifiable {
    let group: TabGroup
    /// Placed cards directly in the group.
    let members: [Tab]
    /// Nested groups, one level deep.
    let children: [FloatingGroupItem]
    /// The outline around the members and nested outlines, folded or not.
    let outline: CGRect
    let depth: Int

    var id: UUID {
        group.id
    }

    var isFolded: Bool {
        group.isCollapsed
    }

    /// Every placed card in the group and its nested groups.
    var allMembers: [Tab] {
        members + children.flatMap(\.allMembers)
    }
}

// MARK: - Groups on the Floating Layer

extension TabCanvasManager {
    /// The unfold and fold motion: the v3 Unfold timing, or a fade alone under Reduce Motion.
    static var foldAnimation: Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .easeInOut(duration: 0.28) : .snappy(duration: 0.28)
    }

    /// The active space's groups that hold placed cards, roots first, each with its nested groups.
    func floatingGroupItems(in area: CGRect) -> [FloatingGroupItem] {
        guard let space = windowState.activeSpace else { return [] }
        let placed = floatingTabs.filter {
            $0.space?.id == space.id && $0.group != nil && storedFloatingPlacement(for: $0).map { !$0.isDocked } == true
        }
        let byGroup = Dictionary(grouping: placed) { $0.group!.id }
        let groups = space.groups.filter { !$0.isArchive && displaysAsGroup($0) }

        func item(for group: TabGroup, depth: Int) -> FloatingGroupItem? {
            let members = byGroup[group.id] ?? []
            let children = depth == 0 ? groups.filter { $0.parentGroupID == group.id }
                .sorted { $0.createdAt < $1.createdAt }
                .compactMap { item(for: $0, depth: 1) } : []
            let frames = members.map { floatingFrame(for: $0, in: area) } + children.map(\.outline)
            guard let outline = FloatingGroupLayout.outlineFrame(around: frames, in: area) else { return nil }
            return FloatingGroupItem(group: group, members: members, children: children, outline: outline, depth: depth)
        }

        return groups.filter { $0.parentGroupID == nil }
            .sorted { $0.createdAt < $1.createdAt }
            .compactMap { item(for: $0, depth: 0) }
    }

    /// Roots, then each root's nested groups, in drawing order.
    func flattenedFloatingGroupItems(in area: CGRect) -> [FloatingGroupItem] {
        floatingGroupItems(in: area).flatMap { [$0] + $0.children }
    }

    /// The header's frame for `item`, as wide as the layer last drew it.
    func headerFrame(for item: FloatingGroupItem) -> CGRect {
        let width = floatingHeaderWidths[item.id] ?? FloatingGroupLayout.nominalHeaderWidth
        return item.isFolded
            ? FloatingGroupLayout.foldedHeaderFrame(in: item.outline, width: width)
            : FloatingGroupLayout.headerFrame(in: item.outline, width: width)
    }

    /// A site stack holding one tab draws as that tab's card.
    func displaysAsGroup(_ group: TabGroup) -> Bool {
        group.stackSite == nil || group.tabs.count(where: { !$0.isArchived }) > 1
    }

    /// Whether `tab` sits in a folded group, or in a group nested in one.
    func isFolded(_ tab: Tab) -> Bool {
        guard let group = tab.group, displaysAsGroup(group) else { return false }
        if group.isCollapsed {
            return true
        }
        guard let parentID = group.parentGroupID else { return false }
        return group.space?.groups.first { $0.id == parentID }?.isCollapsed == true
    }

    /// The header a grouped card folds into and unfolds from.
    func foldOrigin(for tab: Tab, in area: CGRect) -> CGPoint? {
        guard let groupID = tab.group?.id else { return nil }
        let items = flattenedFloatingGroupItems(in: area)
        guard var item = items.first(where: { $0.id == groupID }) else { return nil }
        if let parent = items.first(where: { $0.children.contains { $0.id == groupID } }), parent.isFolded {
            item = parent
        }
        return headerFrame(for: item).origin
    }

    // MARK: Folding

    /// Folds or unfolds `group`; with `everyGroup`, every group in its space follows it.
    func toggleFold(_ group: TabGroup, everyGroup: Bool = false) {
        let unfolding = group.isCollapsed
        withAnimation(Self.foldAnimation) {
            if everyGroup {
                if unfolding {
                    for each in group.space?.groups ?? [] where each.isCollapsed {
                        fanOutPile(of: each)
                    }
                    groupManager.expandAllGroups(in: group.space)
                } else {
                    groupManager.collapseAllGroups(in: group.space)
                }
            } else {
                if unfolding {
                    fanOutPile(of: group)
                }
                groupManager.toggleGroupCollapsed(group)
            }
        }
    }

    /// Spreads cards left in one pile by Stacks by Site so they unfold side by side.
    private func fanOutPile(of group: TabGroup) {
        let area = floatingArea
        let members = group.sortedTabs.filter { storedFloatingPlacement(for: $0) != nil }
        let frames = members.map { floatingPlacement(for: $0).frame(in: area) }
        guard FloatingGroupLayout.isPiled(frames), let first = frames.first else { return }
        let origins = FloatingGroupLayout.fanOrigins(count: members.count, size: first.size, from: first.origin, in: area)
        for (tab, origin) in zip(members, origins) {
            var placement = floatingPlacement(for: tab)
            placement.move(to: origin, in: area)
            updateFloatingPlacement(placement, for: tab)
        }
    }

    // MARK: Membership

    /// Groups the selected cards of this space, and opens the new group's name for editing.
    func groupFloatingSelection() {
        let members = floatingTabs.filter { selectedFloatingTabIDs.contains($0.id) && !$0.isFavorite && $0.space?.id == windowState.activeSpaceID }
        guard members.count > 1, let group = try? groupManager.createGroup(in: windowState.activeSpace, name: "Group", color: Self.nextGroupColor()) else { return }
        for tab in members {
            groupManager.moveTabToGroup(tab, group: group, in: windowState.activeSpace)
        }
        selectedFloatingTabIDs = []
        beginRenaming(group)
    }

    /// Shows the group's name field in its header, keeping the layer up while the name is typed.
    func beginRenaming(_ group: TabGroup) {
        latchFloatingTabs()
        floatingRenamingGroupID = group.id
    }

    func renameFloatingGroup(_ group: TabGroup, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        floatingRenamingGroupID = nil
        guard !name.isEmpty, name != group.name else { return }
        groupManager.renameGroup(group, to: name)
    }

    /// Adds `tabs` to `group`. A card from outside the floating layer gets a place below the group.
    func addToFloatingGroup(_ tabs: [Tab], group: TabGroup) {
        let area = floatingArea
        let outline = floatingGroupItems(in: area).flatMap { [$0] + $0.children }.first { $0.id == group.id }?.outline
        for tab in tabs where tab.group?.id != group.id && !tab.isFavorite {
            groupManager.moveTabToGroup(tab, group: group, in: group.space)
            if storedFloatingPlacement(for: tab) == nil, let outline {
                var placement = floatingPlacement(for: tab)
                placement.move(to: CGPoint(x: outline.minX + FloatingGroupLayout.cardPadding, y: outline.maxY + FloatingArrangement.gap), in: area)
                updateFloatingPlacement(placement, for: tab)
            }
        }
        dissolveLoneSiteStacks()
    }

    /// Every tab in `group` and its nested groups.
    func allTabs(in group: TabGroup) -> [Tab] {
        let nested = group.space?.groups.filter { $0.parentGroupID == group.id } ?? []
        return (group.sortedTabs + nested.flatMap(\.sortedTabs)).filter { !$0.isArchived }
    }

    // MARK: Drop Targets

    /// The groups a card can be dropped into: unfolded outlines and folded headers.
    func floatingDropTargets(in area: CGRect) -> [(id: UUID, frame: CGRect)] {
        flattenedFloatingGroupItems(in: area).map { item in
            (id: item.id, frame: item.isFolded ? headerFrame(for: item) : item.outline)
        }
    }

    /// Marks the group under `point` as the target for `tabs` being dragged.
    func updateFloatingDropTarget(at point: CGPoint, dragging tabs: [Tab], in area: CGRect) {
        let ownGroups = Set(tabs.compactMap(\.group?.id))
        let target = FloatingGroupLayout.dropTarget(at: point, among: floatingDropTargets(in: area).filter { !ownGroups.contains($0.id) })
        if floatingDropGroupID != target {
            floatingDropGroupID = target
        }
        let card = target == nil ? floatingCardDropTarget(at: point, dragging: tabs, in: area) : nil
        if floatingDropCardID != card {
            floatingDropCardID = card
        }
    }

    /// Adds `tabs` to the marked target, if any, and clears the mark.
    func dropIntoTarget(_ tabs: [Tab]) {
        defer { floatingDropGroupID = nil }
        if let cardID = floatingDropCardID, let card = floatingTabs.first(where: { $0.id == cardID }) {
            groupFloatingCard(card, with: tabs)
            return
        }
        guard let targetID = floatingDropGroupID,
              let group = windowState.activeSpace?.groups.first(where: { $0.id == targetID }) else { return }
        addToFloatingGroup(tabs.filter { $0.space?.id == group.space?.id }, group: group)
    }

    /// Joins the group or forms one with the loose card under `point`, for a card dropped from Recent.
    func joinGroup(at point: CGPoint, tabs: [Tab], in area: CGRect) {
        updateFloatingDropTarget(at: point, dragging: tabs, in: area)
        dropIntoTarget(tabs)
    }

    // MARK: Moving Cards Together

    /// The cards a drag on `tab` moves: the whole selection when the card is part of it.
    func cardsMoved(with tab: Tab) -> [Tab] {
        guard selectedFloatingTabIDs.contains(tab.id) else { return [tab] }
        return visibleFloatingTabs.filter { selectedFloatingTabIDs.contains($0.id) }
    }

    /// Moves `tabs` by `translation` from where they were when the move began, keeping their
    /// relative positions and the whole set inside `area`.
    func moveFloatingTabs(_ tabs: [Tab], by translation: CGSize, in area: CGRect) {
        if floatingMoveOrigins.isEmpty {
            floatingMoveOrigins = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, floatingPlacement(for: $0).frame(in: area).origin) })
            floatingMoveBounds = tabs.map { floatingPlacement(for: $0).frame(in: area) }.reduce(CGRect.null) { $0.union($1) }
            beginFloatingManipulation()
        }
        let delta = floatingMoveBounds.map { FloatingArrangement.clampedTranslation(translation, moving: $0, in: area) } ?? translation
        for tab in tabs {
            guard let origin = floatingMoveOrigins[tab.id] else { continue }
            var placement = floatingPlacement(for: tab)
            placement.move(to: CGPoint(x: origin.x + delta.width, y: origin.y + delta.height), in: area)
            updateFloatingPlacement(placement, for: tab)
        }
    }

    func endFloatingMove() {
        floatingMoveOrigins = [:]
        floatingMoveBounds = nil
        endFloatingManipulation()
    }

    /// Follows a drag on a card's header: the card, or its selection, moves, and the group under
    /// the pointer becomes the drop target, or the window side under it the dock target.
    func dragFloatingCard(_ tab: Tab, translation: CGSize, pointer: CGPoint, in area: CGRect) {
        let moving = cardsMoved(with: tab)
        moveFloatingTabs(moving, by: translation, in: area)
        updateFloatingDropTarget(at: pointer, dragging: moving, in: area)
        updateDockTarget(at: pointer, dragging: moving, in: area)
    }

    func endFloatingCardDrag(_ tab: Tab) {
        if dockDraggedCard(tab) {
            return
        }
        let moving = cardsMoved(with: tab)
        endFloatingMove()
        dropIntoTarget(moving)
        confirmFloatingPlacement()
    }

    /// Follows a drag on a group's header: the group moves, and a root group with no nested
    /// groups of its own can nest in the group under the pointer.
    func dragFloatingGroup(_ item: FloatingGroupItem, translation: CGSize, pointer: CGPoint, in area: CGRect) {
        moveFloatingTabs(item.allMembers, by: translation, in: area)
        guard item.depth == 0, item.children.isEmpty else { return }
        let target = FloatingGroupLayout.dropTarget(
            at: pointer,
            among: floatingGroupItems(in: area).filter { $0.id != item.id && !$0.isFolded }.map { (id: $0.id, frame: $0.outline) },
        )
        if floatingDropGroupID != target {
            floatingDropGroupID = target
        }
    }

    func endFloatingGroupDrag(_ item: FloatingGroupItem) {
        endFloatingMove()
        defer { floatingDropGroupID = nil }
        guard let targetID = floatingDropGroupID,
              let parent = item.group.space?.groups.first(where: { $0.id == targetID }) else { return }
        try? groupManager.nestGroup(item.group, in: parent)
    }

    // MARK: Lasso and Selection

    /// Selects every card of this space the lasso could catch.
    func selectAllFloatingTabs() {
        selectedFloatingTabIDs = Set(floatingLassoCandidates.map(\.id))
    }

    private var floatingLassoCandidates: [Tab] {
        visibleFloatingTabs.filter { !$0.isFavorite && $0.space?.id == windowState.activeSpaceID && $0.id != windowState.activeTabID }
    }

    /// The floating layer takes a ⇧-drag on empty page area while it is revealed.
    var isFloatingLassoArmed: Bool {
        floatingVisibility.isRevealed && NSEvent.modifierFlags.contains(.shift)
    }

    /// Selects the cards a released lasso encircles; an empty catch clears the selection.
    func finishFloatingLasso(_ lasso: LassoSelection, in area: CGRect) {
        selectedFloatingTabIDs = lasso.caught(floatingLassoCandidates.map { (id: $0.id, frame: floatingFrame(for: $0, in: area)) })
    }

    var selectedFloatingTabs: [Tab] {
        floatingTabs.filter { selectedFloatingTabIDs.contains($0.id) }
    }

    /// The selected cards' bounds, while any of them shows.
    func floatingSelectionBounds(in area: CGRect) -> CGRect? {
        let frames = visibleFloatingTabs.filter { selectedFloatingTabIDs.contains($0.id) }.map { floatingFrame(for: $0, in: area) }
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }

    func closeFloatingSelection() {
        let closing = selectedFloatingTabs
        selectedFloatingTabIDs = []
        tabManager.requestCloseTabs(closing)
    }

    func moveFloatingSelection(to space: Space) {
        let moving = selectedFloatingTabs.filter { !$0.isFavorite }
        selectedFloatingTabIDs = []
        tabManager.moveTabs(moving, to: space, confirmingIn: windowState)
    }

    /// Spaces a tab or group in the active space can move to.
    var otherSpaces: [Space] {
        tabManager.state.spaces.filter { $0.id != windowState.activeSpaceID && !tabManager.state.spaceLockManager.requiresAuth(for: $0) }
    }

    // MARK: Hit Regions

    /// The floating layer's own controls: group headers, the selection capsule, and the whole
    /// layer while a lasso can start.
    func floatingControlRegions(in bounds: CGRect) -> [CGRect] {
        guard floatingVisibility.isRevealed else { return [] }
        if isFloatingLassoArmed {
            return [bounds]
        }
        var regions = flattenedFloatingGroupItems(in: bounds).map { headerFrame(for: $0) }
        if !selectedFloatingTabIDs.isEmpty, !floatingSelectionCapsuleFrame.isEmpty {
            regions.append(floatingSelectionCapsuleFrame)
        }
        return regions
    }

    /// Everywhere the floating layer takes the pointer: its controls, its cards, and the docked columns.
    func floatingHitRegions(in bounds: CGRect) -> [CGRect] {
        floatingControlRegions(in: bounds) + visibleFloatingTabs.map { floatingHitFrame(for: $0, in: bounds) } + dockHitRegions(in: bounds)
    }
}
