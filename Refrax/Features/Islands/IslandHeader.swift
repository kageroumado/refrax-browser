import AppKit
import SwiftUI

/// An island's header: its icon, which opens the island's editor, its name, which a
/// double-click renames, then the pin, the menu and the plus, in rounded glass above the
/// island. Kept visible for latched or pinned islands, and during pointer interaction; laid
/// out always.
struct IslandHeader: View {
    let island: Island

    @Environment(IslandController.self) private var islands
    @Environment(WindowState.self) private var windowState
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var editAfterMenu = false
    @State private var isEditing = false
    /// The menu button's bounds in the browser glass layer.
    @State private var menuButtonFrame: CGRect = .zero

    private enum Layout {
        /// From the header's edge to the name's ink.
        static let leadingInset: CGFloat = 14
        /// From the last glyph's box to the header's edge: with the glyph's own inset in its
        /// box, the same as the name's.
        static let trailingInset: CGFloat = 8
        /// The system's weights: the name a touch above a row's title, the glyphs regular.
        static let titleSize: CGFloat = 13
        static let glyphSize: CGFloat = 12
        static let controlSize = IslandGeometry.headerControlSize
        static let controlSpacing: CGFloat = 4
        static let fade: TimeInterval = 0.15
        /// Pulls the icon's 24-pt box toward the header's edge, so its glyph sits where the
        /// name's ink would.
        static let iconLeadingOffset: CGFloat = -8
    }

    private var isShown: Bool {
        islands.showsHeader(of: island.id)
    }

    var body: some View {
        Group {
            if island.placement.iconsOnly {
                menuButton
                    .help(island.title)
            } else {
                fullHeader
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            IslandDragSurface(islandID: island.id)
        }
        .windowGlassSurface(tint: windowState.controlIslandTint)
        .opacity(isShown ? 1 : 0)
        .allowsHitTesting(isShown)
        .animation(.easeOut(duration: Layout.fade), value: isShown)
        .onChange(of: islands.renameRequest, initial: true) { _, requested in
            if requested == island.id {
                islands.renameRequest = nil
                beginRename()
            }
        }
        .popover(isPresented: $isEditing, arrowEdge: .bottom) {
            IslandEditor(islandID: island.id)
        }
        .onChange(of: isEditing) { _, editing in
            islands.holdControls(island.id, editing)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(island.title) header")
        .accessibilityAction(named: "Edit Island") { beginEdit() }
    }

    /// The group's icon, tinted with its color: a click opens the island's editor.
    @ViewBuilder
    private var iconButton: some View {
        if let icon = island.iconName {
            Button {
                beginEdit()
            } label: {
                Group {
                    if IslandAppearance.isEmoji(icon) {
                        Text(icon)
                            .font(.system(size: Layout.titleSize))
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: Layout.glyphSize))
                            .foregroundStyle(islands.color(of: island))
                    }
                }
                .frame(width: Layout.controlSize, height: Layout.controlSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.default)
            .help("Edit name, icon, and color")
            .accessibilityLabel("Edit \(island.title)")
        }
    }

    private var fullHeader: some View {
        HStack(spacing: Layout.controlSpacing) {
            iconButton
                .padding(.leading, island.iconName == nil ? 0 : Layout.iconLeadingOffset)
            if isRenaming || islands.renameRequest == island.id {
                IslandNameField(text: $draftName, fontSize: Layout.titleSize, onCommit: commitRename, onCancel: endRename)
            } else {
                Text(island.title)
                    .font(.system(size: Layout.titleSize))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .onTapGesture(count: 2) { beginRename() }
                    .contextMenu {
                        if !island.isDefault {
                            Button("Edit Island…") { beginEdit() }
                            Button("Rename") { beginRename() }
                        }
                    }
            }
            Spacer(minLength: 8)
            pinButton
            menuButton
            newTabButton
        }
        .padding(.leading, Layout.leadingInset)
        .padding(.trailing, Layout.trailingInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var pinButton: some View {
        Button {
            islands.togglePin(island.id)
        } label: {
            Image(systemName: island.placement.isPinned ? "pin.fill" : "pin")
                .font(.system(size: Layout.glyphSize))
                .foregroundStyle(island.placement.isPinned ? AnyShapeStyle(Color.appAccentColor) : AnyShapeStyle(.secondary))
                .frame(width: Layout.controlSize, height: Layout.controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.default)
        .help(island.placement.isPinned ? "Unpin island" : "Pin island")
        .accessibilityLabel(island.placement.isPinned ? "Unpin island" : "Pin island")
    }

    private var menuButton: some View {
        Button {
            showMenu()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: Layout.glyphSize))
                .foregroundStyle(.secondary)
                .frame(width: Layout.controlSize, height: Layout.controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.default)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("islands")) } action: { menuButtonFrame = $0 }
        .help("Show island options")
        .accessibilityLabel("Island options")
    }

    /// The most frequent action, at the end: a page opened from here is a new tab in this island.
    private var newTabButton: some View {
        Button {
            islands.addTab(to: island.id)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: Layout.glyphSize))
                .foregroundStyle(.primary)
                .frame(width: Layout.controlSize, height: Layout.controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.default)
        .help("New tab in \(island.title)")
        .accessibilityLabel("New tab in \(island.title)")
    }

