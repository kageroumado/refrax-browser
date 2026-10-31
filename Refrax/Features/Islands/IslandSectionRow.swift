import SwiftUI

/// A group nested in the island's group: a disclosure chevron, its icon, its name, and while
/// folded its tab count. A click folds or unfolds it; its menu edits it or takes it out.
struct IslandSectionRow: View {
    let section: IslandSection
    let island: Island
    /// The row's place in the island, for the gap a drag opens.
    let index: Int

    @Environment(IslandController.self) private var islands
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var isEditing = false

    enum Layout {
        /// How far a section's tab rows sit in from the island's own.
        static let indent: CGFloat = 12
        static let chevronSize: CGFloat = 9
        static let glyphSize: CGFloat = 11
        static let titleSize: CGFloat = 12
        static let countSize: CGFloat = 11
        static let slot: CGFloat = 16
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
        .help(iconsOnly ? section.title : "")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(section.title), \(section.tabIDs.count) tabs")
        .accessibilityValue(section.isCollapsed ? "Collapsed" : "Expanded")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { islands.toggleSection(section.id) }
        .accessibilityIdentifier("island-section-\(section.id.uuidString)")
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
        }
    }
}
