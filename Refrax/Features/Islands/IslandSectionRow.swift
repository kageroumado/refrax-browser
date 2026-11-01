import AppKit
import SwiftUI

/// A group nested in the island's group: a disclosure chevron, its icon (or a dot of its
/// color), its name, while folded its tab count, and under the pointer a menu button. A
/// click folds or unfolds it; its menu, or a right-click, edits it or makes it its own
/// island again.
struct IslandSectionRow: View {
    let section: IslandSection
    let island: Island
    /// The row's place in the island, for the gap a drag opens.
    let index: Int

    @Environment(IslandController.self) private var islands
    @Environment(WindowState.self) private var windowState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var isEditing = false
    @State private var editAfterMenu = false
    /// The menu button's bounds in the islands layer.
    @State private var menuButtonFrame: CGRect = .zero

    enum Layout {
        /// How far a section's tab rows sit in from the island's own.
        static let indent: CGFloat = 12
        /// Where a section's guide runs: under the header's chevron.
        static let guideOffset: CGFloat = 14
        static let chevronSize: CGFloat = 9
        static let glyphSize: CGFloat = 11
        static let titleSize: CGFloat = 12
        static let countSize: CGFloat = 11
        static let slot: CGFloat = 16
        static let dotSize: CGFloat = 7
        static let menuButtonSize: CGFloat = 20
    }

    private var iconsOnly: Bool {
        island.placement.iconsOnly
    }

    /// How far the row moves while another is dragged, as tab rows do.
    private var shift: CGFloat {
        guard let dragged = islands.draggedTabID, let drop = islands.drop, drop.island == island.id, drop.joins == nil else { return 0 }
        var target = index
        if let lifted = island.layout.row(of: dragged), lifted < index {
            target -= 1
        }
        if target >= drop.row {
            target += 1
        }
        return CGFloat(target - index) * islands.geometry(for: island).cellHeight
    }

    var body: some View {
        let shape = ConcentricRectangle(corners: .concentric(minimum: .fixed(IslandGeometry.rowCornerRadius)), isUniform: true)
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: Layout.chevronSize, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(section.isCollapsed ? 0 : 90))
                .frame(width: Layout.slot, height: Layout.slot)
            if !iconsOnly {
                icon
                Text(section.title)
                    .font(.system(size: Layout.titleSize, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if section.isCollapsed {
                    Text(section.tabIDs.count, format: .number)
                        .font(.system(size: Layout.countSize).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                if isHovering {
                    menuButton
                }
            }
        }
        .padding(.horizontal, iconsOnly ? 0 : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: iconsOnly ? .center : .leading)
        .background(Color.primary.opacity(isHovering ? 0.08 : 0), in: shape)
        .offset(y: shift)
        .animation(.snappy(duration: 0.2), value: islands.drop)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: section.isCollapsed)
        .contentShape(shape)
        .onHover { isHovering = $0 }
        .onTapGesture { islands.toggleSection(section.id) }
        .contextMenu {
            Button(section.isCollapsed ? "Expand" : "Collapse") { islands.toggleSection(section.id) }
            Button("Edit…") { isEditing = true }
            Divider()
            Button("Make Its Own Island") { islands.unnest(section.id) }
        }
        .popover(isPresented: $isEditing, arrowEdge: .trailing) {
            IslandEditor(islandID: section.id)
        }
        .onChange(of: isEditing) { _, editing in
            islands.holdControls(island.id, editing)
        }
        .help("“\(section.title)” is a group inside \(island.title). Click to fold or unfold it.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(section.title), \(section.tabIDs.count) tabs")
        .accessibilityValue(section.isCollapsed ? "Collapsed" : "Expanded")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { islands.toggleSection(section.id) }
        .accessibilityIdentifier("island-section-\(section.id.uuidString)")
    }

    /// The section's menu, under the pointer: fold, edit, or make the group its own island.
    private var menuButton: some View {
        Button {
            showMenu()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: Layout.glyphSize))
                .foregroundStyle(.secondary)
                .frame(width: Layout.menuButtonSize, height: Layout.menuButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.default)
        // A control that comes and goes stays out of the key-view loop: SwiftUI rebuilding
        // that loop beside the page's views can spin forever.
        .focusable(false)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("islands")) } action: { menuButtonFrame = $0 }
        .help("Section options")
        .accessibilityLabel("Options for \(section.title)")
    }

    /// An AppKit menu under the menu button; the island's controls stay while it tracks.
    private func showMenu() {
        guard let content = windowState.window?.contentView else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        editAfterMenu = false
        func add(_ title: String, _ execute: @escaping @MainActor () -> Void) {
            let target = MenuActionTarget(execute)
            let item = NSMenuItem(title: title, action: #selector(MenuActionTarget.performAction(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = target
            menu.addItem(item)
        }
        let id = section.id
        add(section.isCollapsed ? "Expand" : "Collapse") { islands.toggleSection(id) }
        add("Edit…") { editAfterMenu = true }
        menu.addItem(.separator())
        add("Make Its Own Island") { islands.unnest(id) }
        // The layer is top-down; AppKit's content coordinates are bottom-up.
        let point = NSPoint(x: menuButtonFrame.minX, y: content.bounds.height - menuButtonFrame.maxY - 2)
        islands.holdControls(island.id, true)
        // The button's action completes before AppKit's menu tracking loop begins.
        DispatchQueue.main.async {
            if content.window != nil {
                menu.popUp(positioning: nil, at: point, in: content)
            }
            islands.holdControls(island.id, false)
            if editAfterMenu {
                editAfterMenu = false
                isEditing = true
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let name = section.iconName {
            Group {
                if IslandAppearance.isEmoji(name) {
                    Text(name).font(.system(size: Layout.glyphSize))
                } else {
                    Image(systemName: name)
                        .font(.system(size: Layout.glyphSize))
                        .foregroundStyle(section.colorString.map(Color.resolveStoredColor) ?? .secondary)
                }
            }
            .frame(width: Layout.slot, height: Layout.slot)
        } else {
            // Without an icon, the group's color marks it as a group.
            Circle()
                .fill(section.colorString.map(Color.resolveStoredColor) ?? .secondary)
                .frame(width: Layout.dotSize, height: Layout.dotSize)
                .frame(width: Layout.slot, height: Layout.slot)
        }
    }
}
