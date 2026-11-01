import AppKit
import SwiftUI

/// Islands and their chrome share the page window's glass backdrop with the browser controls.
/// Detached live pages are presented by ``TabCardPresenter``.
struct IslandsLayer: View {
    @Environment(IslandController.self) private var islands
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(WindowState.self) private var windowState
    @Environment(BrowserSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Layout {
        static let areaInset: CGFloat = 16
    }

    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            GlassEffectContainer {
                ZStack(alignment: .topLeading) {
                    FloatingDockLayer(area: bounds)
                    ForEach(islands.visibleIslands) { island in
                        let frame = islands.fullFrame(of: island)
                        IslandView(island: island)
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                    }
                    if let ghost = islands.islandGhost {
                        IslandGhostView(ghost: ghost)
                            .frame(width: ghost.frame.width, height: ghost.frame.height)
                            .offset(x: ghost.frame.minX, y: ghost.frame.minY)
                            .zIndex(5)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                    if let ghost = islands.rowGhost, let tab = islands.tab(for: ghost.tabID) {
                        VStack(spacing: 4) {
                            RowGhostView(tab: tab)
                            if islands.drop?.joins != nil {
                                DragWord("Combine into split view")
                            } else if islands.dropsAsCard {
                                DragWord("Drop to open as a card")
                            } else if islands.drop != nil, islands.actionTabs(for: ghost.tabID).count > 1 {
                                DragWord("Moving \(islands.actionTabs(for: ghost.tabID).count) tabs")
                            }
                        }
                        .position(ghost.point)
                        .zIndex(6)
                        .allowsHitTesting(false)
                    }
                    if let origin = islands.filterBadgeOrigin(size: IslandFilterBadge.Layout.size, gap: IslandFilterBadge.Layout.gap) {
                        IslandFilterBadge()
                            .frame(height: IslandFilterBadge.Layout.size.height)
                            .offset(x: origin.x, y: origin.y)
                            .zIndex(4)
                            .transition(.opacity)
                    }
                    if let island = islands.startHintIsland {
                        let origin = IslandDropPlacement.hintOrigin(
                            beside: islands.fullFrame(of: island), size: IslandStartHint.Layout.size, gap: IslandStartHint.Layout.gap, in: bounds,
                        )
                        IslandStartHint()
                            .frame(height: IslandStartHint.Layout.size.height)
                            .offset(x: origin.x, y: origin.y)
                            .zIndex(4)
                            .transition(.opacity)
                    }
                    if let placement = islands.sideDrop, let tab = islands.currentTab {
                        PaneDropZone(placement: placement, tab: tab, session: windowState.paneEditor.session, page: islands.pageArea)
                            .transition(.opacity)
                    }
                    if let tabID = islands.previewedTabID, let tab = islands.tab(for: tabID),
                       let island = islands.visibleIslands.first(where: { $0.allTabIDs.contains(tabID) }) {
                        RowPreview(tab: tab, islandFrame: islands.frame(of: island), bounds: bounds)
                            .zIndex(5)
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.15), value: islands.sideDrop)
                .animation(.easeOut(duration: 0.15), value: islands.islandGhost == nil)
                .animation(.easeOut(duration: 0.2), value: islands.startHintIsland?.id)
                .animation(.easeOut(duration: 0.15), value: islands.filter)
                .animation(.easeOut(duration: 0.15), value: islands.previewedTabID)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .coordinateSpace(name: "islands")
                .coordinateSpace(name: "floatingTabs")
            }
            .onChange(of: geometry.size, initial: true) {
                islands.updateArea(bounds.insetBy(dx: Layout.areaInset, dy: Layout.areaInset), in: bounds)
            }
        }
        .windowContainerShape()
        .ignoresSafeArea()
        .environment(\.colorScheme, settings.theme.colorScheme ?? colorScheme)
        .onChange(of: windowState.activeSpaceID) { canvas.floatingSpaceChanged() }
        .onChange(of: windowState.isSpaceLocked) { canvas.dismissFloatingTabs() }
        .onChange(of: windowState.showsCommandLens) { _, shown in
            if shown {
                canvas.dismissFloatingTabs()
            }
        }
    }
}

