import AppKit
import SwiftUI

/// A group on the floating layer: a glass capsule header and, unfolded, a tinted outline around
/// its cards. The header folds and unfolds the group (⌥ for every group), moves it by drag,
/// and holds its options; folded, it carries the first favicons and lists its tabs on hover.
struct FloatingTabGroup: View {
    let item: FloatingGroupItem
    let area: CGRect
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(WindowState.self) private var windowState
    @Environment(TabManager.self) private var tabs
    @State private var presentsOptions = false
    @State private var presentsAppearance = false
    @State private var showsList = false
    @State private var listHoverTask: Task<Void, Never>?
    @State private var isHeaderHovered = false
    @State private var isListHovered = false
    @State private var name = ""
    @FocusState private var isNameFocused: Bool

    private enum Layout {
        static let dotSize: CGFloat = 8
        static let faviconSize: CGFloat = 14
        /// How far each stacked favicon sits from the one under it.
        static let faviconStep: CGFloat = 6
        static let horizontalPadding: CGFloat = 10
        static let spacing: CGFloat = 6
        static let controlSize: CGFloat = 20
        static let listWidth: CGFloat = 260
        static let listRowHeight: CGFloat = 28
        static let listOpenDelay: Duration = .milliseconds(250)
        static let listCloseDelay: Duration = .milliseconds(200)
        static let outlineFillOpacity: Double = 0.06
        static let targetFillOpacity: Double = 0.14
        static let outlineStrokeOpacity: Double = 0.35
        static let targetStrokeOpacity: Double = 0.9
    }

    private var group: TabGroup {
        item.group
    }
    private var color: Color {
        Color.resolveStoredColor(group.colorString)
    }
    private var isDropTarget: Bool {
        canvas.floatingDropGroupID == item.id
    }
    private var isRenaming: Bool {
        canvas.floatingRenamingGroupID == item.id
    }
    private var memberTabs: [Tab] {
        canvas.allTabs(in: group)
    }
    private var headerFrame: CGRect {
        canvas.headerFrame(for: item)
    }
    /// The widest the header may draw: the folded maximum, or the outline's width inside its insets.
    private var headerRoom: CGFloat {
        item.isFolded
            ? FloatingGroupLayout.maximumHeaderWidth
            : max(FloatingGroupLayout.headerHeight, min(FloatingGroupLayout.maximumHeaderWidth, item.outline.width - FloatingGroupLayout.headerInset * 2))
    }
    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    var body: some View {
        if !item.isFolded {
            outline
                .frame(width: item.outline.width, height: item.outline.height)
                .offset(x: item.outline.minX, y: item.outline.minY)
                .transition(reduceMotion ? .opacity : .scale(scale: 0.92, anchor: .topLeading).combined(with: .opacity))
        }
        header
            .frame(width: headerRoom, alignment: .leading)
            .offset(x: headerFrame.minX, y: headerFrame.minY)
    }

    // MARK: Outline

    private var outline: some View {
        let shape = RoundedRectangle(cornerRadius: FloatingGroupLayout.outlineRadius)
        return shape
            .fill(color.opacity(isDropTarget ? Layout.targetFillOpacity : Layout.outlineFillOpacity))
            .overlay {
                shape.strokeBorder(color.opacity(isDropTarget ? Layout.targetStrokeOpacity : Layout.outlineStrokeOpacity), lineWidth: isDropTarget ? 2 : 1)
            }
            .animation(.easeOut(duration: 0.15), value: isDropTarget)
            .allowsHitTesting(false)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: Layout.spacing) {
            Circle().fill(color).frame(width: Layout.dotSize, height: Layout.dotSize)
                .popover(isPresented: $presentsAppearance, arrowEdge: .bottom) { CreateGroupPopover(group: group) }
            if item.isFolded {
                stackedFavicons
            }
            if isRenaming {
                nameField
            } else {
                Text(group.displayNameWithIcon)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            if item.isFolded {
                Text("\(memberTabs.count)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Image(systemName: item.isFolded ? "chevron.right" : "chevron.down")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .contentTransition(.symbolEffect(.replace))
            optionsButton
        }
        .padding(.leading, Layout.horizontalPadding)
        .padding(.trailing, Layout.spacing)
        .frame(height: FloatingGroupLayout.headerHeight)
        .glassEffect(.regular, in: Capsule())
        .overlay {
            Capsule().strokeBorder(Color.appAccentColor, lineWidth: 2)
                .opacity(isDropTarget && item.isFolded ? 1 : 0)
                .allowsHitTesting(false)
        }
        .contentShape(Capsule())
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { canvas.floatingHeaderWidths[item.id] = $0 }
        .onTapGesture {
            guard !isRenaming else { return }
            canvas.toggleFold(group, everyGroup: NSEvent.modifierFlags.contains(.option))
        }
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("floatingTabs"))
            .onChanged { value in
                closeList()
                canvas.dragFloatingGroup(item, translation: value.translation, pointer: value.location, in: area)
            }
            .onEnded { _ in canvas.endFloatingGroupDrag(item) })
        .onHover(perform: hoverHeader)
        .contextMenu {
            MenuTreeView(tree: actions.tree())
        }
        .popover(isPresented: $showsList, arrowEdge: .bottom) { tabList }
        .help(item.isFolded ? "Unfold \(group.name) · ⌥ for every group" : "Fold \(group.name) · ⌥ for every group")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Group \(group.name), \(memberTabs.count) tabs, \(item.isFolded ? "folded" : "unfolded")")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { canvas.toggleFold(group) }
        .accessibilityAction(named: "Fold or unfold every group") { canvas.toggleFold(group, everyGroup: true) }
    }

