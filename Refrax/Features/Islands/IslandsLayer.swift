import AppKit
import SwiftUI

/// The islands over the page: each a glass container of chips, shown while the reveal key is
/// held or the island is pinned, with the beams that run from the page card to a chip.
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
                        .zIndex(island.layout[windowState.activeTabID ?? UUID()] != nil ? 1 : 0)
                        .transition(reduceMotion ? .opacity : .scale(scale: Layout.emergeScale).combined(with: .opacity))
                }
                ForEach(islands.beams) { beam in
                    IslandBeamView(beam: beam, area: bounds) {
                        islands.finishBeam(beam.id)
                    }
                }
            }
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: islands.visibleIslands.map(\.id))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .coordinateSpace(name: "islands")
            .onChange(of: geometry.size, initial: true) {
                islands.updateArea(bounds.insetBy(dx: Layout.areaInset, dy: Layout.areaInset))
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
}

/// A beam in an island's color, from the page card to a chip.
private struct IslandBeamView: View {
    let beam: IslandBeam
    let area: CGRect
    let onFinish: () -> Void

    var body: some View {
        let style = LightStyle.guide
        let path = FloatingRayPath(from: beam.from, to: beam.to, in: area)
        LightTravel(paths: [style.path(ray: path, color: beam.color)], timing: style.timing, onFinish: onFinish)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// One island: its chips on their grid inside glass, a silhouette where a dragged chip may
/// land, and a footer naming it that moves it, pins it, and holds its actions.
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
        let content = geometry.contentSize(of: island.layout)
        let frame = islands.frame(of: island)
        VStack(spacing: 0) {
            grid(content: content)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
            footer
                .frame(height: IslandGeometry.footerHeight)
        }
        .frame(width: frame.width, height: frame.height)
        // The Control Island's glass: the window's tint under regular glass.
        .background(windowState.controlIslandTint, in: shape)
        .glassEffect(.regular, in: shape)
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
        .onHover { isHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(island.title), \(island.layout.chips.count) tabs")
    }

    @ViewBuilder
    private func grid(content: CGSize) -> some View {
        let gridContent = ZStack(alignment: .topLeading) {
            if let candidate = islands.dropCandidate, candidate.island == island.id {
                let placement = ChipPlacement(cell: candidate.cell, span: draggedSpan)
                RoundedRectangle(cornerRadius: IslandGeometry.chipCornerRadius, style: .continuous)
                    .fill(color.opacity(0.18))
                    .overlay {
                        RoundedRectangle(cornerRadius: IslandGeometry.chipCornerRadius, style: .continuous)
                            .strokeBorder(color.opacity(0.7), lineWidth: 1)
                    }
                    .frame(width: geometry.frame(of: placement, in: island.layout).width, height: geometry.frame(of: placement, in: island.layout).height)
                    .offset(x: geometry.frame(of: placement, in: island.layout).minX, y: geometry.frame(of: placement, in: island.layout).minY)
                    .allowsHitTesting(false)
            }
            ForEach(island.layout.tabIDs, id: \.self) { tabID in
                if let tab = islands.tab(for: tabID), let chip = island.layout[tabID] {
                    let frame = geometry.frame(of: chip, in: island.layout)
                    ChipView(tab: tab, chip: chip, island: island, area: area)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
            }
        }
        .frame(width: content.width, height: content.height - IslandGeometry.footerHeight, alignment: .topLeading)
        .animation(.snappy(duration: 0.24), value: island.layout)

        let frame = islands.frame(of: island)
        if content.width > frame.width + 0.5 || content.height - IslandGeometry.footerHeight > frame.height - IslandGeometry.footerHeight + 0.5 {
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                gridContent
            }
        } else {
            gridContent
        }
    }

    private var draggedSpan: IslandSpan {
        guard let candidate = islands.dropCandidate, let tabID = windowState.draggedChipID, let chip = islands.island(candidate.island)?.layout[tabID] ?? islands.island(holding: tabID)?.layout[tabID] else { return .one }
        return chip.span
    }

    /// The island's name, its count, and, while the pointer is on the island, its pin and
    /// actions. Double-click the name to rename a group's island. The footer moves the island.
    private var footer: some View {
        let showsControls = isHovered || island.placement.isPinned
        return HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7)
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
            } else {
                Text(island.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        guard !island.isDefault else { return }
                        draftName = island.title
                        isRenaming = true
                        nameIsFocused = true
                    }
            }
            Text("\(island.layout.chips.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            if showsControls {
                Button {
                    islands.togglePin(island.id)
                } label: {
                    Image(systemName: island.placement.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 11))
                        .foregroundStyle(island.placement.isPinned ? AnyShapeStyle(color) : AnyShapeStyle(.tertiary))
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 18, height: 18)
            }
        }
        .padding(.horizontal, IslandGeometry.padding)
        .animation(.easeInOut(duration: 0.15), value: showsControls)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .named("islands"))
                .onChanged { value in
                    if dragStart == nil {
                        dragStart = islands.frame(of: island).origin
                    }
                    if let dragStart {
                        islands.moveIsland(island.id, to: CGPoint(x: dragStart.x + value.translation.width, y: dragStart.y + value.translation.height))
                    }
                }
                .onEnded { _ in dragStart = nil },
        )
        .accessibilityAddTraits(.isHeader)
    }

    private func commitRename() {
        guard isRenaming else { return }
        isRenaming = false
        islands.rename(island.id, to: draftName)
    }
}