/// An island in the browser glass layer: the header with its name and controls above, a glass column of
/// tab rows below. Both surfaces move the island. The header is always laid out, so the
/// island keeps its size. Latched and pinned islands keep it visible; other headers follow
/// pointer interaction.
struct IslandView: View {
    let island: Island

    @Environment(IslandController.self) private var islands
    @Environment(WindowState.self) private var windowState

    private var geometry: IslandGeometry {
        islands.geometry(for: island)
    }

    var body: some View {
        let shape = WindowCorner.concentric
        let frame = islands.frame(of: island)
        let fullFrame = islands.fullFrame(of: island)
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: IslandGeometry.headerGap) {
                IslandHeader(island: island)
                    .frame(width: fullFrame.width, height: IslandGeometry.headerHeight)
                rows
                    .padding(.vertical, IslandGeometry.padding)
                    .padding(.horizontal, geometry.horizontalPadding)
                    .frame(width: frame.width, height: frame.height, alignment: .top)
                    .clipShape(shape)
                    // Links, files, text, and rows from other windows land on the row under the pointer.
                    .onDrop(of: IslandPasteboard.dropTypes, delegate: IslandDropDelegate(islandID: island.id, islands: islands))
                    // Empty glass moves the island within the browser.
                    .background {
                        IslandDragSurface(islandID: island.id)
                    }
                    // The Control Island's glass: the window's tint under regular glass, the same
                    // on every island; the rows inside are concentric with the island's corner.
                    .windowGlassSurface(tint: windowState.controlIslandTint)
                    .containerShape(.rect(cornerRadius: WindowCorner.radius))
                    .overlay(alignment: .topLeading) {
                        if let drop = islands.drop, drop.island == island.id, drop.joins == nil {
                            Capsule()
                                .fill(Color.appAccentColor)
                                .frame(width: frame.width - 2 * geometry.horizontalPadding, height: IslandGeometry.insertionLineHeight)
                                .offset(x: geometry.horizontalPadding, y: IslandGeometry.padding + CGFloat(drop.row) * geometry.cellHeight - (islands.scrollOffsets[island.id] ?? 0))
                                .allowsHitTesting(false)
                        }
                    }
                    .offset(x: frame.minX - fullFrame.minX)
            }
            .frame(width: fullFrame.width, height: fullFrame.height, alignment: .bottomLeading)
        }
        .onHover { islands.setHovered(island.id, $0) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(island.title), \(island.tabIDs.count) tabs")
        .accessibilityIdentifier("island-\(island.id.uuidString)")
        .accessibilityAction(named: island.placement.isPinned ? "Unpin" : "Pin") { islands.togglePin(island.id) }
        .accessibilityAction(named: "Move left") { nudge(dx: -Layout.nudge, dy: 0) }
        .accessibilityAction(named: "Move right") { nudge(dx: Layout.nudge, dy: 0) }
        .accessibilityAction(named: "Move up") { nudge(dx: 0, dy: -Layout.nudge) }
        .accessibilityAction(named: "Move down") { nudge(dx: 0, dy: Layout.nudge) }
    }

    private enum Layout {
        static let nudge: CGFloat = 40
    }

    private func nudge(dx: CGFloat, dy: CGFloat) {
        let origin = islands.frame(of: island).origin
        islands.moveIsland(island.id, to: CGPoint(x: origin.x + dx, y: origin.y + dy))
        islands.endIslandMove(keeping: island.id)
    }

    /// The rows in the tab list's order; past the window's share of height they scroll, and
    /// then only the rows in view are built.
    @ViewBuilder
    private var rows: some View {
        let list = ForEach(Array(island.rows.enumerated()), id: \.element.id) { index, row in
            switch row {
            case let .tab(tabID):
                if let tab = islands.tab(for: tabID) {
                    IslandTabRow(tab: tab, island: island, index: index, area: islands.bounds)
                        .frame(height: geometry.cellHeight)
                }
            case let .section(sectionID):
                if let section = island.layout.section(sectionID) {
                    IslandSectionRow(section: section, island: island, index: index)
                        .frame(height: geometry.cellHeight)
                }
            }
        }
        if geometry.contentHeight(rows: island.rows.count) > islands.frame(of: island).height + 0.5 {
            ScrollViewReader { reader in
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        list
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .scrollIndicators(.visible)
                .scrollIndicatorsFlash(onAppear: true)
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, offset in
                    islands.scrollOffsets[island.id] = offset
                    if let ghost = islands.rowGhost {
                        islands.updateRowDrag(ghost.tabID, at: ghost.point)
                    }
                }
                .onChange(of: windowState.activeTabID) { revealCurrentRow(using: reader) }
                .onChange(of: islands.keyboardCursorID) { _, cursor in
                    if let cursor {
                        reveal(cursor, using: reader)
                    }
                }
                .onChange(of: islands.isRevealed, initial: true) { revealCurrentRow(using: reader) }
                .task(id: islands.draggedTabID) { await scrollDuringDrag(using: reader) }
            }
        } else {
            VStack(spacing: 0) {
                list
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func revealCurrentRow(using reader: ScrollViewProxy) {
        guard let id = windowState.activeTabID else { return }
        reveal(id, using: reader)
    }

    /// Scrolls `id`'s row into view when it is on this island and out of sight.
    private func reveal(_ id: UUID, using reader: ScrollViewProxy) {
        guard let index = island.layout.row(of: id) else { return }
        let offset = islands.scrollOffsets[island.id] ?? 0
        let row = geometry.rowFrame(index)
        let height = islands.frame(of: island).height - 2 * IslandGeometry.padding
        if row.minY < offset || row.maxY > offset + height {
            reader.scrollTo(id, anchor: .center)
        }
    }

    private func scrollDuringDrag(using reader: ScrollViewProxy) async {
        guard islands.draggedTabID != nil else { return }
        while !Task.isCancelled, islands.draggedTabID != nil {
            if let point = islands.rowGhost?.point {
                let frame = islands.frame(of: island)
                if point.x >= frame.minX, point.x <= frame.maxX {
                    let offset = islands.scrollOffsets[island.id] ?? 0
                    let reach = geometry.cellHeight
                    if point.y >= frame.minY, point.y < frame.minY + reach {
                        let index = max(0, Int(offset / reach) - 1)
                        reader.scrollTo(island.rows[index].id, anchor: .top)
                    } else if point.y <= frame.maxY, point.y > frame.maxY - reach {
                        let index = min(island.rows.count - 1, Int((offset + frame.height) / reach))
                        reader.scrollTo(island.rows[index].id, anchor: .bottom)
                    }
                }
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}

/// A row on its way: its icon and title in a capsule at the pointer, over the page.
private struct RowGhostView: View {
    let tab: Tab

    private enum Layout {
        static let faviconSize: CGFloat = 16
        static let width: CGFloat = 200
        static let height: CGFloat = 30
    }

    var body: some View {
        HStack(spacing: 8) {
            FaviconView(data: tab.activePage.faviconData, url: tab.activePage.url, size: Layout.faviconSize)
            Text(tab.displayTitle)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(width: Layout.width, height: Layout.height)
        .glassEffect(.regular, in: .capsule)
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .accessibilityHidden(true)
    }
}

/// The word under a traveling row on what a drop does.
private struct DragWord: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: .capsule)
    }
}

/// The island a dragged row is about to make, drawn where it will land: a header with the
/// name it will take, a column with room for its rows, both outlined in the accent, and the
/// word on what a drop does under it. The row's ghost travels in its first row.
private struct IslandGhostView: View {
    let ghost: IslandGhost

    private enum Layout {
        static let fill: Double = 0.08
        static let stroke: Double = 0.5
        static let dash: [CGFloat] = [5, 4]
        static let wordGap: CGFloat = 8
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: IslandGeometry.cornerRadius, style: .continuous)
        VStack(alignment: .leading, spacing: IslandGeometry.headerGap) {
            HStack {
                if !ghost.iconsOnly {
                    Text(ghost.title)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.leading, 14)
                }
                Spacer(minLength: 0)
            }
            .frame(width: ghost.frame.width, height: IslandGeometry.headerHeight)
            .background(outline(shape))
            outline(shape)
                .frame(width: ghost.frame.width, height: ghost.frame.height - IslandGeometry.headerReserve)
        }
        .overlay(alignment: .top) {
            Text(ghost.rows > 1 ? "Drop to make an island of \(ghost.rows) tabs" : "Drop to make an island")
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: .capsule)
                .fixedSize()
                .offset(y: ghost.frame.height + Layout.wordGap)
        }
        .accessibilityHidden(true)
    }

    private func outline(_ shape: RoundedRectangle) -> some View {
        shape
            .fill(Color.appAccentColor.opacity(Layout.fill))
            .overlay {
                shape
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: Layout.dash))
                    .foregroundStyle(Color.appAccentColor.opacity(Layout.stroke))
                    .padding(0.5)
            }
    }
}