    private var nameField: some View {
        TextField("Group Name", text: $name)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .frame(minWidth: 80)
            .focused($isNameFocused)
            .onSubmit { canvas.renameFloatingGroup(group, to: name) }
            .onExitCommand { canvas.floatingRenamingGroupID = nil }
            .onChange(of: isNameFocused) { _, focused in
                if !focused, isRenaming {
                    canvas.renameFloatingGroup(group, to: name)
                }
            }
            .onAppear {
                name = group.name
                isNameFocused = true
            }
    }

    /// Up to three favicons, each a step to the right of the one under it.
    private var stackedFavicons: some View {
        let shown = Array(memberTabs.prefix(FloatingGroupLayout.foldedFaviconLimit))
        return ZStack(alignment: .leading) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, tab in
                favicon(for: tab)
                    .background(Circle().fill(.background).padding(-1))
                    .offset(x: CGFloat(index) * Layout.faviconStep)
                    .zIndex(Double(shown.count - index))
            }
        }
        .frame(width: Layout.faviconSize + CGFloat(max(0, shown.count - 1)) * Layout.faviconStep, alignment: .leading)
        .accessibilityHidden(true)
    }

    private func favicon(for tab: Tab) -> some View {
        Group {
            if let data = tab.activePage.faviconData, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "globe").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .frame(width: Layout.faviconSize, height: Layout.faviconSize)
    }

    // MARK: Options

    private var actions: FloatingGroupActions {
        FloatingGroupActions(
            group: group, canvas: canvas, windowState: windowState, tabs: tabs,
            onRename: { canvas.beginRenaming(group) },
            onEditAppearance: {
                canvas.latchFloatingTabs()
                presentsAppearance = true
            },
        )
    }

    private var optionsButton: some View {
        Button("Group options", systemImage: "ellipsis") {
            canvas.latchFloatingTabs()
            presentsOptions.toggle()
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .frame(width: Layout.controlSize, height: Layout.controlSize)
        .contentShape(Rectangle())
        .help("Group options")
        .popover(isPresented: $presentsOptions, arrowEdge: .bottom) {
            VStack(spacing: PageMenuContent.Layout.itemSpacing) {
                MenuTreeView(tree: actions.tree().runningFirst { presentsOptions = false })
            }
            .buttonStyle(.pageMenuRow)
            .menuStyle(.button)
            .padding(PageMenuContent.Layout.popoverPadding)
            .frame(width: PageMenuContent.Layout.width)
        }
    }

    // MARK: Tab List

    private var tabList: some View {
        VStack(alignment: .leading, spacing: PageMenuContent.Layout.itemSpacing) {
            ForEach(memberTabs) { tab in
                Button {
                    closeList()
                    canvas.openFloatingTab(tab)
                } label: {
                    Label {
                        Text(tab.displayTitle).lineLimit(1)
                    } icon: {
                        favicon(for: tab)
                    }
                }
                .frame(height: Layout.listRowHeight)
            }
        }
        .buttonStyle(.pageMenuRow)
        .padding(PageMenuContent.Layout.popoverPadding)
        .frame(width: Layout.listWidth)
        .onHover { hovering in
            isListHovered = hovering
            scheduleListUpdate()
        }
    }

    private func hoverHeader(_ hovering: Bool) {
        isHeaderHovered = hovering
        scheduleListUpdate()
    }

    /// Opens the list after the pointer settles on a folded header, and closes it once the
    /// pointer has left both the header and the list.
    private func scheduleListUpdate() {
        listHoverTask?.cancel()
        let wanted = item.isFolded && (isHeaderHovered || isListHovered) && canvas.floatingMoveOrigins.isEmpty
        guard wanted != showsList else { return }
        listHoverTask = Task(name: "Folded group tab list") {
            try? await Task.sleep(for: wanted ? Layout.listOpenDelay : Layout.listCloseDelay)
            guard !Task.isCancelled else { return }
            showsList = wanted
        }
    }

    private func closeList() {
        listHoverTask?.cancel()
        showsList = false
    }
}
