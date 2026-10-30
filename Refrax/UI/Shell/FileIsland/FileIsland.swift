import AppKit
import SwiftUI

/// The browser's place for things that are files: downloads in progress and from the last
/// hour, then the shelf of dropped images, text, links, and files.
///
/// A small sibling of the Control Island in the same 48-point column, glass, tint, rest and
/// wake, grip, and snapping. It exists only while it holds something, while its full list is
/// open, or while a file, image, text, or link is dragged over the window, when it shows itself
/// as the place to drop and brightens as the drag reaches it. Snapped to the window's left or
/// right edge it hides past that edge while idle, by default, and comes back to the pointer.
///
/// Dropped at the seam under the rail's bottom end, it couples there: the rail's bottom edge
/// places it, so it follows as the rail grows, moves with it, and hides and returns with it.
/// A pull past a little magnetic resistance sets it free again.
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
    /// How far a coupled island gives to a pull before it pops free.
    @State private var pull = CGSize.zero
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
        if case let .full(limit) = couplingFit {
            return allocation(limit: limit)
        }
        return allocation(limit: Layout.visibleLimit(in: area, showsDropCell: showsDropCell))
    }

    private func allocation(limit: Int) -> FileIslandAllocation {
        FileIslandAllocation(downloads: downloads.count, shelf: shelf.items.count, limit: limit)
    }

    // MARK: - Geometry

    private var rail: ControlIslandState {
        windowState.controlIsland
    }

    /// The rail's frame while the island is coupled under it and the rail is in the window.
    private var couplingRail: CGRect? {
        guard state.isCoupled, !rail.railLayoutFrame.isEmpty else { return nil }
        return rail.railLayoutFrame
    }

    private var couplingFit: FileIslandCoupling.Fit? {
        couplingRail.map { FileIslandCoupling.fit(below: $0, in: area, showsDropCell: showsDropCell) }
    }

    /// Coupled under a rail with no room for files: one cell with an icon and a count.
    private var isCompact: Bool {
        switch couplingFit {
        case .compact, .beside: true
        case .full, nil: false
        }
    }

    private var height: CGFloat {
        height(for: couplingFit)
    }

    private func height(for fit: FileIslandCoupling.Fit?) -> CGFloat {
        let allocation: FileIslandAllocation
        switch fit {
        case .compact, .beside:
            return Layout.compactHeight
        case let .full(limit):
            allocation = self.allocation(limit: limit)
        case nil:
            allocation = self.allocation
        }
        return Layout.height(downloads: allocation.downloads, shelf: allocation.shelf, showsDropCell: showsDropCell)
    }

    private var placement: ControlIslandPlacement {
        state.placement ?? Layout.defaultPlacement(oppositeOf: windowState.controlIsland.placement)
    }

    /// Under the rail while coupled, giving a little to a pull; otherwise at its own placement.
    private var frame: CGRect {
        if let rail = couplingRail, let fit = couplingFit {
            return FileIslandCoupling.frame(for: fit, height: height, below: rail, in: area)
                .offsetBy(dx: pull.width, dy: pull.height)
        }
        return placement.railFrame(in: area, height: height)
    }

    /// Where the island would settle under `rail` if it coupled now.
    private func coupledTarget(under rail: CGRect) -> CGRect {
        let fit = FileIslandCoupling.fit(below: rail, in: area, showsDropCell: showsDropCell)
        return FileIslandCoupling.frame(for: fit, height: height(for: fit), below: rail, in: area)
    }

    private var opensLeft: Bool {
        frame.midX > area.midX
    }

    // MARK: - Hiding at the Edge

    /// The window side the island hides past: the side it is snapped to, while Hide at the Edge is
    /// on. A coupled island hides with the rail instead.
    private var hiddenEdge: ControlIslandPlacement.Edge? {
        guard couplingRail == nil else { return nil }
        return windowState.controlIsland.configuration.fileIslandHidesAtEdge ? placement.horizontalEdge : nil
    }

    private var isHiddenAtEdge: Bool {
        guard isShown else { return false }
        return couplingRail == nil ? state.isHiddenAtEdge : rail.isHiddenAtEdge
    }

    /// The edge the island is away past: its own, or the rail's while coupled.
    private var awayEdge: ControlIslandPlacement.Edge? {
        couplingRail == nil ? state.hiddenEdge : rail.hiddenEdge
    }

    /// Where the island draws: its frame, or past the window edge while hidden there. Under
    /// Reduce Motion it stays in place and fades instead.
    private var displayFrame: CGRect {
        guard isHiddenAtEdge, !reduceMotion, let edge = awayEdge else { return frame }
        return Placement.hiddenFrame(for: frame, at: edge, in: area)
    }

    /// The strip along the window edge that brings the hidden island back.
    private var revealStrip: CGRect {
        guard isShown, let edge = hiddenEdge else { return .zero }
        return Placement.revealStrip(for: frame, at: edge, in: area)
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
                    .opacity(isHiddenAtEdge && reduceMotion ? 0 : 1)
                    .offset(x: displayFrame.minX, y: displayFrame.minY)
                    .transition(.opacity)
                if isHiddenAtEdge, couplingRail == nil, let edge = state.hiddenEdge {
                    flap(at: edge)
                }
                if state.isDragging {
                    if state.couplesOnRelease {
                        couplingPreview
                    } else if !state.isCoupled {
                        snapGuide
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .font(.system(size: 13, weight: Placement.symbolWeight))
        .buttonStyle(ControlIslandButtonStyle())
        .onChange(of: isShown && !isHiddenAtEdge ? frame : .zero, initial: true) { _, frame in
            state.frame = frame
            state.hitRegions = frame.isEmpty ? [] : [frame]
        }
        .onChange(of: couplingRail != nil && isShown ? frame : .zero, initial: true) { _, frame in rail.companionFrame = frame }
        .onChange(of: couplingRail != nil && state.isEngaged, initial: true) { _, engaged in rail.companionIsEngaged = engaged }
        .onChange(of: hiddenEdge, initial: true) { _, edge in state.hiddenEdge = edge }
        .onChange(of: revealStrip, initial: true) { _, strip in state.revealStrip = strip }
        .onChange(of: isDraggingIsland) { _, dragging in
            state.isDragging = dragging
            if !dragging {
                finishIslandDrag()
            }
        }
        .onChange(of: downloadManager.activeDownloadCount) { previous, count in
            if count > previous {
                state.holdAwake(for: FileIslandState.arrivalHold)
                revealWithRail()
            }
        }
        .onChange(of: downloadManager.latestCompletionDate) {
            now = Date()
        }
        .onChange(of: shelf.items.count) { previous, count in
            if count > previous {
                state.holdAwake(for: FileIslandState.arrivalHold)
                revealWithRail()
            }
        }
        .onChange(of: showsDropCell) { _, dragging in
            if dragging {
                state.wake()
                revealWithRail()
            }
        }
        .onChange(of: state.showsAll) { _, shows in
            if shows {
                revealWithRail()
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
            state.revealStrip = .zero
            state.isHovered = false
            state.isDragging = false
            state.setDrop(.none)
            state.couplesOnRelease = false
            rail.companionFrame = .zero
            rail.companionIsEngaged = false
            dragOrigin = nil
            pull = .zero
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("File Island")
        .accessibilityIdentifier("browser-file-island")
        .animation(restAnimation, value: isResting)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.28), value: isHiddenAtEdge)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: isShown)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: height)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: state.drop)
        .animation(followsRailAnimation, value: couplingRail)
        .animation(reduceMotion ? nil : .interactiveSpring(duration: 0.2), value: pull)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: state.couplesOnRelease)
    }

    /// A coupled island glides after the rail as it grows or yields, and keeps pace with a drag.
    private var followsRailAnimation: Animation? {
        reduceMotion || rail.isDragging || state.isDragging ? nil : .snappy(duration: 0.28)
    }

    /// A coupled island brings a rail hidden at the edge back when something arrives on it.
    private func revealWithRail() {
        if couplingRail != nil {
            rail.revealAtEdge(.request)
        }
    }

    // MARK: - Column

    @ViewBuilder
    private var column: some View {
        if isCompact {
            compactColumn
        } else {
            fullColumn
        }
    }

    private var fullColumn: some View {
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

    /// The column coupled under a rail with no room for files: an icon and a count that open the
    /// full lists, and the grip.
    private var compactColumn: some View {
        let count = downloads.count + shelf.items.count
        let isTarget = state.drop == .island
        let symbol = if showsDropCell {
            isTarget ? "tray.and.arrow.down.fill" : "tray.and.arrow.down"
        } else if downloads.contains(where: { $0.state.isActive }) {
            "arrow.down.circle"
        } else {
            "tray.full"
        }
        return VStack(spacing: 0) {
            Button {
                state.showsAll.toggle()
            } label: {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: Placement.symbolWeight))
                    .foregroundStyle(isTarget ? AnyShapeStyle(Color.appAccentColor) : AnyShapeStyle(.primary))
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    .frame(width: Layout.cellSize, height: Layout.cellSize)
                    .overlay(alignment: .bottomTrailing) {
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 9, weight: .semibold))
                                .monospacedDigit()
                                .padding(.horizontal, 3)
                                .background(.quaternary, in: .capsule)
                                .padding(2)
                        }
                    }
                    .contentShape(Rectangle())
            }
            .help("Show all downloads and shelf items · ⌥⌘L")
            .accessibilityLabel("All files")
            .accessibilityValue(count == 1 ? "1 file" : "\(count) files")
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
            Toggle(Placement.edgeHidingTitle, isOn: Binding(
                get: { windowState.controlIsland.configuration.fileIslandHidesAtEdge },
                set: { windowState.controlIsland.configuration.setFileIslandHidesAtEdge($0) },
            ))
            .help("Against the window's left or right edge, the File Island slides away while nothing on it is in progress; it returns when the pointer reaches that edge or a download starts")
            .disabled(state.isCoupled)
            Button(state.isCoupled ? "Uncouple from Controls" : "Couple Under Controls") { setCoupled(!state.isCoupled) }
                .help("Coupled, the File Island sits under the controls, follows them as they grow, and moves and hides with them")
            Button("Reset Position") { resetPlacement() }
        }
        .help("Move the File Island")
        .accessibilityElement()
        .accessibilityLabel("Move the File Island")
        .accessibilityAction(named: state.isCoupled ? "Uncouple from controls" : "Couple under controls") { setCoupled(!state.isCoupled) }
        .accessibilityAction(named: "Move left") { moveBy(dx: -32, dy: 0) }
        .accessibilityAction(named: "Move right") { moveBy(dx: 32, dy: 0) }
        .accessibilityAction(named: "Move up") { moveBy(dx: 0, dy: -32) }
        .accessibilityAction(named: "Move down") { moveBy(dx: 0, dy: 32) }
    }

    /// The sliver of glass on the edge that marks where the hidden island is, as the rail's does.
    private func flap(at edge: ControlIslandPlacement.Edge) -> some View {
        let flap = CGRect(
            x: edge == .left ? area.minX : area.maxX - Placement.flapWidth,
            y: min(max(area.minY, frame.midY - Placement.flapHeight / 2), area.maxY - Placement.flapHeight),
            width: Placement.flapWidth, height: Placement.flapHeight,
        )
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: edge == .left ? 0 : Placement.flapWidth, bottomLeadingRadius: edge == .left ? 0 : Placement.flapWidth,
            bottomTrailingRadius: edge == .left ? Placement.flapWidth : 0, topTrailingRadius: edge == .left ? Placement.flapWidth : 0,
        )
        return shape.fill(windowState.controlIslandTint)
            .glassEffect(.regular, in: shape)
            .frame(width: flap.width, height: flap.height)
            .offset(x: flap.minX, y: flap.minY)
            .transition(.opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
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

    /// The coupling preview: the place under the rail the island will settle, outlined in the
    /// accent color, and the seam between them glowing.
    @ViewBuilder
    private var couplingPreview: some View {
        let railFrame = rail.railLayoutFrame
        if !railFrame.isEmpty {
            let target = coupledTarget(under: railFrame)
            let seam = FileIslandCoupling.seamFrame(below: railFrame)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Placement.cornerRadius)
                    .strokeBorder(Color.appAccentColor.opacity(0.7), lineWidth: 1)
                    .frame(width: target.width, height: target.height)
                    .offset(x: target.minX, y: target.minY)
                Capsule()
                    .fill(Color.appAccentColor)
                    .shadow(color: Color.appAccentColor.opacity(Placement.highlightGlowOpacity), radius: Placement.highlightGlowRadius)
                    .frame(width: seam.width, height: seam.height)
                    .offset(x: seam.minX, y: seam.minY)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.opacity)
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(FileIslandLayer.coordinateSpace))
            .updating($isDraggingIsland) { _, dragging, _ in dragging = true }
            .onChanged { value in
                let origin = dragOrigin ?? frame.origin
                if dragOrigin == nil {
                    dragOrigin = origin
                }
                if !state.isDragging {
                    state.isDragging = true
                }
                let point = CGPoint(x: origin.x + value.translation.width, y: origin.y + value.translation.height)
                if couplingRail != nil {
                    // Held by the rail: it gives a little, then pops free under the pointer.
                    if let offset = FileIslandCoupling.resistedOffset(for: value.translation) {
                        pull = offset
                        return
                    }
                    var next = placement
                    next.move(to: point, in: area, height: height(for: nil))
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.16)) {
                        pull = .zero
                        state.isCoupled = false
                        state.placement = next
                    }
                    return
                }
                var next = placement
                next.move(to: point, in: area, height: height)
                // Same-value writes are skipped: each one re-evaluates the island and the rail.
                if state.placement != next {
                    state.placement = next
                }
                let couples = FileIslandCoupling.isAtSeam(next.railFrame(in: area, height: height), rail: rail.railLayoutFrame)
                if state.couplesOnRelease != couples {
                    state.couplesOnRelease = couples
                }
            }
            .onEnded { _ in finishIslandDrag() }
    }

    private func finishIslandDrag() {
        guard dragOrigin != nil else { return }
        dragOrigin = nil
        let couples = state.couplesOnRelease
        state.couplesOnRelease = false
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
            pull = .zero
            if couplingRail == nil {
                state.placement = placement.snapped(in: area, height: height)
            }
            if couples {
                state.isCoupled = true
            }
        }
        state.savePlacement()
        windowState.window?.invalidateRestorableState()
    }

    private func setCoupled(_ coupled: Bool) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
            if !coupled, couplingRail != nil {
                // Freed from the menu, it stays where it was.
                var next = placement
                next.move(to: frame.origin, in: area, height: height(for: nil))
                state.placement = next.snapped(in: area, height: height(for: nil))
            }
            state.isCoupled = coupled
        }
        state.savePlacement()
        windowState.window?.invalidateRestorableState()
    }

    private func moveBy(dx: CGFloat, dy: CGFloat) {
        if state.isCoupled {
            setCoupled(false)
        }
        var next = placement
        next.move(to: CGPoint(x: frame.minX + dx, y: frame.minY + dy), in: area, height: height)
        state.placement = next
        state.savePlacement()
        windowState.window?.invalidateRestorableState()
    }

    private func resetPlacement() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
            state.isCoupled = false
            state.placement = nil
        }
        state.savePlacement()
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