/// The one-time word beside the loose tabs' island, while a space has no other island: how
/// to start one. Its close puts it away for good; so does the first island.
struct IslandStartHint: View {
    @Environment(IslandController.self) private var islands

    enum Layout {
        /// The room the hint is placed with; the capsule itself takes its text's width.
        static let size = CGSize(width: 250, height: 28)
        static let gap: CGFloat = 10
    }

    var body: some View {
        HStack(spacing: 6) {
            Text("Drag a tab here to start an island")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Button {
                islands.dismissStartHint()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.default)
            .help("Don't show this again")
            .accessibilityLabel("Dismiss hint")
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: Layout.size.height)
        .fixedSize()
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Drag a tab here to start an island")
    }
}

/// The quick filter on the islands, beside them while it is on: what it shows, or that it
/// matches nothing, and a button that brings every tab back.
struct IslandFilterBadge: View {
    @Environment(IslandController.self) private var islands

    enum Layout {
        /// The room the badge is placed with; the capsule itself takes its text's width.
        static let size = CGSize(width: 260, height: 28)
        static let gap: CGFloat = 10
        static let glyphSize: CGFloat = 10
    }

    var body: some View {
        if let filter = islands.filter {
            let text = islands.visibleIslands.isEmpty ? filter.emptyDescription : filter.description
            HStack(spacing: 6) {
                Image(systemName: filter.symbol)
                    .font(.system(size: Layout.glyphSize))
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.caption)
                    .lineLimit(1)
                Button("Show All") {
                    islands.setFilter(nil)
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.appAccentColor)
                .pointerStyle(.default)
                // The badge comes and goes with the filter: kept out of the key-view loop, whose
                // rebuild beside the page's views can spin forever.
                .focusable(false)
                .help("Show every tab")
            }
            .padding(.horizontal, 12)
            .frame(height: Layout.size.height)
            .fixedSize()
            .glassEffect(.regular, in: .capsule)
            // Its drawn size is where the layer takes its clicks.
            .onGeometryChange(for: CGSize.self) { $0.size } action: { islands.filterBadgeSize = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(text)
        }
    }
}

