import AppKit
import SwiftUI

/// The islands over the page: each a glass column of the group's tabs, shown while the
/// reveal key is held or the island is pinned, and the tabs taken out of them, floating as
/// live cards.
struct IslandsLayer: View {
    @Environment(IslandController.self) private var islands
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(WindowState.self) private var windowState
    @Environment(BrowserSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Layout {
        static let areaInset: CGFloat = 16
        static let emergeScale: CGFloat = 0.6
    }

    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            ZStack(alignment: .topLeading) {
                FloatingDockLayer(area: bounds)
                ForEach(islands.visibleIslands) { island in
                    let frame = islands.frame(of: island)
                    IslandView(island: island, area: bounds)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .zIndex(zIndex(of: island))
                        .transition(reduceMotion ? .opacity : .scale(scale: Layout.emergeScale).combined(with: .opacity))
                }
                if let side = islands.sideDrop {
                    SideDropZone(side: side, bounds: bounds)
                        .transition(.opacity)
                }
                ForEach(islands.detachedTabs.filter { $0.id != windowState.activeTabID }) { tab in
                    let frame = canvas.floatingFrame(for: tab, in: bounds)
                    FloatingTabCard(tab: tab, placement: canvas.floatingPlacement(for: tab), area: bounds)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .zIndex(tab.id == canvas.focusedFloatingTabID ? 4 : 3)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: islands.visibleIslands.map(\.id))
            .animation(.easeOut(duration: 0.15), value: islands.sideDrop)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .coordinateSpace(name: "islands")
            .coordinateSpace(name: "floatingTabs")
            .onChange(of: geometry.size, initial: true) {
                islands.updateArea(bounds.insetBy(dx: Layout.areaInset, dy: Layout.areaInset), in: bounds)
            }
        }
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

    /// The island being moved is on top; the current tab's island above the rest.
    private func zIndex(of island: Island) -> Double {
        if islands.draggedIslandID == island.id { return 2 }
        return island.tabIDs.contains(windowState.activeTabID ?? UUID()) ? 1 : 0
    }
}

/// One island: a band with its color and, under the pointer, its controls, over a column of
/// the group's tabs as rows. Any of its empty glass moves it; its rows move themselves.
struct IslandView: View {
    let island: Island
    let area: CGRect

    @Environment(IslandController.self) private var islands
    @Environment(WindowState.self) private var windowState
    @State private var dragStart: CGPoint?
    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var draftName = ""
    @FocusState private var nameIsFocused: Bool

    private var geometry: IslandGeometry {
        islands.geometry(for: island)
    }

    private var color: Color {
        islands.color(of: island)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: IslandGeometry.cornerRadius, style: .continuous)
        let frame = islands.frame(of: island)
        VStack(spacing: 0) {
            band
                .frame(height: IslandGeometry.bandHeight)
            rows
        }
        .padding(IslandGeometry.padding)
        .frame(width: frame.width, height: frame.height, alignment: .top)
        .clipShape(shape)
        // The glass behind the rows takes the drag that moves the island: the open hand over
        // any empty space says so.
        .background {
            Color.clear
                .contentShape(shape)
                .pointerStyle(dragStart == nil ? .grabIdle : .grabActive)
                .gesture(moveGesture)
        }
        // The Control Island's glass: the window's tint under regular glass.
        .background(windowState.controlIslandTint, in: shape)
        .glassEffect(.regular, in: shape)
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(island.title), \(island.tabIDs.count) tabs")
    }