    /// An AppKit menu anchored to the island header in the browser window:
    /// the header stays while it tracks.
    private func showMenu() {
        guard let content = windowState.window?.contentView else { return }
        editAfterMenu = false
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
        add(islands.state.automaticallyArranged ? "Use Free Island Placement" : "Arrange All Islands Along Left Edge", to: menu) {
            if islands.state.automaticallyArranged {
                islands.useFreePlacement()
            } else {
                islands.arrangeAutomatically()
            }
        }
        add("New Tab in \(island.title)", to: menu) { islands.addTab(to: id) }
        add(island.placement.iconsOnly ? "Show Titles" : "Show as Icon Rail", to: menu) { islands.toggleIconsOnly(id) }
        add(island.placement.isPinned ? "Unpin Island" : "Pin Island", to: menu) { islands.togglePin(id) }
        let only = NSMenu(title: "Show Only")
        add("All Tabs", to: only, state: islands.filter == nil ? .on : .off) { islands.setFilter(nil) }
        only.addItem(.separator())
        for filter in IslandFilter.allCases {
            add(filter.title, to: only, state: islands.filter == filter ? .on : .off) { islands.setFilter(filter) }
        }
        let onlyItem = NSMenuItem(title: "Show Only", action: nil, keyEquivalent: "")
        onlyItem.submenu = only
        menu.addItem(onlyItem)
        if !island.isDefault {
            add("Edit Island…", to: menu) { editAfterMenu = true }
            let parents = islands.islands.filter { islands.canNest(id, in: $0.id) }
            if !parents.isEmpty {
                let inside = NSMenu(title: "Put Inside")
                for parent in parents {
                    add(parent.title, to: inside) { islands.nest(id, in: parent.id) }
                }
                let insideItem = NSMenuItem(title: "Put Inside", action: nil, keyEquivalent: "")
                insideItem.submenu = inside
                menu.addItem(insideItem)
            }
        }
        menu.addItem(.separator())
        add("Close All Tabs in Island", to: menu) { islands.closeAll(in: id) }
        if !island.isDefault {
            add("Ungroup Island", to: menu) { islands.dissolve(id) }
        }
        menu.addItem(.separator())
        add("Show Archive", to: menu) { windowState.showDetailTray(.archive) }
        // Convert the top-down glass layer coordinates to AppKit's content coordinates.
        let point = NSPoint(x: menuButtonFrame.maxX - menu.size.width, y: content.bounds.height - menuButtonFrame.maxY - 2)
        islands.holdControls(id, true)
        // Complete the button action before entering AppKit's menu tracking loop.
        DispatchQueue.main.async {
            if content.window != nil {
                menu.popUp(positioning: nil, at: point, in: content)
            }
            islands.holdControls(id, false)
            if editAfterMenu {
                editAfterMenu = false
                beginEdit()
            }
        }
    }

    /// Opens the editor of the island's name, icon, and color, anchored to its header.
    private func beginEdit() {
        guard !island.isDefault else { return }
        if island.placement.iconsOnly {
            islands.setIconsOnly(false, for: island.id)
        }
        isEditing = true
    }

    private func beginRename() {
        guard !island.isDefault else { return }
        if island.placement.iconsOnly {
            islands.setIconsOnly(false, for: island.id)
        }
        (windowState.window as? RefraxWindow)?.lockedFirstResponder = nil
        draftName = island.title
        isRenaming = true
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