/// One tab as a row: its favicon with the loading ring, its title, its state, and under the
/// pointer its close. A click opens the page; a drag moves the row within its island, into
/// another, or, let go on empty space, out as a new island of its own (a live card with ⇧).
/// Its menu is the page's.
private struct IslandTabRow: View, Equatable {
    let tab: Tab
    let island: Island
    /// The row's place in the island, for the gap a drag opens.
    let index: Int
    let area: CGRect

    /// The row re-renders only when what it draws from its inputs has changed: the island
    /// moving under a drag leaves every row alone.
    static func == (lhs: IslandTabRow, rhs: IslandTabRow) -> Bool {
        lhs.tab.id == rhs.tab.id && lhs.island.id == rhs.island.id && lhs.index == rhs.index
            && lhs.island.placement.iconsOnly == rhs.island.placement.iconsOnly && lhs.island.rows == rhs.island.rows
            && lhs.island.colorString == rhs.island.colorString && lhs.area == rhs.area
    }

    @Environment(IslandController.self) private var islands
    @Environment(WindowState.self) private var windowState
    @Environment(TabManager.self) private var tabManager
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(\.colorScheme) private var colorScheme
    @Environment(BookmarksManager.self) private var bookmarks
    @Environment(SharingCoordinator.self) private var sharing
    @State private var isHovering = false

