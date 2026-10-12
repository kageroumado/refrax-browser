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
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
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
            if event.type == .leftMouseDown { onPointerDown?(point) }
            guard let state = controlState?(),
                  !state.isPresenting, !state.hitRegions.isEmpty else { return event }
            state.dismissIfOutside(point)
            return event
        }
    }

    isolated deinit {
        if let pointerMonitor { NSEvent.removeMonitor(pointerMonitor) }
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
                if canvas.floatingVisibility.isRevealed {
                    ForEach(canvas.floatingGroups, id: \.first?.group?.id) { members in
                        FloatingTabGroup(tabs: members, area: bounds)
                    }
                }
                ForEach(canvas.visibleFloatingTabs) { tab in
                    let placement = canvas.floatingPlacement(for: tab)
                    let frame = canvas.floatingFrame(for: tab, in: bounds)
                    FloatingTabCard(tab: tab, placement: placement, area: bounds)
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                }
                if let request = canvas.rayRequest, let tab = canvas.floatingTabs.first(where: { $0.id == request.tabID }) {
                    FloatingRayView(path: FloatingRayPath(from: request.source, to: canvas.floatingFrame(for: tab, in: bounds), in: bounds)) {
                        canvas.finishRay(request.revision)
                    }
                    .id(request.revision)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .coordinateSpace(name: "floatingTabs")
            .dropDestination(for: FloatingTabDrag.self) { items, point in
                guard let item = items.first, let tab = canvas.floatingTabs.first(where: { $0.id == item.id }) else { return false }
                var placement = canvas.floatingPlacement(for: tab)
                placement.move(to: point, in: bounds)
                canvas.updateFloatingPlacement(placement, for: tab)
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

private struct FloatingTabCard: View {
    let tab: Tab
    let placement: FloatingTabPlacement
    let area: CGRect

    @Environment(TabCanvasManager.self) private var canvas
    @Environment(WindowState.self) private var windowState
    @State private var dragOrigin: CGPoint?
    @State private var resizeOrigin: CGSize?

    private enum Layout {
        /// Each header control's target, inside the 34-point header.
        static let headerControlSize: CGFloat = 32
        static let headerControlSpacing: CGFloat = 2
        static let headerInset: CGFloat = 10
    }

    private var isMainPage: Bool { tab.id == windowState.activeTabID }
    private var hasInput: Bool { windowState.focusedPage?.tab?.id == tab.id && !isMainPage }

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: FloatingTabPlacement.headerHeight)
            if isMainPage {
                Text(placement.isPinned ? "Open full-size · Kept visible" : "Open full-size")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).frame(height: 24)
            } else if !placement.isCompact {
                FloatingTabPreview(tab: tab, viewportSize: area.size)
                    .frame(height: max(0, placement.frame(in: area).height - FloatingTabPlacement.headerHeight - FloatingTabPlacement.previewInset))
                    .clipShape(.rect(cornerRadius: CanvasTileLayout.slabCornerRadius - FloatingTabPlacement.previewInset))
                    .padding([.horizontal, .bottom], FloatingTabPlacement.previewInset)
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: CanvasTileLayout.slabCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: CanvasTileLayout.slabCornerRadius)
                .strokeBorder(canvas.selectedFloatingTabIDs.contains(tab.id) || hasInput || (tab.id == canvas.focusedFloatingTabID && canvas.floatingVisibility.isRevealed) ? Color.appAccentColor : .clear, lineWidth: 2)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            if !placement.isCompact && !isMainPage {
                resizeHandle
            }
        }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Floating tab, \(tab.displayTitle)")
        .accessibilityIdentifier("floating-tab-\(tab.id.uuidString)")
    }

    private var resizeHandle: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 22, height: 22)
            .background(.regularMaterial, in: .rect(cornerRadius: 6))
            .contentShape(Rectangle())
            .padding(3)
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
                let delta: CGFloat = direction == .increment ? 40 : -40
                resize(to: CGSize(width: placement.size.width + delta, height: placement.size.height + delta))
            }
            .help("Drag to resize preview")
    }

    private func resize(to size: CGSize) {
        var next = placement
        next.resize(to: size, in: area)
        canvas.updateFloatingPlacement(next, for: tab)
    }

    private var header: some View {
        HStack(spacing: Layout.headerControlSpacing) {
            HStack(spacing: 7) {
                if let data = tab.activePage.faviconData, let image = NSImage(data: data) {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 16, height: 16)
                } else {
                    Image(systemName: "globe").frame(width: 16, height: 16)
                }
                Text(tab.displayTitle).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if NSEvent.modifierFlags.contains(.shift) {
                    if canvas.selectedFloatingTabIDs.contains(tab.id) { canvas.selectedFloatingTabIDs.remove(tab.id) }
                    else { canvas.selectedFloatingTabIDs.insert(tab.id) }
                } else { canvas.openFloatingTab(tab) }
            }
            .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("floatingTabs"))
                .onChanged { value in
                    canvas.beginFloatingManipulation()
                    let origin = dragOrigin ?? placement.frame(in: area).origin
                    dragOrigin = origin
                    var next = placement
                    next.move(to: CGPoint(x: origin.x + value.translation.width, y: origin.y + value.translation.height), in: area)
                    canvas.updateFloatingPlacement(next, for: tab)
                }
                .onEnded { _ in
                    dragOrigin = nil
                    canvas.endFloatingManipulation()
                    canvas.confirmFloatingPlacement()
                })
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { canvas.openFloatingTab(tab) }
            .accessibilityAction(named: "Move left") { moveBy(dx: -24, dy: 0) }
            .accessibilityAction(named: "Move right") { moveBy(dx: 24, dy: 0) }
            .accessibilityAction(named: "Move up") { moveBy(dx: 0, dy: -24) }
            .accessibilityAction(named: "Move down") { moveBy(dx: 0, dy: 24) }

            presentationButton
            pinButton
            if canvas.retainedInputTabID == tab.id && !canvas.floatingVisibility.isRevealed {
                Button("Finish") { canvas.finishPreviewInteraction() }
                    .labelStyle(.titleOnly)
            }
            PageActionsMenu(tab: tab, area: area, host: .floatingCard)
                .frame(width: Layout.headerControlSize, height: Layout.headerControlSize)
        }
        .labelStyle(.iconOnly)
        .controlSize(.small)
        .buttonStyle(.plain)
        .padding(.horizontal, Layout.headerInset)
    }

    /// Switches the card between compact and preview where it stands.
    private var presentationButton: some View {
        let title = placement.isCompact ? "Show as preview" : "Show as compact tab"
        return Button(title, systemImage: placement.isCompact ? "rectangle.expand.vertical" : "rectangle.compress.vertical") {
            var next = placement
            next.setCompact(!placement.isCompact, in: area)
            canvas.updateFloatingPlacement(next, for: tab)
        }
        .foregroundStyle(.secondary)
        .frame(width: Layout.headerControlSize, height: Layout.headerControlSize).contentShape(Rectangle())
        .help(title)
        .accessibilityLabel(title)
    }

    private var pinButton: some View {
        let title = placement.isPinned ? "Hide preview" : "Keep preview visible"
        return Button(title, systemImage: placement.isPinned ? "pin.fill" : "pin") {
            var next = placement
            next.isPinned.toggle()
            if next.isPinned {
                next.setCompact(false, in: area)
            }
            canvas.updateFloatingPlacement(next, for: tab)
        }
        .foregroundStyle(placement.isPinned ? Color.appAccentColor : .secondary)
        .frame(width: Layout.headerControlSize, height: Layout.headerControlSize).contentShape(Rectangle())
        .help(title)
        .accessibilityLabel(title)
    }

    private func moveBy(dx: CGFloat, dy: CGFloat) {
        var next = placement
        let origin = next.frame(in: area).origin
        next.move(to: CGPoint(x: origin.x + dx, y: origin.y + dy), in: area)
        canvas.updateFloatingPlacement(next, for: tab)
    }
}