/// One chip: the tab's favicon and title, the favicon alone, or a live preview of the page.
/// A click opens the page; a drag moves the chip to a cell beside another, or to another
/// island; its menu makes a new island from it or changes its shape.
private struct ChipView: View {
    let tab: Tab
    let chip: ChipPlacement
    let island: Island
    let area: CGRect

    @Environment(IslandController.self) private var islands
    @Environment(WindowState.self) private var windowState
    @Environment(TabManager.self) private var tabManager
    @State private var dragOffset: CGSize = .zero
    @State private var isHovering = false

    private enum Layout {
        static let faviconSize: CGFloat = 14
        static let previewHeaderHeight: CGFloat = 24
        /// Chips untouched this long step back a shade.
        static let restAge: TimeInterval = 24 * 60 * 60
        static let restOpacity: Double = 0.55
        /// How far inside another island a dragged chip must be to move there.
        static let otherIslandInset: CGFloat = 24
    }

    private var isCurrent: Bool {
        tab.id == windowState.activeTabID
    }

    private var isResting: Bool {
        !isCurrent && Date.now.timeIntervalSince(tab.lastAccessed ?? .distantPast) > Layout.restAge
    }

    private var color: Color {
        islands.color(of: island)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: IslandGeometry.chipCornerRadius, style: .continuous)
        Group {
            if chip.shape == .preview {
                preview
            } else {
                titleFace
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isCurrent ? color.opacity(0.28) : Color.primary.opacity(isHovering ? 0.1 : 0.055), in: shape)
        .clipShape(shape)
        .opacity(isResting ? Layout.restOpacity : 1)
        .offset(dragOffset)
        .zIndex(dragOffset == .zero ? 0 : 2)
        .onHover { isHovering = $0 }
        .contentShape(shape)
        .onTapGesture { islands.open(tab) }
        .gesture(dragGesture)
        .contextMenu { menu }
        .help(tab.displayTitle)
        .accessibilityLabel(tab.displayTitle)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }

    private var titleFace: some View {
        HStack(spacing: 8) {
            favicon
            if !island.placement.iconsOnly {
                Text(tab.displayTitle)
                    .font(.callout.weight(isCurrent ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
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
        .padding(.leading, island.placement.iconsOnly ? 0 : 9)
        .padding(.trailing, island.placement.iconsOnly ? 0 : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: island.placement.iconsOnly ? .center : .leading)
    }

    private var preview: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                favicon
                Text(tab.displayTitle)
                    .font(.caption)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: Layout.previewHeaderHeight)
            FloatingTabPreview(tab: tab, viewportSize: area.size, isLive: !isCurrent)
                .clipShape(RoundedRectangle(cornerRadius: IslandGeometry.chipCornerRadius - 4, style: .continuous))
                .padding([.horizontal, .bottom], 4)
        }
    }

    @ViewBuilder
    private var favicon: some View {
        if let data = tab.activePage.faviconData, let image = NSImage(data: data) {
            Image(nsImage: image).resizable().scaledToFit()
                .frame(width: Layout.faviconSize, height: Layout.faviconSize)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        } else {
            Image(systemName: "globe")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: Layout.faviconSize, height: Layout.faviconSize)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
        }
    }

    @ViewBuilder
    private var menu: some View {
        Button("Open") { islands.open(tab) }
        Button("New Island from Here") { islands.makeIsland(from: tab.id) }
        if chip.shape == .preview {
            Button("Show as Title") { islands.setShape(.title, of: tab.id) }
            Menu("Preview Size") {
                Button("Small") { islands.resizePreview(tab.id, to: IslandGeometry.previewSpans[0]) }
                Button("Medium") { islands.resizePreview(tab.id, to: IslandGeometry.previewSpans[1]) }
                Button("Large") { islands.resizePreview(tab.id, to: IslandGeometry.previewSpans[2]) }
            }
        } else {
            Button("Show Preview") { islands.setShape(.preview, span: IslandGeometry.previewSpans[1], of: tab.id) }
        }
        Divider()
        Button("Close Tab") { tabManager.requestCloseTab(tab) }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named("islands"))
            .onChanged { value in
                dragOffset = value.translation
                windowState.draggedChipID = tab.id
                let point = value.location
                let home = islands.frame(of: island)
                let geometry = islands.geometry(for: island)
                // A chip may land one cell beyond its island's edges, which grows the island.
                let reach = home.insetBy(dx: -(geometry.cell.width + IslandGeometry.gap), dy: -(geometry.cell.height + IslandGeometry.gap))
                let local = CGPoint(x: point.x - home.minX, y: point.y - home.minY)
                let cell = geometry.cell(at: local, in: island.layout)
                // The chip's own island has first claim; another island takes a drop only well
                // inside its frame, so a neighbor island never catches a chip moved one cell over.
                if reach.contains(point), island.layout.canPlace(tab.id, at: cell, span: chip.span) {
                    islands.dropCandidate = (island.id, cell)
                } else if let target = islands.visibleIslands.first(where: {
                    $0.id != island.id && islands.frame(of: $0).insetBy(dx: Layout.otherIslandInset, dy: Layout.otherIslandInset).contains(point)
                }) {
                    islands.dropCandidate = (target.id, IslandCell(x: 0, y: 0))
                } else {
                    islands.dropCandidate = nil
                }
            }
            .onEnded { _ in
                if let candidate = islands.dropCandidate {
                    if candidate.island == island.id {
                        islands.moveChip(tab.id, to: candidate.cell)
                    } else {
                        islands.moveChip(tab.id, toIsland: candidate.island)
                    }
                }
                islands.dropCandidate = nil
                windowState.draggedChipID = nil
                withAnimation(.snappy(duration: 0.2)) {
                    dragOffset = .zero
                }
            }
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