    private enum Layout {
        static let faviconSize: CGFloat = 16
        /// A split tab's panes, overlapping in the icon's slot.
        static let paneFaviconSize: CGFloat = 11
        static let closeSize: CGFloat = 20
        /// How present the row is while its ghost travels.
        static let draggedOpacity: Double = 0.35
        static let previewDelay: Duration = .milliseconds(650)
        static let ringSize: CGFloat = 20
    }

    private var isCurrent: Bool {
        tab.id == windowState.activeTabID
    }

    private var iconsOnly: Bool {
        island.placement.iconsOnly
    }

    private var color: Color {
        islands.color(of: island)
    }

    /// Another row is held over this one: it would join this tab as a second pane.
    private var isJoinTarget: Bool {
        islands.drop?.joins == tab.id
    }

    private var isSelected: Bool {
        islands.selectedTabIDs.contains(tab.id)
    }

    /// The row is a tab of a group nested in the island's, drawn indented under its header.
    private var isInSection: Bool {
        !iconsOnly && island.layout.section(of: tab.id) != nil
    }

    /// The keyboard has chosen this row while the islands are latched open.
    private var isKeyboardChoice: Bool {
        islands.keyboardCursorID == tab.id && canvas.floatingVisibility.isLatched
    }

    /// How far the row moves while another is dragged: the rows below the lifted one close
    /// its hole, and the rows at and past the drop row open a gap for it.
    private var shift: CGFloat {
        guard let dragged = islands.draggedTabID, dragged != tab.id, let drop = islands.drop, drop.island == island.id, drop.joins == nil else { return 0 }
        var target = index
        if let lifted = island.layout.row(of: dragged), lifted < index {
            target -= 1
        }
        if target >= drop.row {
            target += 1
        }
        return CGFloat(target - index) * islands.geometry(for: island).cellHeight
    }

    private var rowFill: Color {
        if isJoinTarget {
            return Color.appAccentColor.opacity(0.2)
        }
        if isSelected {
            return Color.appAccentColor.opacity(0.16)
        }
        // The current row is white, a lit surface on the glass, in any tint the window has.
        if isCurrent {
            return Color.white.opacity(colorScheme == .dark ? 0.16 : 0.7)
        }
        return Color.primary.opacity(isHovering ? 0.08 : 0)
    }

