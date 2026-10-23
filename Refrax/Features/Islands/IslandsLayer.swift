import AppKit
import SwiftUI

/// The islands over the page: each a glass column of the group's tabs, shown while the
/// reveal key is held or the island is pinned. The tabs taken out of them are windows of
/// their own, kept by ``TabCardPresenter``.
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
            // One container for every glass sibling: islands, previews, and labels; their
            // corners are concentric with the window's.
            GlassEffectContainer {
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
                if let island = islands.controlsIsland {
                    let frame = islands.controlsFrame(for: island, in: bounds)
                    IslandControls(island: island, frame: frame)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .zIndex(3)
                        .transition(.opacity)
                        .id(island.id)
                }
                if let side = islands.sideDrop {
                    SideDropZone(side: side, bounds: bounds)
                        .transition(.opacity)
                }
                if let tabID = islands.previewedTabID, let tab = islands.tab(for: tabID), let island = islands.island(holding: tabID) {
                    RowPreview(tab: tab, islandFrame: islands.frame(of: island), bounds: bounds)
                        .zIndex(5)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: islands.visibleIslands.map(\.id))
            .animation(.easeOut(duration: 0.15), value: islands.sideDrop)
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

    /// The island being moved is on top; the current tab's island above the rest.
    private func zIndex(of island: Island) -> Double {
        if islands.draggedIslandID == island.id { return 2 }
        return island.tabIDs.contains(windowState.activeTabID ?? UUID()) ? 1 : 0
    }
}

/// One island: a column of the group's tabs as rows. Any of its empty glass moves it; its
/// rows move themselves. Its name and controls float beside it while the pointer is on it
/// (``IslandControls``).
struct IslandView: View {
    let island: Island
    let area: CGRect

    @Environment(IslandController.self) private var islands
    @Environment(WindowState.self) private var windowState
    @State private var dragStart: CGPoint?

    private var geometry: IslandGeometry {
        islands.geometry(for: island)
    }

    private var color: Color {
        islands.color(of: island)
    }

    var body: some View {
        let shape = WindowCorner.concentric
        let frame = islands.frame(of: island)
        rows
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
        // A blurred shape under the glass is the shadow: a row's hover never re-renders the
        // island for it.
        .background {
            shape.fill(.black.opacity(0.12)).blur(radius: 18).offset(y: 8)
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
    }

    /// The rows in the tab list's order; past the window's share of height they scroll, and
    /// then only the rows in view are built.
    @ViewBuilder
    private var rows: some View {
        let list = ForEach(Array(island.tabIDs.enumerated()), id: \.element) { index, tabID in
            if let tab = islands.tab(for: tabID) {
                IslandTabRow(tab: tab, island: island, index: index, area: area)
                    .frame(height: IslandGeometry.rowHeight)
            }
        }
        if geometry.contentHeight(rows: island.tabIDs.count) > islands.frame(of: island).height + 0.5 {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    list
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, offset in
                islands.scrollOffsets[island.id] = offset
            }
        } else {
            VStack(spacing: 0) {
                list
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
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
                islands.endIslandMove(keeping: island.id)
            }
    }

    /// The island's color and name, and under the pointer its pin and actions.
}

/// An island's name and controls, floating beside it while the pointer is on the island: its
/// color and name at the leading end, which a double-click renames, the pin and the menu at
/// the trailing end. Glass over the page, never over the island's glass.
private struct IslandControls: View {
    let island: Island
    let frame: CGRect

    @Environment(IslandController.self) private var islands
    @Environment(WindowState.self) private var windowState
    @State private var isRenaming = false
    @State private var draftName = ""
    @FocusState private var nameIsFocused: Bool

    private enum Layout {
        static let horizontalPadding: CGFloat = 10
        /// The name reads above the rows' titles: larger than a tab's title, and semibold.
        static let titleSize: CGFloat = 14
        static let controlSize: CGFloat = 22
        static let controlSpacing: CGFloat = 2
    }

    /// Where the menu button is, in the layer, so its menu hangs from it.
    @State private var menuButtonFrame: CGRect = .zero

    private var color: Color {
        islands.color(of: island)
    }

