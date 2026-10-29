import AppKit
import SwiftUI

/// The browser's place for things that are files: downloads in progress and from the last
/// hour, then the shelf of dropped images, text, links, and files.
///
/// A small sibling of the Control Island in the same 48-point column, glass, tint, rest and
/// wake, grip, and snapping. It exists only while it holds something, while its full list is
/// open, or while a file, image, text, or link is dragged over the window, when it shows itself
/// as the place to drop and brightens as the drag reaches it.
struct FileIsland: View {
    let area: CGRect

    @Environment(WindowState.self) private var windowState
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(ShelfManager.self) private var shelf
    @Environment(TabManager.self) private var tabManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.appearsActive) private var appearsActive
    @GestureState private var isDraggingIsland = false
    @GestureState private var isDraggingWindow = false
    @State private var dragOrigin: CGPoint?
    /// The clock recent downloads are judged by, advanced as each one expires.
    @State private var now = Date()

    private typealias Placement = ControlIslandPlacement
    private typealias Layout = FileIslandLayout

    private var state: FileIslandState {
        windowState.fileIsland
    }

    private var actions: FileIslandActions {
        FileIslandActions(downloads: downloadManager, shelf: shelf, tabs: tabManager, windowState: windowState)
    }

    // MARK: - Contents

    /// Downloads in progress, newest first, then those finished within the hour, most recent first.
    private var downloads: [Download] {
        let all = downloadManager.downloads
        let inProgress = all.filter { $0.state.isActive || $0.state == .paused }
            .sorted { $0.createdAt > $1.createdAt }
        let finished = all.filter { ($0.state == .completed || $0.state == .failed) && Layout.isRecent(finishDate(of: $0), now: now) }
            .sorted { finishDate(of: $0) > finishDate(of: $1) }
        return inProgress + finished
    }

    private func finishDate(of download: Download) -> Date {
        download.completedAt ?? download.modifiedAt
    }

    /// When the next finished download leaves the island.
    private var nextExpiry: Date? {
        downloadManager.downloads
            .filter { $0.state == .completed || $0.state == .failed }
            .map { finishDate(of: $0).addingTimeInterval(Layout.recentInterval) }
            .filter { $0 > now }
            .min()
    }

    private var showsDropCell: Bool {
        state.drop != .none
    }

    private var isShown: Bool {
        !downloads.isEmpty || shelf.hasItems || showsDropCell || state.showsAll
    }

    private var allocation: FileIslandAllocation {
        FileIslandAllocation(
            downloads: downloads.count,
            shelf: shelf.items.count,
            limit: Layout.visibleLimit(in: area, showsDropCell: showsDropCell),
        )
    }

    // MARK: - Geometry

    private var height: CGFloat {
        let allocation = allocation
        return Layout.height(downloads: allocation.downloads, shelf: allocation.shelf, showsDropCell: showsDropCell)
    }

    private var placement: ControlIslandPlacement {
        state.placement ?? Layout.defaultPlacement(oppositeOf: windowState.controlIsland.placement)
    }

    private var frame: CGRect {
        placement.railFrame(in: area, height: height)
    }

    private var opensLeft: Bool {
        placement.opensLeft(in: area)
    }

    // MARK: - Rest

    private var isResting: Bool {
        windowState.controlIsland.configuration.restsWhenIdle && (state.isQuiet || !appearsActive) && !state.isEngaged
    }

    private var glass: Glass {
        isResting && !reduceTransparency ? .clear : .regular
    }

    private var restAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.4)
    }

    var body: some View {
        @Bindable var state = windowState.fileIsland
        ZStack(alignment: .topLeading) {
            if isShown {
                column
                    .frame(width: frame.width, height: frame.height)
                    .environment(\.controlIslandIsResting, isResting)
                    .background(windowState.controlIslandTint.opacity(isResting ? 0 : 1), in: .rect(cornerRadius: Placement.cornerRadius))
                    .background(Color.appAccentColor.opacity(state.drop == .island ? 0.18 : 0), in: .rect(cornerRadius: Placement.cornerRadius))
                    .glassEffect(glass, in: .rect(cornerRadius: Placement.cornerRadius))
                    .overlay {
                        if state.drop == .island {
                            RoundedRectangle(cornerRadius: Placement.cornerRadius)
                                .strokeBorder(Color.appAccentColor, lineWidth: Placement.highlightLineWidth)
                                .shadow(color: Color.appAccentColor.opacity(Placement.highlightGlowOpacity), radius: Placement.highlightGlowRadius)
                                .allowsHitTesting(false)
                                .transition(.opacity)
                        }
                    }
                    .popover(isPresented: $state.showsAll, arrowEdge: opensLeft ? .leading : .trailing) {
                        FileIslandAllFiles(actions: actions)
                            .readablePopoverBackground()
                    }
                    .offset(x: frame.minX, y: frame.minY)
                    .transition(.opacity)
                if state.isDragging {
                    snapGuide
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .font(.system(size: 13, weight: Placement.symbolWeight))
        .buttonStyle(ControlIslandButtonStyle())
        .onChange(of: isShown ? frame : .zero, initial: true) { _, frame in
            state.frame = frame
            state.hitRegions = frame.isEmpty ? [] : [frame]
        }
        .onChange(of: isDraggingIsland) { _, dragging in
            state.isDragging = dragging
            if !dragging {
                finishIslandDrag()
            }
        }
        .onChange(of: downloadManager.activeDownloadCount) { previous, count in
            if count > previous {
                state.holdAwake(for: FileIslandState.arrivalHold)
            }
        }
        .onChange(of: downloadManager.latestCompletionDate) {
            now = Date()
        }
        .onChange(of: shelf.items.count) { previous, count in
            if count > previous {
                state.holdAwake(for: FileIslandState.arrivalHold)
            }
        }
        .onChange(of: showsDropCell) { _, dragging in
            if dragging {
                state.wake()
            }
        }
        .task(id: nextExpiry) {
            guard let nextExpiry else { return }
            try? await Task.sleep(for: .seconds(max(0.1, nextExpiry.timeIntervalSinceNow)))
            guard !Task.isCancelled else { return }
            now = Date()
        }
        .onDisappear {
            state.frame = .zero
            state.hitRegions = []
            state.isHovered = false
            state.isDragging = false
            state.setDrop(.none)
            dragOrigin = nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("File Island")
        .accessibilityIdentifier("browser-file-island")
        .animation(restAnimation, value: isResting)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: isShown)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: height)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: state.drop)
    }

    // MARK: - Column

    private var column: some View {
        let allocation = allocation
        let downloads = downloads
        return VStack(spacing: 0) {
            if showsDropCell {
                dropCell
            }
            ForEach(downloads.prefix(allocation.downloads)) { download in
                FileIslandDownloadCell(download: download, actions: actions)
            }
            if allocation.downloads > 0, allocation.shelf > 0 {
                draggableBackground(Divider().frame(height: Placement.sectionGap).contentShape(Rectangle()))
            }
            ForEach(shelf.items.prefix(allocation.shelf)) { item in
                FileIslandShelfCell(item: item, actions: actions)
            }
            overflowRow(hidden: allocation.hidden)
            grip
        }
        .padding(.top, Placement.contentInset)
        .padding(.bottom, Placement.gripBottomInset)
        .padding(.horizontal, Placement.horizontalInset)
        .background { draggableBackground(Color.clear.contentShape(Rectangle())) }
    }

    /// The place to drop while a drag is over the window; it lights as the drag reaches the island.
    private var dropCell: some View {
        let isTarget = state.drop == .island
        return Image(systemName: isTarget ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
            .font(.system(size: 15, weight: Placement.symbolWeight))
            .foregroundStyle(isTarget ? AnyShapeStyle(Color.appAccentColor) : AnyShapeStyle(.primary))
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            .frame(width: Layout.cellSize, height: Layout.cellSize)
            .accessibilityLabel(isTarget ? "Release to keep on the File Island" : "Drop here to keep on the File Island")
    }

    /// Opens the full lists; it counts the files the column has no room for.
    private func overflowRow(hidden: Int) -> some View {
        Button {
            state.showsAll.toggle()
        } label: {
            ControlIslandRow {
                if hidden > 0 {
                    Text("+\(hidden)")
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                } else {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .help(hidden > 0 ? "Show \(hidden) more and all downloads · ⌥⌘L" : "Show all downloads and shelf items · ⌥⌘L")
        .accessibilityLabel("All files")
        .accessibilityValue(hidden > 0 ? "\(hidden) more" : "")
    }

    // MARK: - Moving

    /// Empty glass drags the window natively, as it does on the Control Island.
    private func draggableBackground(_ content: some View) -> some View {
        content.gesture(WindowDragGesture().updating($isDraggingWindow) { _, dragging, _ in dragging = true })
    }

    /// The Control Island's 3 × 2 dot grip, closing the column; it fades with the glass at rest.
    private var grip: some View {
        Grid(horizontalSpacing: Placement.gripDotSpacing, verticalSpacing: Placement.gripDotSpacing) {
            ForEach(0 ..< Placement.gripRows, id: \.self) { _ in
                GridRow {
                    ForEach(0 ..< Placement.gripColumns, id: \.self) { _ in
                        Circle()
                            .fill(.secondary)
                            .frame(width: Placement.gripDot, height: Placement.gripDot)
                    }
                }
            }
        }
        .frame(width: Placement.gripSize.width, height: Placement.gripSize.height)
        .opacity(isResting ? 0 : 1)
        .frame(width: Placement.contentWidth, height: Placement.gripGap + Placement.gripSize.height, alignment: .bottom)
        .contentShape(Rectangle())
        .gesture(moveGesture)
        .contextMenu {
            Button("Reset Position") { resetPlacement() }
        }
        .help("Move the File Island")
        .accessibilityElement()
        .accessibilityLabel("Move the File Island")
        .accessibilityAction(named: "Move left") { moveBy(dx: -32, dy: 0) }
        .accessibilityAction(named: "Move right") { moveBy(dx: 32, dy: 0) }
        .accessibilityAction(named: "Move up") { moveBy(dx: 0, dy: -32) }
        .accessibilityAction(named: "Move down") { moveBy(dx: 0, dy: 32) }
    }

    /// The dashed outline of where the island will settle when released.
    @ViewBuilder
    private var snapGuide: some View {
        let snap = placement.snapped(in: area, height: height)
        if snap != placement {
            let target = snap.railFrame(in: area, height: height)
            RoundedRectangle(cornerRadius: Placement.cornerRadius)
                .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: target.width, height: target.height)
                .offset(x: target.minX, y: target.minY)
                .allowsHitTesting(false)
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(FileIslandLayer.coordinateSpace))
            .updating($isDraggingIsland) { _, dragging, _ in dragging = true }
            .onChanged { value in
                let origin = dragOrigin ?? frame.origin
                dragOrigin = origin
                state.isDragging = true
                var next = placement
                next.move(to: CGPoint(x: origin.x + value.translation.width, y: origin.y + value.translation.height), in: area, height: height)
                state.placement = next
            }
            .onEnded { _ in finishIslandDrag() }
    }

    private func finishIslandDrag() {
        guard dragOrigin != nil else { return }
        dragOrigin = nil
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
            state.placement = placement.snapped(in: area, height: height)
        }
        windowState.window?.invalidateRestorableState()
    }

    private func moveBy(dx: CGFloat, dy: CGFloat) {
        var next = placement
        next.move(to: CGPoint(x: frame.minX + dx, y: frame.minY + dy), in: area, height: height)
        state.placement = next
        windowState.window?.invalidateRestorableState()
    }

    private func resetPlacement() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
            state.placement = nil
        }
        windowState.window?.invalidateRestorableState()
    }
}

/// The File Island shares window coordinates with the page, above the Control Island's layer.
struct FileIslandLayer: View {
    static let coordinateSpace = "fileIsland"

    @Environment(TabCanvasManager.self) private var canvas
    @Environment(BrowserSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            if canvas.showsFloatingControls, canvas.regionSelection == nil {
                FileIsland(area: CGRect(origin: .zero, size: geometry.size))
            }
        }
        .coordinateSpace(name: Self.coordinateSpace)
        .ignoresSafeArea()
        .environment(\.colorScheme, settings.theme.colorScheme ?? colorScheme)
    }
}