    var body: some View {
        let shape = ConcentricRectangle(corners: .concentric(minimum: .fixed(IslandGeometry.rowCornerRadius)), isUniform: true)
        HStack(spacing: 8) {
            pages
            if !iconsOnly {
                FloatingTabTitle(tab: tab, weight: isCurrent ? .semibold : .regular)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.primary) : AnyShapeStyle(.primary.opacity(0.85)))
                if tab.pages.count > 1 {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .help("\(tab.pages.count) pages side by side")
                }
                Spacer(minLength: 0)
                TabStateSymbols(tab: tab)
                if isHovering {
                    Button {
                        tabManager.requestCloseTab(tab)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: Layout.closeSize, height: Layout.closeSize)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // Shown under the pointer only, so kept out of the key-view loop.
                    .focusable(false)
                    .help("Close Tab")
                }
            }
        }
        .padding(.horizontal, iconsOnly ? 0 : 8)
        .padding(.leading, isInSection ? IslandSectionRow.Layout.indent : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: iconsOnly ? .center : .leading)
        .background(rowFill, in: shape)
        // A section's rows hang from its header on a thin guide.
        .overlay(alignment: .leading) {
            if isInSection {
                Rectangle()
                    .fill(.separator)
                    .frame(width: 1)
                    .padding(.vertical, 3)
                    .offset(x: IslandSectionRow.Layout.guideOffset)
                    .allowsHitTesting(false)
            }
        }
        .offset(y: shift)
        .animation(.snappy(duration: 0.2), value: islands.drop)
        .overlay {
            if isJoinTarget {
                shape.stroke(Color.appAccentColor, lineWidth: 1.5).padding(0.75)
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appAccentColor)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 8)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isJoinTarget)
        // The keyboard's choice wears a focus ring, apart from the current row's fill.
        .overlay {
            if isKeyboardChoice {
                shape.stroke(Color.appAccentColor, lineWidth: 2).padding(1)
            }
        }
        .contentShape(shape)
        .opacity(islands.draggedTabID == tab.id ? Layout.draggedOpacity : 1)
        .onHover { hovering in
            isHovering = hovering
            if !hovering, islands.previewedTabID == tab.id {
                islands.previewedTabID = nil
            }
        }
        // The page shows beside the island once the pointer has rested on the row.
        .task(id: isHovering) {
            guard isHovering else { return }
            try? await Task.sleep(for: Layout.previewDelay)
            guard !Task.isCancelled, isHovering, islands.draggedTabID == nil else { return }
            islands.requestStoredSnapshot(for: tab)
            islands.previewedTabID = tab.id
        }
        .onTapGesture {
            let flags = NSEvent.modifierFlags
            if flags.contains(.command) || flags.contains(.shift) {
                islands.select(tab.id, extending: flags.contains(.shift), toggling: flags.contains(.command))
            } else {
                islands.clearSelection()
                islands.open(tab)
            }
        }
        .highPriorityGesture(dragGesture, including: canvas.renamingTabID == tab.id ? .subviews : .all)
        .contextMenu { MenuTreeView(tree: menuTree) }
        .closesOnMiddleClick(tab)
        .help(iconsOnly ? tab.displayTitle : "")
        // One element per row: the label and actions on a container that isn't an element land
        // on each of its children, which listed every row twice. Close and the rest are actions.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.displayTitle)
        .accessibilityIdentifier("island-row-\(tab.id.uuidString)")
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { islands.open(tab) }
        .accessibilityAction(named: "Close") { tabManager.requestCloseTab(tab) }
        .accessibilityAction(named: "Open as Card") { islands.detach(tab.id, at: CGPoint(x: area.midX, y: area.midY)) }
        .accessibilityAction(named: "New Island with This Tab") { islands.makeIsland(from: tab.id) }
        .accessibilityAction(named: "Move Up") { moveRow(by: -1) }
        .accessibilityAction(named: "Move Down") { moveRow(by: 1) }
        .accessibilityAction(named: "Join with Row Above") { joinNeighbor(offset: -1) }
        .accessibilityAction(named: "Select") { islands.select(tab.id, extending: false, toggling: true) }
    }

    /// Moves the row one place up or down its island.
    private func moveRow(by offset: Int) {
        guard let index = island.layout.row(of: tab.id) else { return }
        // Rows are counted without this one: down goes after the next row, up before the previous.
        let rows = island.rows.count - 1
        islands.moveTab(tab.id, to: offset > 0 ? min(index + 1, rows) : max(0, index - 1), in: island.id)
    }

    /// Joins this row's tab to its neighbor's as a pane.
    private func joinNeighbor(offset: Int) {
        guard let index = island.tabIDs.firstIndex(of: tab.id), island.tabIDs.indices.contains(index + offset) else { return }
        islands.join(tab.id, with: island.tabIDs[index + offset])
    }

    /// The tab's page as its favicon with the loading ring; a tab of two pages shows both,
    /// the two panes side by side in small.
    /// The row's icon, in the one slot every row keeps: a split tab's two panes share it, the
    /// left pane's icon at the top leading corner and the right pane's over it at the bottom
    /// trailing, each with its own corners.
    @ViewBuilder
    private var pages: some View {
        if tab.pages.count > 1 {
            let panes = Array(tab.pages.sorted { ($0.position ?? .single).sortOrder < ($1.position ?? .single).sortOrder }.prefix(2))
            ZStack {
                ForEach(Array(panes.enumerated()), id: \.element.id) { index, page in
                    FaviconView(data: page.faviconData, url: page.url, size: Layout.paneFaviconSize)
                        .frame(width: Layout.faviconSize, height: Layout.faviconSize, alignment: index == 0 ? .topLeading : .bottomTrailing)
                }
            }
            .frame(width: Layout.faviconSize, height: Layout.faviconSize)
            .overlay { TabLoadingRing(tab: tab, size: Layout.ringSize) }
        } else {
            FaviconView(data: tab.activePage.faviconData, url: tab.activePage.url, size: Layout.faviconSize)
                .overlay { TabLoadingRing(tab: tab, size: Layout.ringSize) }
        }
    }

    /// The page's actions and the tab's, with a rename that edits the row's title in place
    /// and the island this row can leave for.
    private var menuTree: MenuTree {
        IslandRowMenu(
            tab: tab, island: island, islands: islands, windowState: windowState, tabs: tabManager, bookmarks: bookmarks, canvas: canvas,
            sharing: sharing, area: area, onRename: { canvas.renamingTabID = tab.id },
        ).tree()
    }

    /// Where the row would land while it is dragged, and what happens when it is let go. The
    /// row's ghost travels over the page; the row itself stays, dimmed, in its window. ⇧ held
    /// at the drop opens the row as a card instead of a new island. Past the window's edge
    /// the drag leaves the browser, carrying the page's address and a `.webloc`.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("islands"))
            .onChanged { value in
                switch islands.rowDragExit(tab.id, at: value.location) {
                case .inside:
                    islands.updateRowDrag(tab.id, at: value.location, asCard: NSEvent.modifierFlags.contains(.shift))
                case let .leaves(tabs):
                    // Past the window's edge the row goes on as a system drag, to Finder or any app.
                    guard let view = windowState.window?.contentView, let event = NSApp.currentEvent,
                          IslandRowDragOut.begin(tabs, from: view, event: event, islands: islands) else {
                        islands.endDragOut()
                        return
                    }
                case .handedOff:
                    break
                }
            }
            .onEnded { value in
                islands.finishRowDrag(tab.id, at: value.location, asCard: NSEvent.modifierFlags.contains(.shift))
            }
    }
}

