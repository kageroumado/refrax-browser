import AppKit
import SwiftUI

/// Keeps the webpage interactive between the floating cards.
final class FloatingTabsHostingView<Content: View>: NSHostingView<Content> {
    var hitRegions: () -> [CGRect] = { [] }
    var onPointerDown: ((CGPoint) -> Void)?
    /// A right-click at a point; returns whether it was handled, which keeps it from the page.
    var onSecondaryPointerDown: ((CGPoint, NSEvent) -> Bool)?
    var controlState: (() -> ControlIslandState?)?
    private var pointerMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let pointerMonitor {
            NSEvent.removeMonitor(pointerMonitor)
        }
        pointerMonitor = nil
        guard window != nil else { return }
        window?.acceptsMouseMovedEvents = true
        pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]) { [weak self] event in
            guard let self, event.window === window else { return event }
            let point = topLeadingPoint(convert(event.locationInWindow, from: nil))
            if event.type == .mouseMoved {
                controlState?()?.pointerMoved?(point)
                return event
            }
            if event.type == .leftMouseDown {
                onPointerDown?(point)
            }
            if event.type == .rightMouseDown, onSecondaryPointerDown?(point, event) == true {
                return nil
            }
            guard let state = controlState?(),
                  !state.isPresenting, !state.hitRegions.isEmpty else { return event }
            state.dismissIfOutside(point)
            return event
        }
    }

    isolated deinit {
        if let pointerMonitor {
            NSEvent.removeMonitor(pointerMonitor)
        }
    }

    private func topLeadingPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = topLeadingPoint(convert(point, from: superview))
        guard hitRegions().contains(where: { $0.contains(local) }) else { return nil }
        return super.hitTest(point)
    }
}

