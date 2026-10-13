import AppKit
import SwiftUI

/// Keeps the webpage interactive between the floating cards.
final class FloatingTabsHostingView<Content: View>: NSHostingView<Content> {
    var hitRegions: () -> [CGRect] = { [] }
    var onPointerDown: ((CGPoint) -> Void)?
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
                if canvas.floatingVisibility.isRevealed {
                    FloatingLassoSurface(area: bounds)
                    ForEach(canvas.flattenedFloatingGroupItems(in: bounds)) { item in
                        FloatingTabGroup(item: item, area: bounds)
                    }
                }
                ForEach(canvas.visibleFloatingTabs) { tab in
                    let placement = canvas.floatingPlacement(for: tab)
                    let frame = canvas.floatingFrame(for: tab, in: bounds)
                    let fold = canvas.foldOrigin(for: tab, in: bounds)
                    FloatingTabCard(tab: tab, placement: placement, area: bounds)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .transition(.fold(toward: fold.map { CGSize(width: $0.x - frame.minX, height: $0.y - frame.minY) }))
                }
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
            // A card never rests against the rail, wherever it was put or the rail has moved since.
            .onChange(of: RailClearanceKey(isRevealed: canvas.floatingVisibility.isRevealed, rail: windowState.controlIsland.railFrame), initial: true) { _, key in
                guard key.isRevealed else { return }
                canvas.keepClearOfRail(canvas.visibleFloatingTabs, in: bounds)
            }
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

/// What decides whether cards must be pushed clear of the rail: the layer showing, and the rail's frame.
private struct RailClearanceKey: Equatable {
    let isRevealed: Bool
    let rail: CGRect
}

private struct FloatingTabCard: View {
    let tab: Tab
    let placement: FloatingTabPlacement
    let area: CGRect

    @Environment(TabCanvasManager.self) private var canvas
    @Environment(WindowState.self) private var windowState
    @State private var resizeOrigin: CGSize?
    @State private var isHovering = false
    @State private var tearOff: FloatingTearOffGhost?
    @State private var isOutsideWindow = false

    private typealias Header = FloatingCardChrome.Header

    private enum Layout {
        static let resizeHandleSize: CGFloat = 22
        static let resizeHandleRadius: CGFloat = 6
        static let resizeHandleInset: CGFloat = 3
        static let resizeSymbolSize: CGFloat = 9
        static let mainPageRowHeight: CGFloat = 24
        /// The card's opacity while a copy of it follows the pointer outside the window.
        static let leavingOpacity: Double = 0.4
        static let moveStep: CGFloat = 24
        static let resizeStep: CGFloat = 40
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
    private var cornerRadius: CGFloat {
        FloatingCardChrome.cornerRadius(isKept: isKept)
    }
    /// The header's controls and the resize handle show while the pointer is on the card or
    /// its options are open.
    private var showsControls: Bool {
        isHovering || canvas.menuTabID == tab.id
    }

    var body: some View {
        let shadow = FloatingCardChrome.shadow(isKept: isKept)
        VStack(spacing: 0) {
            header
                .frame(height: Header.height)
            if isMainPage {
                Text("Open full-size")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Header.leadingPadding).frame(height: Layout.mainPageRowHeight)
            } else if !placement.isCompact {
                FloatingTabPreview(tab: tab, viewportSize: area.size)
                    .frame(height: max(0, placement.frame(in: area).height - Header.height - FloatingTabPlacement.previewInset))
                    .clipShape(.rect(cornerRadius: FloatingCardChrome.previewCornerRadius(isKept: isKept)))
                    .padding([.horizontal, .bottom], FloatingTabPlacement.previewInset)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(canvas.selectedFloatingTabIDs.contains(tab.id) || hasInput || (tab.id == canvas.focusedFloatingTabID && canvas.floatingVisibility.isRevealed) ? Color.appAccentColor : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            if !placement.isCompact, !isMainPage, showsControls {
                resizeHandle
            }
        }
        .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.y)
        .opacity(isOutsideWindow ? Layout.leavingOpacity : 1)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Floating tab, \(tab.displayTitle)")
        .accessibilityValue(isKept ? "Kept visible" : "")
        .accessibilityIdentifier("floating-tab-\(tab.id.uuidString)")
        .closesOnMiddleClick(tab)
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: Layout.resizeSymbolSize, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: Layout.resizeHandleSize, height: Layout.resizeHandleSize)
            .background(.regularMaterial, in: .rect(cornerRadius: Layout.resizeHandleRadius))
            .contentShape(Rectangle())
            .padding(Layout.resizeHandleInset)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .named("floatingTabs"))
                .onChanged { value in
                    canvas.beginFloatingManipulation()
                    let size = resizeOrigin ?? placement.frame(in: area).size
                    resizeOrigin = size
                    resize(to: CGSize(
                        width: size.width + value.translation.width,
                        height: size.height + value.translation.height,
                    ))
                }
                .onEnded { _ in
                    resizeOrigin = nil
                    canvas.endFloatingManipulation()
                })
            .accessibilityLabel("Resize \(tab.displayTitle) preview")
            .accessibilityAdjustableAction { direction in
                let delta = direction == .increment ? Layout.resizeStep : -Layout.resizeStep
                resize(to: CGSize(width: placement.size.width + delta, height: placement.size.height + delta))
            }
            .help("Drag to resize preview")
    }

    private func resize(to size: CGSize) {
        var next = placement
        next.resize(to: size, in: area)
        canvas.updateFloatingPlacement(next, for: tab)
    }

    /// A title bar: favicon, title, and state at rest; the presentation toggle, close, and the
    /// options join them on hover. The header is the card's drag handle.
    private var header: some View {
        HStack(spacing: 0) {
            HStack(spacing: Header.itemSpacing) {
                Group {
                    if let data = tab.activePage.faviconData, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else {
                        Image(systemName: "globe")
                    }
                }
                .frame(width: Header.glyphBox, height: Header.glyphBox)
                FloatingTabTitle(tab: tab)
                TabStateSymbols(tab: tab)
                Spacer(minLength: 0)
            }
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

            if canvas.retainedInputTabID == tab.id, !canvas.floatingVisibility.isRevealed {
                Button("Finish") { canvas.finishPreviewInteraction() }
                    .labelStyle(.titleOnly)
                    .padding(.leading, Header.itemSpacing)
            }
            if showsControls {
                if !isMainPage {
                    presentationButton
                }
                closeButton
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

    /// Switches the card between compact and preview where it stands.
    private var presentationButton: some View {
        let title = placement.isCompact ? "Show as Preview" : "Show as Compact Tab"
        return headerControl(title, symbol: placement.isCompact ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left") {
            var next = placement
            next.setCompact(!placement.isCompact, in: area)
            canvas.updateFloatingPlacement(next, for: tab)
        }
    }

    private var closeButton: some View {
        headerControl("Close Tab", symbol: "xmark") {
            canvas.tabManager.requestCloseTab(tab)
        }
    }

    private func headerControl(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(title, systemImage: symbol, action: action)
            .font(.system(size: Header.symbolPointSize))
            .foregroundStyle(.secondary)
            .frame(width: Header.controlSize, height: Header.controlSize).contentShape(Rectangle())
            .help(title)
            .accessibilityLabel(title)
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