/// A row's page beside its island while the pointer rests on the row: the newest render of
/// it, with its title, on the side with room.
private struct RowPreview: View {
    let tab: Tab
    let islandFrame: CGRect
    let bounds: CGRect

    @Environment(IslandController.self) private var islands

    private enum Layout {
        static let size = CGSize(width: 240, height: 150)
        static let gap: CGFloat = 10
        static let padding: CGFloat = 6
        static let cornerRadius = WindowCorner.radius
    }

    var body: some View {
        let width = Layout.size.width + 2 * Layout.padding
        let height = Layout.size.height + 2 * Layout.padding + 22
        let right = islandFrame.maxX + Layout.gap
        let x = right + width <= bounds.maxX ? right : islandFrame.minX - Layout.gap - width
        let y = min(max(bounds.minY, islandFrame.minY), bounds.maxY - height)
        let shape = RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
        VStack(spacing: 4) {
            Group {
                if let image = islands.snapshot(for: tab.id) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    PagePlaceholder(tab: tab)
                }
            }
            .frame(width: Layout.size.width, height: Layout.size.height)
            .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius - Layout.padding, style: .continuous))
            Text(tab.displayTitle)
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        }
        .padding(Layout.padding)
        .glassEffect(.regular, in: shape)
        .shadow(color: .black.opacity(0.14), radius: 12, y: 6)
        .frame(width: width, height: height)
        .offset(x: x, y: y)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A page with nothing to show yet: its favicon (32 pt) and title on the window's tinted
/// background.
struct PagePlaceholder: View {
    let tab: Tab

    @Environment(WindowState.self) private var windowState

    private enum Layout {
        static let spacing: CGFloat = 10
        static let faviconSize: CGFloat = 32
        static let titleWidthFraction: CGFloat = 0.8
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: Layout.spacing) {
                favicon
                Text(tab.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: geometry.size.width * Layout.titleWidthFraction)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(windowState.controlIslandTint)
        .background(.regularMaterial)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var favicon: some View {
        if let data = tab.activePage.faviconData, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFit().frame(width: Layout.faviconSize, height: Layout.faviconSize)
        } else {
            Image(systemName: "globe")
                .font(.system(size: Layout.faviconSize * 0.75))
                .foregroundStyle(.secondary)
                .frame(width: Layout.faviconSize, height: Layout.faviconSize)
        }
    }
}