    var body: some View {
        HStack(spacing: 6) {
            if isRenaming {
                TextField("Name", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.system(size: Layout.titleSize, weight: .semibold))
                    .focused($nameIsFocused)
                    .onSubmit { commitRename() }
                    .onExitCommand { endRename() }
                    .onChange(of: nameIsFocused) { _, focused in
                        if !focused { commitRename() }
                    }
            } else {
                Text(island.title)
                    .font(.system(size: Layout.titleSize, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .onTapGesture(count: 2) { beginRename() }
            }
            Spacer(minLength: 8)
            pinButton
            menuButton
            newTabButton
        }
        .padding(.leading, Layout.horizontalPadding)
        .padding(.trailing, (Layout.horizontalPadding - Layout.controlSpacing) / 2)
        .frame(width: frame.width, height: frame.height)
        .background(windowState.controlIslandTint, in: .capsule)
        .glassEffect(.regular, in: .capsule)
        .coordinateSpace(name: "islandControls")
        .onHover { islands.setHovered(island.id, $0) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(island.title) controls")
    }

    private var pinButton: some View {
        Button {
            islands.togglePin(island.id)
        } label: {
            Image(systemName: island.placement.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(island.placement.isPinned ? AnyShapeStyle(color) : AnyShapeStyle(.secondary))
                .frame(width: Layout.controlSize, height: Layout.controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.default)
        .help(island.placement.isPinned ? "Let the island go when ⌃ is up" : "Keep the island visible")
        .accessibilityLabel(island.placement.isPinned ? "Unpin island" : "Pin island")
    }

    private var menuButton: some View {
        Button {
            showMenu()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: Layout.controlSize, height: Layout.controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.default)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("islandControls")) } action: { menuButtonFrame = $0 }
        .help("Island options")
        .accessibilityLabel("Island options")
    }

    /// The most frequent action, at the end: a page opened from here is a new tab in this island.
    private var newTabButton: some View {
        Button {
            islands.addTab(to: island.id)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: Layout.controlSize, height: Layout.controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.default)
        .help("New tab in \(island.title) · opens the Command Lens")
        .accessibilityLabel("New tab in \(island.title)")
    }

    /// The island's menu, an AppKit menu under the controls: the controls stay while it tracks.
    private func showMenu() {
        guard let content = windowState.window?.contentView else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        func add(_ title: String, to menu: NSMenu, state: NSControl.StateValue = .off, _ execute: @escaping @MainActor () -> Void) {
            let target = MenuActionTarget(execute)
            let item = NSMenuItem(title: title, action: #selector(MenuActionTarget.performAction(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = target
            item.state = state
            menu.addItem(item)
        }
        let id = island.id
        add(island.placement.iconsOnly ? "Show Titles" : "Show Icons Only", to: menu) { islands.toggleIconsOnly(id) }
        add(island.placement.isPinned ? "Let Go When ⌃ Is Up" : "Keep Visible", to: menu) { islands.togglePin(id) }
        if !island.isDefault {
            add("Rename…", to: menu) { beginRename() }
            let colors = NSMenu(title: "Color")
            let current = GroupColor(rawValue: island.colorString ?? "")
            for color in GroupColor.allCases {
                add(color.rawValue, to: colors, state: color == current ? .on : .off) { islands.setColor(color, of: id) }
            }
            let colorItem = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
            colorItem.submenu = colors
            menu.addItem(colorItem)
        }
        menu.addItem(.separator())
        add("Close All Tabs in Island", to: menu) { islands.closeAll(in: id) }
        if !island.isDefault {
            add("Dissolve Island", to: menu) { islands.dissolve(id) }
        }
        // The menu hangs from the button, its trailing edges aligned. The layer is top-down;
        // the content view is not.
        let button = menuButtonFrame.offsetBy(dx: frame.minX, dy: frame.minY)
        let point = NSPoint(x: button.maxX - menu.size.width, y: content.bounds.height - button.maxY - 2)
        islands.holdControls(id, true)
        menu.popUp(positioning: nil, at: point, in: content)
        islands.holdControls(id, false)
    }

    private func beginRename() {
        guard !island.isDefault else { return }
        draftName = island.title
        isRenaming = true
        nameIsFocused = true
        islands.holdControls(island.id, true)
    }

    private func commitRename() {
        guard isRenaming else { return }
        islands.rename(island.id, to: draftName)
        endRename()
    }

    private func endRename() {
        isRenaming = false
        islands.holdControls(island.id, false)
    }
}

/// One tab as a row: its favicon with the loading ring, its title, its state, and under the
/// pointer its close. A click opens the page; a drag moves the row within its island, into
/// another, or, let go on the page, out of its island as a live card. Its menu is the page's.
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
            && lhs.island.placement.iconsOnly == rhs.island.placement.iconsOnly && lhs.island.tabIDs == rhs.island.tabIDs
            && lhs.island.colorString == rhs.island.colorString && lhs.area == rhs.area
    }

    @Environment(IslandController.self) private var islands
    @Environment(WindowState.self) private var windowState
    @Environment(TabManager.self) private var tabManager
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(\.colorScheme) private var colorScheme
    @Environment(BookmarksManager.self) private var bookmarks
    @Environment(SharingCoordinator.self) private var sharing
    @State private var dragOffset: CGSize = .zero
    @State private var isHovering = false

    private enum Layout {
        static let faviconSize: CGFloat = 16
        static let paneFaviconSize: CGFloat = 12
        static let previewDelay: Duration = .milliseconds(650)
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

    private var isSelected: Bool {
        islands.selectedTabIDs.contains(tab.id)
    }

    /// How far the row moves while another is dragged: the rows below the lifted one close
    /// its hole, and the rows at and past the drop row open a gap for it.
    private var shift: CGFloat {
        guard let dragged = islands.draggedTabID, dragged != tab.id, let drop = islands.drop, drop.island == island.id, drop.joins == nil else { return 0 }
        var target = index
        if let lifted = island.tabIDs.firstIndex(of: dragged), lifted < index {
            target -= 1
        }
        if target >= drop.row {
            target += 1
        }
        return CGFloat(target - index) * IslandGeometry.rowHeight
    }

    private var rowFill: Color {
        if isJoinTarget { return Color.appAccentColor.opacity(0.2) }
        if isSelected { return Color.appAccentColor.opacity(0.16) }
        // The current row is white, a lit surface on the glass, in any tint the window has.
        if isCurrent { return Color.white.opacity(colorScheme == .dark ? 0.16 : 0.7) }
        return Color.primary.opacity(isHovering ? 0.08 : 0)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: IslandGeometry.rowCornerRadius, style: .continuous)
        HStack(spacing: 8) {
            pages
            if !iconsOnly {
                FloatingTabTitle(tab: tab, weight: isCurrent ? .semibold : .regular)
                    .foregroundStyle(isCurrent ? AnyShapeStyle(.primary) : AnyShapeStyle(.primary.opacity(0.85)))
                if tab.pages.count > 1 {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
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
        .background(rowFill, in: shape)
        .offset(y: shift)
        .animation(.snappy(duration: 0.2), value: islands.drop)
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
        .gesture(dragGesture)
        .contextMenu { MenuTreeView(tree: menuTree) }
        .closesOnMiddleClick(tab)
        .help(iconsOnly ? tab.displayTitle : "")
        .accessibilityLabel(tab.displayTitle)
        .accessibilityIdentifier("island-row-\(tab.id.uuidString)")
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { islands.open(tab) }
        .accessibilityAction(named: "Close") { tabManager.requestCloseTab(tab) }
        .accessibilityAction(named: "Float as Live Page") { islands.detach(tab.id, at: CGPoint(x: area.midX, y: area.midY)) }
        .accessibilityAction(named: "New Island from Here") { islands.makeIsland(from: tab.id) }
        .accessibilityAction(named: "Move Up") { moveRow(by: -1) }
        .accessibilityAction(named: "Move Down") { moveRow(by: 1) }
        .accessibilityAction(named: "Join with Row Above") { joinNeighbor(offset: -1) }
        .accessibilityAction(named: "Select") { islands.select(tab.id, extending: false, toggling: true) }
    }

    /// Moves the row one place up or down its island.
    private func moveRow(by offset: Int) {
        guard let index = island.tabIDs.firstIndex(of: tab.id) else { return }
        // Rows are counted without this one: down goes after the next row, up before the previous.
        let rows = island.tabIDs.count - 1
        islands.moveTab(tab.id, to: offset > 0 ? min(index + 1, rows) : max(0, index - 1), in: island.id)
    }

    /// Joins this row's tab to its neighbor's as a pane.
    private func joinNeighbor(offset: Int) {
        guard let index = island.tabIDs.firstIndex(of: tab.id), island.tabIDs.indices.contains(index + offset) else { return }
        islands.join(tab.id, with: island.tabIDs[index + offset])
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
        let chosen = islands.actionTabs(for: tab.id)
        if chosen.count > 1 {
            return MenuComposer.compose(selectionActions(chosen), groupOrder: PageActionsMenu.groupOrder)
        }
        return MenuComposer.compose(page.actions() + object.actions() + islandActions, groupOrder: PageActionsMenu.groupOrder)
    }

    /// What a row can do within its island: make an island, float, move, leave, close around it.
    private var islandActions: [MenuAction] {
        var actions = [
            MenuAction("island.new", "New Island from Here", symbol: "plus.rectangle.on.rectangle", group: .move) { islands.makeIsland(from: tab.id) },
            MenuAction("island.float", "Float as Live Page", symbol: "rectangle.on.rectangle", group: .move) {
                islands.detach(tab.id, at: CGPoint(x: area.midX, y: area.midY))
            },
        ]
        let others = islands.islands.filter { $0.id != island.id }
        if !others.isEmpty {
            actions.append(MenuAction("island.moveTo", "Move to Island", symbol: "arrow.right.square", group: .move, children: others.map { other in
                MenuAction("island.moveTo.\(other.id)", other.title, symbol: "circle.fill", group: .move) {
                    islands.moveTab(tab.id, to: Int.max, in: other.id)
                }
            }))
        }
        if !island.isDefault {
            actions.append(MenuAction("island.leave", "Remove from Island", symbol: "minus.square", group: .move) { islands.removeFromIsland(tab.id) })
        }
        if tabManager.state.settings.archiveEnabled {
            actions.append(MenuAction("island.archive", "Archive Tab", symbol: "archivebox", group: .close) { islands.archive([tab]) })
        }
        actions.append(MenuAction("island.closeOthers", "Close Other Tabs in Island", symbol: "xmark.rectangle", group: .close) { islands.closeOthers(than: tab.id) })
        actions.append(MenuAction("island.closeAbove", "Close Tabs Above", symbol: "arrow.up.to.line", group: .close) { islands.close(below: false, of: tab.id) })
        actions.append(MenuAction("island.closeBelow", "Close Tabs Below", symbol: "arrow.down.to.line", group: .close) { islands.close(below: true, of: tab.id) })
        return actions
    }

    /// What several chosen rows can do together.
    private func selectionActions(_ chosen: [Tab]) -> [MenuAction] {
        let n = chosen.count
        var actions = [
            MenuAction("island.selection.new", "New Island from \(n) Tabs", symbol: "plus.rectangle.on.rectangle", group: .move) {
                islands.makeIsland(from: chosen.map(\.id))
            },
        ]
        if let current = tab.space {
            let targets = tabManager.spaceManager.spaces.filter { $0.id != current.id }.map { space in
                MenuAction("island.selection.space.\(space.id)", space.name, symbol: space.isEmoji ? nil : space.iconName, group: .move) {
                    Task(name: "Move tabs to space") { await tabManager.moveTabsUnlocking(chosen, to: space, confirmingIn: windowState) }
                }
            }
            if !targets.isEmpty {
                actions.append(MenuAction("island.selection.space", "Move \(n) Tabs to Space", symbol: "square.stack.3d.up", group: .move, children: targets))
            }
        }
        if tabManager.state.settings.archiveEnabled {
            actions.append(MenuAction("island.selection.archive", "Archive \(n) Tabs", symbol: "archivebox", group: .close) { islands.archive(chosen) })
        }
        actions.append(MenuAction("island.selection.close", "Close \(n) Tabs", symbol: "xmark", group: .close, isDestructive: true) {
            tabManager.requestCloseTabs(chosen)
        })
        return actions
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
                    let local = islands.rowPoint(CGPoint(x: point.x - frame.minX, y: point.y - frame.minY), in: target)
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
        WindowCorner.concentric
            .fill(Color.appAccentColor.opacity(0.14))
            .overlay {
                WindowCorner.concentric
                    .stroke(Color.appAccentColor.opacity(0.5), lineWidth: 1)
                    .padding(0.5)
            }
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: side == .topLeft ? "rectangle.lefthalf.inset.filled" : "rectangle.righthalf.inset.filled")
                        .font(.system(size: Layout.symbolSize, weight: .regular))
                    Text("Open beside the page")
                        .font(.callout.weight(.medium))
                }
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