/// Instant access to placed tabs, with live pinned pages beside the main page.
struct FloatingTabsLayer: View {
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(WindowState.self) private var windowState
    @Environment(BrowserSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            ZStack(alignment: .topLeading) {
                FloatingDockLayer(area: bounds)
                if canvas.floatingVisibility.isRevealed && !canvas.isMomentaryNavigation {
                    FloatingLassoSurface(area: bounds)
                    ForEach(canvas.flattenedFloatingGroupItems(in: bounds)) { item in
                        FloatingTabGroup(item: item, area: bounds)
                    }
                }
                ForEach(canvas.visibleFloatingTabs.filter { $0.id != windowState.activeTabID }) { tab in
                    let placement = canvas.floatingPlacement(for: tab)
                    let frame = canvas.floatingFrame(for: tab, in: bounds)
                    let fold = canvas.foldOrigin(for: tab, in: bounds)
                    FloatingTabCard(tab: tab, placement: placement, area: bounds)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .zIndex(tab.id == canvas.focusedFloatingTabID ? 1 : 0)
                        .transition(.fold(toward: fold.map { CGSize(width: $0.x - frame.minX, height: $0.y - frame.minY) }))
                }
                FloatingCardGroupTarget(area: bounds)
                FloatingSelectionCapsule(area: bounds)
                if let request = canvas.rayRequest, let tab = canvas.floatingTabs.first(where: { $0.id == request.tabID }) {
                    FloatingRayView(path: FloatingRayPath(from: request.source, to: canvas.floatingFrame(for: tab, in: bounds), in: bounds)) {
                        canvas.finishRay(request.revision)
                    }
                    .id(request.revision)
                }
                FloatingDockBeams(area: bounds)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .coordinateSpace(name: "floatingTabs")
            .dropDestination(for: FloatingTabDrag.self) { items, point in
                guard let item = items.first, let tab = canvas.floatingTabs.first(where: { $0.id == item.id }) else { return false }
                var placement = canvas.floatingPlacement(for: tab)
                placement.move(to: point, in: bounds)
                canvas.updateFloatingPlacement(placement, for: tab)
                canvas.joinGroup(at: point, tabs: [tab], in: bounds)
                canvas.draggedRecentTabID = nil
                canvas.recentIsOpen = false
                return true
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

/// A tab as a card over the page: its icon, its title, or its live page, moved by its header.
struct FloatingTabCard: View {
    let tab: Tab
    let placement: FloatingTabPlacement
    let area: CGRect

    @Environment(TabCanvasManager.self) private var canvas
    @Environment(WindowState.self) private var windowState
    @Environment(IslandController.self) private var islands
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var faviconSpace
    /// The card's frame when the current resize began; its sides opposite the handle stay put.
    @State private var resizeStart: CGRect?
    /// When the current resize last changed the shape: updates while that motion runs join it.
    @State private var shapeChangedAt: Date?
    @State private var isHovering = false
    /// The pointer was on the card within the last ``Layout/liveLinger``, so its page stays live.
    @State private var wantsLive = false
    @State private var tearOff: FloatingTearOffGhost?
    @State private var isOutsideWindow = false

    private typealias Header = FloatingCardChrome.Header
    private typealias ShapeLayout = FloatingCardShape.Layout

    private enum Layout {
        /// The card's opacity while a copy of it follows the pointer outside the window.
        static let leavingOpacity: Double = 0.4
        static let moveStep: CGFloat = 24
        /// How far the icon's state badge reaches past its top-trailing corner.
        static let iconBadgeOffset: CGFloat = 8
        static let iconBadgePadding: CGFloat = 2
        /// How long a resize keeps animating after a shape change: the spring's duration.
        static let shapeMotionDuration: TimeInterval = 0.2
        /// How long a card keeps its page live after the pointer leaves it.
        static let liveLinger: Duration = .seconds(1)
    }

    private var shape: FloatingCardShape {
        placement.shape
    }
    private var isMainPage: Bool {
        tab.id == windowState.activeTabID
    }
    private var hasInput: Bool {
        windowState.focusedPage?.tab?.id == tab.id && !isMainPage
    }
    private var isKept: Bool {
        placement.isPinned
    }
    private var outline: RoundedRectangle {
        RoundedRectangle(cornerRadius: FloatingCardChrome.cornerRadius(for: shape, isKept: isKept), style: .continuous)
    }
    /// The header's controls show while the pointer is on the card or its options are open.
    private var showsControls: Bool {
        isHovering || canvas.menuTabID == tab.id
    }
    /// A live-shape card draws its page while the pointer is on it or just left, while it
    /// takes input, while it is kept visible, or while it shows a region; otherwise it shows
    /// its snapshot, so a peek at the floating layer draws no pages.
    private var showsLivePage: Bool {
        wantsLive || hasInput || isKept || canvas.retainedInputTabID == tab.id || placement.region != nil
    }
    private var isHighlighted: Bool {
        canvas.selectedFloatingTabIDs.contains(tab.id) || hasInput
            || (tab.id == canvas.focusedFloatingTabID && canvas.floatingVisibility.isRevealed)
    }

    var body: some View {
        let shadow = FloatingCardChrome.shadow(isKept: isKept)
        ZStack(alignment: .top) {
            if shape == .icon {
                iconFace
                    .transition(.opacity)
            } else {
                VStack(spacing: 0) {
                    header
                        .frame(height: Header.height)
                    if shape == .live {
                        FloatingTabPreview(tab: tab, viewportSize: area.size, isLive: showsLivePage)
                            .frame(height: max(0, placement.frame(in: area).height - Header.height - FloatingTabPlacement.previewInset))
                            .clipShape(.rect(cornerRadius: FloatingCardChrome.previewCornerRadius(isKept: isKept), style: .continuous))
                            .padding([.horizontal, .bottom], FloatingTabPlacement.previewInset)
                            .transition(.opacity)
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .transaction(value: shape) { transaction in
            if reduceMotion {
                transaction.animation = ShapeLayout.reducedMotionFade
            }
        }
        .glassEffect(.regular, in: outline)
        .overlay {
            outline
                .strokeBorder(isHighlighted ? Color.appAccentColor : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            if !isMainPage {
                resizeHandles
            }
        }
        .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
        .opacity(isOutsideWindow ? Layout.leavingOpacity : 1)
        .onHover { isHovering = $0 }
        .task(id: isHovering) {
            if isHovering {
                wantsLive = true
                return
            }
            try? await Task.sleep(for: Layout.liveLinger)
            if !Task.isCancelled {
                wantsLive = false
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Floating tab, \(tab.displayTitle)")
        .accessibilityValue(isKept ? "Kept visible" : "")
        .accessibilityIdentifier("floating-tab-\(tab.id.uuidString)")
        .closesOnMiddleClick(tab)
    }

    // MARK: Faces

    /// The favicon, one object across shapes: it travels between the icon's center and the
    /// header's leading edge as the shape changes.
    private func favicon(side: CGFloat) -> some View {
        Group {
            if let data = tab.activePage.faviconData, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "globe").resizable().scaledToFit()
            }
        }
        .frame(width: side, height: side)
        .modifier(FaviconTravel(id: tab.id, namespace: faviconSpace, isEnabled: !reduceMotion))
    }

    /// The icon shape: the favicon alone, its state as a badge on the top-trailing corner,
    /// and the title in the tooltip. The badge reads as state only; the corner under it
    /// resizes the card.
    private var iconFace: some View {
        cardHandle(
            favicon(side: ShapeLayout.iconFaviconSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity),
        )
        .help(tab.displayTitle)
        .overlay(alignment: .topTrailing) {
            TabStateSymbols(tab: tab)
                .padding(.horizontal, Layout.iconBadgePadding)
                .background(.regularMaterial, in: Capsule())
                .fixedSize()
                .offset(x: Layout.iconBadgeOffset, y: -Layout.iconBadgeOffset)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .topLeading) {
            // An icon has no header, so its way back to its island shows on its corner on hover.
            if showsControls {
                light(.yellow, symbol: "minus", "Back to Its Island") { islands.returnToIsland(tab.id) }
                    .background(.regularMaterial, in: Circle())
                    .offset(x: -Layout.iconBadgeOffset, y: -Layout.iconBadgeOffset)
            }
        }
    }

    /// A title bar: a window's three lights at the leading edge, then favicon, title, and
    /// state; the options join them on hover. The header is the card's drag handle.
    private var header: some View {
        HStack(spacing: 0) {
            lights
            cardHandle(HStack(spacing: Header.itemSpacing) {
                favicon(side: Header.glyphBox)
                FloatingTabTitle(tab: tab)
                TabStateSymbols(tab: tab)
                Spacer(minLength: 0)
            })

            if canvas.retainedInputTabID == tab.id, !canvas.floatingVisibility.isRevealed {
                Button("Finish") { canvas.finishPreviewInteraction() }
                    .labelStyle(.titleOnly)
                    .padding(.leading, Header.itemSpacing)
            }
            if showsControls {
                PageActionsMenu(tab: tab, surface: .floatingCard, area: area)
                    .frame(width: Header.controlSize, height: Header.controlSize)
            }
        }
        .labelStyle(.iconOnly)
        .controlSize(.small)
        .buttonStyle(.plain)
        .padding(.leading, Header.leadingPadding)
        .padding(.trailing, showsControls ? Header.trailingPadding : Header.leadingPadding)
    }

    /// The three lights a window has, in the order and colors people know, a shade fainter:
    /// red closes the tab, yellow puts the card back in its island, green opens it as the page.
    /// Their glyphs show while the pointer is on the card.
    private var lights: some View {
        HStack(spacing: Header.lightSpacing) {
            light(.red, symbol: "xmark", "Close Tab") { canvas.tabManager.requestCloseTab(tab) }
            light(.yellow, symbol: "minus", "Back to Its Island") { islands.returnToIsland(tab.id) }
            light(.green, symbol: "arrow.up.left.and.arrow.down.right", "Open as the Page") { islands.open(tab) }
        }
        .padding(.trailing, Header.itemSpacing)
    }

    private func light(_ color: Color, symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color.opacity(Header.lightOpacity))
                    .overlay { Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5) }
                    .frame(width: Header.lightSize, height: Header.lightSize)
                if isHovering {
                    Image(systemName: symbol)
                        .font(.system(size: Header.lightGlyphSize, weight: .bold))
                        .foregroundStyle(.black.opacity(0.55))
                }
            }
            .frame(width: Header.lightTarget, height: Header.lightTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }

    // MARK: Resizing

    /// Eight invisible zones on the card's outer edge, one per corner and edge, each with its
    /// window resize pointer.
    private var resizeHandles: some View {
        GeometryReader { proxy in
            ForEach(FloatingResizeHandle.allCases, id: \.self) { handle in
                let zone = handle.hitFrame(
                    in: proxy.size, thickness: ShapeLayout.resizeEdgeThickness, corner: ShapeLayout.resizeCornerSide,
                )
                Color.clear
                    .frame(width: zone.width, height: zone.height)
                    .contentShape(Rectangle())
                    .pointerStyle(.frameResize(position: handle.pointerPosition))
                    .gesture(resizeGesture(handle))
                    .offset(x: zone.minX, y: zone.minY)
                    .accessibilityHidden(true)
            }
        }
    }

    private func resizeGesture(_ handle: FloatingResizeHandle) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("floatingTabs"))
            .onChanged { value in
                canvas.beginFloatingManipulation()
                let start = resizeStart ?? placement.frame(in: area)
                resizeStart = start
                var next = placement
                if next.resize(dragging: handle, from: start, by: value.translation, in: area) {
                    shapeChangedAt = .now
                }
                let joinsShapeMotion = shapeChangedAt.map { Date.now.timeIntervalSince($0) < Layout.shapeMotionDuration } ?? false
                if joinsShapeMotion {
                    withAnimation(TabCanvasManager.shapeAnimation) {
                        canvas.updateFloatingPlacement(next, for: tab)
                    }
                } else {
                    canvas.updateFloatingPlacement(next, for: tab)
                }
            }
            .onEnded { _ in
                resizeStart = nil
                shapeChangedAt = nil
                canvas.endFloatingManipulation()
            }
    }


    // MARK: Moving

    /// Makes `content` the card's handle: a click opens the card, a Shift-click toggles its
    /// selection, and a drag moves it.
    private func cardHandle(_ content: some View) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                if NSEvent.modifierFlags.contains(.shift) {
                    if canvas.selectedFloatingTabIDs.contains(tab.id) {
                        canvas.selectedFloatingTabIDs.remove(tab.id)
                    } else {
                        canvas.selectedFloatingTabIDs.insert(tab.id)
                    }
                } else {
                    canvas.openFloatingTab(tab)
                }
            }
            .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("floatingTabs"))
                .onChanged { value in
                    canvas.dragFloatingCard(tab, translation: value.translation, pointer: value.location, in: area)
                    followTearOff(from: value.startLocation)
                }
                .onEnded { _ in
                    endHeaderDrag()
                })
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { canvas.openFloatingTab(tab) }
            .accessibilityAction(named: "Move left") { moveBy(dx: -Layout.moveStep, dy: 0) }
            .accessibilityAction(named: "Move right") { moveBy(dx: Layout.moveStep, dy: 0) }
            .accessibilityAction(named: "Move up") { moveBy(dx: 0, dy: -Layout.moveStep) }
            .accessibilityAction(named: "Move down") { moveBy(dx: 0, dy: Layout.moveStep) }
            .accessibilityActions {
                if !isMainPage {
                    ForEach(FloatingCardShape.allCases.filter { $0 != shape }, id: \.self) { other in
                        Button(other.showTitle) { canvas.setFloatingShape(other, for: tab, in: area) }
                    }
                }
            }
    }

    // MARK: Leaving the Window

    /// Shows a copy of the card under the pointer once it is outside the window.
    private func followTearOff(from start: CGPoint) {
        guard canvas.canTearOff(tab), let window = windowState.window else { return }
        let pointer = NSEvent.mouseLocation
        let isOutside = FloatingTearOff.isTornOff(pointer: pointer, from: window.frame)
        if tearOff == nil, isOutside, let origin = canvas.floatingMoveOrigins[tab.id] {
            tearOff = FloatingTearOffGhost(
                tab: tab, snapshot: canvas.snapshots[tab.id], placement: placement,
                size: placement.frame(in: area).size, grab: CGPoint(x: start.x - origin.x, y: start.y - origin.y),
            )
        }
        tearOff?.follow(pointer, isOutside: isOutside)
        if isOutsideWindow != isOutside {
            isOutsideWindow = isOutside
        }
    }

    /// Releases a header drag: outside the window the tab leaves as a window of its own;
    /// inside, the card stays where it was dropped, clear of the island's rail.
    private func endHeaderDrag() {
        let ghost = tearOff
        let leaves = isOutsideWindow
        tearOff = nil
        isOutsideWindow = false
        ghost?.close()
        if leaves, let ghost {
            canvas.tearOffFloatingCard(tab, at: NSEvent.mouseLocation, grabFraction: ghost.grabFraction, in: area)
            return
        }
        let moved = canvas.cardsMoved(with: tab)
        canvas.endFloatingCardDrag(tab)
        canvas.keepClearOfRail(moved, in: area)
    }

    private func moveBy(dx: CGFloat, dy: CGFloat) {
        var next = placement
        let origin = next.frame(in: area).origin
        next.move(to: CGPoint(x: origin.x + dx, y: origin.y + dy), in: area)
        canvas.updateFloatingPlacement(next, for: tab)
    }
}

/// Moves a card's favicon between its places in two shapes as one object; under Reduce
/// Motion the favicon stays where each shape puts it.
private struct FaviconTravel: ViewModifier {
    let id: Tab.ID
    let namespace: Namespace.ID
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.matchedGeometryEffect(id: id, in: namespace)
        } else {
            content
        }
    }
}