    /// The rows in the tab list's order; past the window's share of height they scroll.
    @ViewBuilder
    private var rows: some View {
        let column = VStack(spacing: 0) {
            ForEach(Array(island.tabIDs.enumerated()), id: \.element) { index, tabID in
                if let tab = islands.tab(for: tabID) {
                    IslandTabRow(tab: tab, island: island, area: area)
                        .frame(height: IslandGeometry.rowHeight)
                        .offset(y: shift(of: index, tabID: tabID))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .animation(.snappy(duration: 0.2), value: islands.drop)
        if geometry.contentHeight(rows: island.tabIDs.count) > islands.frame(of: island).height + 0.5 {
            ScrollView(.vertical, showsIndicators: false) {
                column
            }
        } else {
            column
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    /// How far a row moves while another is dragged: the rows below the lifted one close its
    /// hole, and the rows at and past the drop row open a gap for it.
    private func shift(of index: Int, tabID: UUID) -> CGFloat {
        guard let dragged = islands.draggedTabID, dragged != tabID, let drop = islands.drop, drop.island == island.id, drop.joins == nil else { return 0 }
        var target = index
        if let lifted = island.tabIDs.firstIndex(of: dragged), lifted < index {
            target -= 1
        }
        if target >= drop.row {
            target += 1
        }
        return CGFloat(target - index) * IslandGeometry.rowHeight
    }

    /// The drag that moves the island, from its origin when the drag began.
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("islands"))
            .onChanged { value in
                if dragStart == nil {
                    dragStart = islands.frame(of: island).origin
                    islands.draggedIslandID = island.id
                }
                if let dragStart {
                    islands.moveIsland(island.id, to: CGPoint(x: dragStart.x + value.translation.width, y: dragStart.y + value.translation.height))
                }
            }
            .onEnded { _ in
                dragStart = nil
                islands.draggedIslandID = nil
            }
    }

    /// The island's color and name, and under the pointer its pin and actions.
    private var band: some View {
        let showsControls = isHovered || island.placement.isPinned
        return HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            if !isRenaming, !island.placement.iconsOnly {
                Text(island.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        guard !island.isDefault else { return }
                        draftName = island.title
                        isRenaming = true
                        nameIsFocused = true
                    }
            }
            if isRenaming {
                TextField("Name", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .focused($nameIsFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { isRenaming = false }
                    .onChange(of: nameIsFocused) { _, focused in
                        if !focused { commitRename() }
                    }
            }
            Spacer(minLength: 0)
            if showsControls {
                Button {
                    islands.togglePin(island.id)
                } label: {
                    Image(systemName: island.placement.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .foregroundStyle(island.placement.isPinned ? AnyShapeStyle(color) : AnyShapeStyle(.tertiary))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointerStyle(.default)
                .help(island.placement.isPinned ? "Let the island go when ⌃ is up" : "Keep the island visible")
                Menu {
                    Button(island.placement.iconsOnly ? "Show Titles" : "Show Icons Only") { islands.toggleIconsOnly(island.id) }
                    if !island.isDefault {
                        Button("Rename…") {
                            draftName = island.title
                            isRenaming = true
                            nameIsFocused = true
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .pointerStyle(.default)
                .frame(width: 18, height: 18)
            }
        }
        .padding(.horizontal, 4)
        .animation(.easeInOut(duration: 0.15), value: showsControls)
        .accessibilityAddTraits(.isHeader)
    }

    private func commitRename() {
        guard isRenaming else { return }
        isRenaming = false
        islands.rename(island.id, to: draftName)
    }
}

/// One tab as a row: its favicon with the loading ring, its title, its state, and under the
/// pointer its close. A click opens the page; a drag moves the row within its island, into
/// another, or, let go on the page, out of its island as a live card. Its menu is the page's.
private struct IslandTabRow: View {
    let tab: Tab
    let island: Island
    let area: CGRect

    @Environment(IslandController.self) private var islands
    @Environment(WindowState.self) private var windowState
    @Environment(TabManager.self) private var tabManager
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(BookmarksManager.self) private var bookmarks
    @Environment(SharingCoordinator.self) private var sharing
    @State private var dragOffset: CGSize = .zero
    @State private var isHovering = false

    private enum Layout {
        static let faviconSize: CGFloat = 16
        static let paneFaviconSize: CGFloat = 12
        static let ringSize: CGFloat = 20
        /// How far past an island's edge a row still lands on it.
        static let reach: CGFloat = 12
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

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: IslandGeometry.rowCornerRadius, style: .continuous)
        HStack(spacing: 8) {
            pages
            if !iconsOnly {
                FloatingTabTitle(tab: tab)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.primary) : AnyShapeStyle(.primary.opacity(0.85)))
                Spacer(minLength: 0)
                TabStateSymbols(tab: tab)
                if isHovering {
                    Button {
                        tabManager.requestCloseTab(tab)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Close Tab")
                }
            }
        }
        .padding(.horizontal, iconsOnly ? 0 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: iconsOnly ? .center : .leading)
        .background(isJoinTarget ? Color.appAccentColor.opacity(0.2) : isCurrent ? color.opacity(0.28) : Color.primary.opacity(isHovering ? 0.08 : 0), in: shape)
        .overlay {
            if isJoinTarget {
                shape.strokeBorder(Color.appAccentColor, lineWidth: 1.5)
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.appAccentColor)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 8)
            }
        }
        .animation(.easeOut(duration: 0.12), value: isJoinTarget)
        .contentShape(shape)
        .offset(dragOffset)
        .zIndex(dragOffset == .zero ? 0 : 2)
        .onHover { isHovering = $0 }
        .onTapGesture { islands.open(tab) }
        .gesture(dragGesture)
        .contextMenu { MenuTreeView(tree: menuTree) }
        .closesOnMiddleClick(tab)
        .help(iconsOnly ? tab.displayTitle : "")
        .accessibilityLabel(tab.displayTitle)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { islands.open(tab) }
    }

    /// The tab's page as its favicon with the loading ring; a tab of two pages shows both,
    /// the two panes side by side in small.
    @ViewBuilder
    private var pages: some View {
        if tab.pages.count > 1 {
            HStack(spacing: 2) {
                ForEach(tab.pages.sorted { ($0.position ?? .single).sortOrder < ($1.position ?? .single).sortOrder }.prefix(2)) { page in
                    FaviconView(data: page.faviconData, url: page.url, size: Layout.paneFaviconSize)
                }
            }
            .frame(width: Layout.faviconSize + Layout.paneFaviconSize + 2, height: Layout.faviconSize)
            .overlay { TabLoadingRing(tab: tab, size: Layout.ringSize) }
        } else {
            FaviconView(data: tab.activePage.faviconData, url: tab.activePage.url, size: Layout.faviconSize)
                .overlay { TabLoadingRing(tab: tab, size: Layout.ringSize) }
        }
    }

    /// The page's actions and the tab's, with a rename that edits the row's title in place
    /// and the island this row can leave for.
    private var menuTree: MenuTree {
        let page = PageActions(tab: tab, windowState: windowState, tabs: tabManager, sharing: sharing)
        let object = TabActions(
            tab: tab, surface: .floatingCard, windowState: windowState, tabs: tabManager, bookmarks: bookmarks, canvas: canvas, area: area,
            onRename: { canvas.renamingTabID = tab.id },
        )
        let island = [
            MenuAction("island.new", "New Island from Here", symbol: "plus.rectangle.on.rectangle", group: .move) { islands.makeIsland(from: tab.id) },
            MenuAction("island.float", "Float as Live Page", symbol: "rectangle.on.rectangle", group: .move) {
                islands.detach(tab.id, at: CGPoint(x: area.midX, y: area.midY))
            },
        ]
        return MenuComposer.compose(page.actions() + object.actions() + island, groupOrder: PageActionsMenu.groupOrder)
    }

    /// Where the row would land while it is dragged, and what happens when it is let go.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("islands"))
            .onChanged { value in
                dragOffset = value.translation
                islands.draggedTabID = tab.id
                let point = value.location
                if let target = islands.visibleIslands.first(where: { islands.frame(of: $0).insetBy(dx: -Layout.reach, dy: -Layout.reach).contains(point) }) {
                    let frame = islands.frame(of: target)
                    let local = CGPoint(x: point.x - frame.minX, y: point.y - frame.minY)
                    let geometry = islands.geometry(for: target)
                    let count = target.tabIDs.filter { $0 != tab.id }.count
                    var drop = IslandDrop(island: target.id, row: geometry.insertion(at: local, count: count))
                    // On a row's middle the row joins that tab as its second pane.
                    if let hit = geometry.joinedRow(at: local, count: target.tabIDs.count), islands.canJoin(tab.id, with: target.tabIDs[hit]) {
                        drop.joins = target.tabIDs[hit]
                    }
                    if islands.drop != drop {
                        islands.drop = drop
                    }
                    if islands.sideDrop != nil {
                        islands.sideDrop = nil
                    }
                } else {
                    if islands.drop != nil {
                        islands.drop = nil
                    }
                    let side = islands.sideZone(at: point, dragging: tab.id)
                    if islands.sideDrop != side {
                        islands.sideDrop = side
                    }
                }
            }
            .onEnded { value in
                if let drop = islands.drop {
                    if let joins = drop.joins {
                        islands.join(tab.id, with: joins)
                    } else {
                        islands.moveTab(tab.id, to: drop.row, in: drop.island)
                    }
                } else if let side = islands.sideDrop {
                    islands.joinPage(tab.id, at: side)
                } else {
                    islands.detach(tab.id, at: value.location)
                }
                islands.drop = nil
                islands.sideDrop = nil
                islands.draggedTabID = nil
                dragOffset = .zero
            }
    }
}

/// The side of the page a dragged row would join the current tab on: the band lights up
/// with the split it makes.
private struct SideDropZone: View {
    let side: PanePosition
    let bounds: CGRect

    private enum Layout {
        static let inset: CGFloat = 12
        static let symbolSize: CGFloat = 30
    }

    var body: some View {
        let width = bounds.width * IslandController.Layout.sideZoneShare
        let zone = CGRect(x: side == .topLeft ? bounds.minX : bounds.maxX - width, y: bounds.minY, width: width, height: bounds.height)
            .insetBy(dx: Layout.inset, dy: Layout.inset)
        RoundedRectangle(cornerRadius: IslandGeometry.cornerRadius, style: .continuous)
            .fill(Color.appAccentColor.opacity(0.14))
            .overlay {
                RoundedRectangle(cornerRadius: IslandGeometry.cornerRadius, style: .continuous)
                    .strokeBorder(Color.appAccentColor.opacity(0.5), lineWidth: 1)
            }
            .overlay {
                Image(systemName: side == .topLeft ? "rectangle.lefthalf.inset.filled" : "rectangle.righthalf.inset.filled")
                    .font(.system(size: Layout.symbolSize, weight: .regular))
                    .foregroundStyle(Color.appAccentColor)
            }
            .frame(width: zone.width, height: zone.height)
            .offset(x: zone.minX, y: zone.minY)
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
