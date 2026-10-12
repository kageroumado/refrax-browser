import AppKit
import SwiftUI

/// A movable, fixed-width rail of browser controls.
///
/// The rail rests while the pointer is far away or still: its glass clears and its
/// symbols recede, so the page shows through. Pointer travel toward it wakes it.
struct ControlIsland: View {
    let area: CGRect

    @Environment(WindowState.self) private var windowState
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(TabSwitcherManager.self) private var tabSwitcher
    @Environment(BookmarksManager.self) private var bookmarks
    @Environment(SpaceManager.self) private var spaces
    @Environment(TabManager.self) private var tabManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.appearsActive) private var appearsActive
    @Namespace private var glassNamespace
    @FocusState private var focusedControl: String?
    @GestureState private var isDraggingWindow = false
    @GestureState private var isDraggingPanel = false
    @State private var isOptionDragging = false
    @State private var railDragFeedback: ControlIslandDragFeedback = .idle
    @State private var dragOrigin: CGPoint?
    @State private var showsFavorites = false
    @State private var pointerPhase = ControlIslandHoverPath.Phase.outside
    @State private var shortcutRowMidY: CGFloat?
    @State private var showsShortcut = false
    @State private var avoidancePlacement: ControlIslandPlacement?
    @State private var hoverHasSettled = false
    @AppStorage("floatingTabs.revealKey") private var revealKey = FloatingRevealKey.control
    private typealias Layout = ControlIslandPlacement

    private var state: ControlIslandState {
        windowState.controlIsland
    }
    private var favorites: [FavoriteItem] {
        bookmarks.favorites.filter { $0.tab != nil }
    }
    private var visibleItems: [ControlIslandItem] {
        state.configuration.visibleItems.filter { item in
            switch item {
            case .spaces: !spaces.spaces.isEmpty
            case .favoriteTabs: !favorites.isEmpty
            case .page: windowState.activePage != nil
            default: true
            }
        }
    }

    private var height: CGFloat {
        let items = visibleItems
        let rowCount = items.reduce(1) { count, item in
            switch item {
            case .windowControls: count + 3
            case .spaces: count
            case .favoriteTabs: count
            default: count + 1
            }
        }
        let separators = items.indices.filter { $0 > 0 && (items[$0].isGroup || items[$0 - 1].isGroup) }.count
            + (items.last?.isGroup == true ? 1 : 0)
        return Layout.contentInset * 2
            + Layout.rowHeight * CGFloat(rowCount) + Layout.sectionGap * CGFloat(separators)
            + (items.contains(.spaces) ? CGFloat(min(spaces.spaces.count, Layout.maximumVisibleSpaces)) * Layout.spaceRowHeight : 0)
            + (items.contains(.favoriteTabs) ? ControlIslandFavoriteTabs.height(for: favorites.count) : 0)
    }

    private func hasSeparator(before item: ControlIslandItem) -> Bool {
        guard let index = visibleItems.firstIndex(of: item), index > 0 else { return false }
        return item.isGroup || visibleItems[index - 1].isGroup
    }
    private var frame: CGRect { effectivePlacement.railFrame(in: area, height: height) }
    private var effectivePlacement: ControlIslandPlacement { avoidancePlacement ?? state.placement }
    private var opensLeft: Bool {
        effectivePlacement.opensLeft(in: area)
    }
    private var pageBranchFrame: CGRect {
        let anchor = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: Layout.railWidth)
        return effectivePlacement.pageBranchFrame(in: area, anchor: anchor,
            height: Layout.pageBranchHeight + (windowState.pageVisit.destination == nil ? 0 : 37))
    }
    /// The page card accompanies deliberate use of the rail: a settled hover, the Address row,
    /// the revealed tab layer, or a visit that can return. A pointer crossing the rail leaves it closed.
    private var showsPageBranch: Bool {
        windowState.activePage != nil && dragFeedback == .idle && !state.isDragging
            && (state.tabInfo.isVisible || state.showsAddress || hoverHasSettled || windowState.pageVisit.destination != nil
                || canvas.floatingVisibility.isRevealed)
    }

    /// The glass clears and the symbols recede while nothing on the rail is in use.
    private var isResting: Bool {
        state.configuration.restsWhenIdle && (state.isQuiet || !appearsActive) && !state.isEngaged
            && !showsPageBranch && !canvas.recentIsOpen && !showsShortcut
    }

    /// At rest the glass is clear rather than frosted; the symbols stay opaque and step back one shade.
    private var glass: Glass { isResting && !reduceTransparency ? .clear : .regular }

    /// The space color is drawn as the rail's own layer under the symbols, so it can fade with
    /// the glass: a tint inside the glass would drop to white the moment the glass starts to clear.
    private var spaceTint: Color {
        guard state.configuration.tintsWithSpaceColor, let color = windowState.activeSpace?.color else { return .clear }
        return color.opacity(Layout.spaceTintOpacity)
    }
    private var restAnimation: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.4) }
    private var recentFrame: CGRect {
        effectivePlacement.pageBranchFrame(in: area, anchor: frame, height: min(320, area.height - Layout.margin * 2))
    }
    private var shortcutFrame: CGRect {
        let x = opensLeft ? frame.minX - 38 : frame.maxX + 8
        return CGRect(x: x, y: (shortcutRowMidY ?? frame.midY) - 14, width: 30, height: 28)
    }

    var body: some View {
        @Bindable var state = windowState.controlIsland
        GlassEffectContainer(spacing: Layout.adjacentGap) {
            ZStack(alignment: .topLeading) {
                controls
                    .frame(width: frame.width, height: frame.height)
                    .environment(\.controlIslandIsResting, isResting)
                    .background(spaceTint.opacity(isResting ? 0 : 1), in: .rect(cornerRadius: Layout.cornerRadius))
                    .glassEffect(glass, in: .rect(cornerRadius: Layout.cornerRadius))
                    .glassEffectID("rail", in: glassNamespace)
                    .offset(x: frame.minX, y: frame.minY)
                if showsPageBranch, !canvas.recentIsOpen {
                    ControlIslandPageBranch(area: area, frame: pageBranchFrame)
                    .frame(width: pageBranchFrame.width, height: pageBranchFrame.height)
                    .background(spaceTint, in: .rect(cornerRadius: Layout.pageBranchHeight / 2))
                    .glassEffect(.regular, in: .rect(cornerRadius: Layout.pageBranchHeight / 2))
                    .glassEffectID("pageBranch", in: glassNamespace)
                    .offset(x: pageBranchFrame.minX, y: pageBranchFrame.minY)
                    .transition(.opacity)
                }
                if canvas.recentIsOpen {
                    FloatingRecentTabs(area: area)
                        .frame(width: recentFrame.width, height: recentFrame.height)
                        .background(spaceTint, in: .rect(cornerRadius: 20))
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                        .glassEffectID("recent", in: glassNamespace)
                        .offset(x: recentFrame.minX, y: recentFrame.minY)
                        .transition(.opacity)
                }
                if showsShortcut {
                    Button { canvas.toggleFloatingTabs() } label: {
                        Text(revealKey.glyph).font(.system(size: 16, weight: .medium))
                            .frame(width: shortcutFrame.width, height: shortcutFrame.height)
                            .contentShape(Rectangle())
                    }
                    .background(spaceTint, in: .rect(cornerRadius: 7))
                    .glassEffect(.regular, in: .rect(cornerRadius: 7))
                    .glassEffectID("shortcut", in: glassNamespace)
                    .offset(x: shortcutFrame.minX, y: shortcutFrame.minY)
                    .transition(.opacity)
                    .help("Hold \(revealKey.title) to reveal tabs; release to hide")
                    .accessibilityLabel("Tabs shortcut: hold \(revealKey.title)")
                }
                if state.isDragging {
                    let snap = state.placement.snapped(in: area, height: height)
                    if snap != state.placement {
                        let target = snap.railFrame(in: area, height: height)
                        RoundedRectangle(cornerRadius: Layout.cornerRadius)
                            .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .frame(width: target.width, height: target.height)
                            .offset(x: target.minX, y: target.minY)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .buttonStyle(ControlIslandButtonStyle())
        .onAppear { state.pointerMoved = { hoverChanged(state.tracksPointer($0)) } }
        .onChange(of: interactionRegions, initial: true) { _, regions in state.hitRegions = regions }
        .onChange(of: frame, initial: true) { _, frame in state.railFrame = frame }
        .onChange(of: state.placement) { avoidancePlacement = nil }
        .onChange(of: windowState.activeTabID) { state.showsAddress = false }
        .onChange(of: windowState.activeSpaceID) {
            state.showsAddress = false
            state.tabInfo.dismiss()
        }
        .onChange(of: focusedControl) {
            if focusedControl == nil { state.hasKeyboardFocus = false }
            else if NSApp.currentEvent?.type == .keyDown { state.hasKeyboardFocus = true }
        }
        .onChange(of: isDraggingWindow || isDraggingPanel || isOptionDragging || state.isReorderingFavorites) { _, dragging in
            state.isDragging = dragging
            if !dragging {
                finishPanelDrag()
            }
        }
        .onChange(of: showsFavorites) { _, presented in
            state.isPresenting = presented
        }
        .onChange(of: state.focusRequest) {
            focusedControl = visibleItems.contains(.page) ? "Page" : "More"
        }
        .onChange(of: state.configuration.items) {
            focusedControl = nil
            if !visibleItems.contains(.page) {
                state.showsAddress = false
            }
        }
        .onChange(of: pageBranchFrame, initial: true) { windowState.addressBarFrame = pageBranchFrame }
        .sheet(isPresented: $state.showsCustomization) {
            ControlIslandCustomizationSheet(configuration: state.configuration)
        }
        .onChange(of: state.dismissalRequest) {
            focusedControl = nil
            canvas.recentIsOpen = false
        }
        .onChange(of: state.pageFocusRequest) {
            windowState.window?.makeFirstResponder(windowState.activeWebPage?.contentView)
        }
        .onExitCommand {
            state.dismiss()
        }
        .onChange(of: windowState.showsCompactAddressBar) { _, shown in
            if shown {
                windowState.showsCompactAddressBar = false
            }
        }
        .onDisappear {
            state.pointerMoved = nil
            state.hitRegions = []
            state.clearFrames()
            state.isHovered = false
            state.showsAddress = false
            state.hasKeyboardFocus = false
            state.isPresenting = false
            state.isDragging = false
            state.tabInfo.dismiss()
            dragOrigin = nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Browser controls")
        .accessibilityIdentifier("browser-control-island")
        .animation(restAnimation, value: isResting)
        .animation(restAnimation, value: windowState.activeSpaceID)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: showsPageBranch)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: canvas.recentIsOpen)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: showsShortcut)
        .onAppear { state.wake() }
        .task(id: state.isHovered) {
            hoverHasSettled = false
            guard state.isHovered else { return }
            try? await Task.sleep(for: .seconds(Layout.hoverSettle))
            guard !Task.isCancelled else { return }
            hoverHasSettled = true
        }
        .task(id: avoidanceRevision) { await yieldToPageControl() }
        .task(id: keepsHoverOpen ? .inside : pointerPhase) { await settleHover() }
        .task(id: showsShortcut) {
            guard showsShortcut else { return }
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            showsShortcut = false
        }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(visibleItems) { item in
                        if hasSeparator(before: item) { sectionDivider }
                        itemControl(item)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("browserControls")) } action: {
                                state.reportFrame($0, for: item)
                            }
                    }
                    if visibleItems.last?.isGroup == true { sectionDivider }
                    ControlIslandMenu(showsFavorites: $showsFavorites)
                        .focused($focusedControl, equals: "More")
                        .focusEffectDisabled()
                        .popover(isPresented: $showsFavorites, arrowEdge: opensLeft ? .leading : .trailing) {
                            ControlIslandFavorites(isPresented: $showsFavorites)
                        }
                }
            }
            .scrollIndicators(.automatic)
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.vertical, Layout.contentInset)
        .padding(.horizontal, Layout.horizontalInset)
        .background { dragSurface }
        .background { optionDrag }
        .accessibilityAction(named: "Move controls left") { moveBy(dx: -32, dy: 0) }
        .accessibilityAction(named: "Move controls right") { moveBy(dx: 32, dy: 0) }
        .accessibilityAction(named: "Move controls up") { moveBy(dx: 0, dy: -32) }
        .accessibilityAction(named: "Move controls down") { moveBy(dx: 0, dy: 32) }
        .accessibilityAction(named: "Move window left") { moveWindowBy(dx: -32, dy: 0) }
        .accessibilityAction(named: "Move window right") { moveWindowBy(dx: 32, dy: 0) }
        .accessibilityAction(named: "Move window up") { moveWindowBy(dx: 0, dy: 32) }
        .accessibilityAction(named: "Move window down") { moveWindowBy(dx: 0, dy: -32) }
    }

    @ViewBuilder
    private func itemControl(_ item: ControlIslandItem) -> some View {
        switch item {
        case .windowControls:
            ControlIslandWindowButtons().frame(height: Layout.rowHeight * 3)
        case .navigation:
            navigationControls
        case .page:
            pageRow
        case .copyLink:
            control(item.title, symbol: item.symbol, enabled: windowState.activeTab != nil) {
                guard let tab = windowState.activeTab else { return }
                ControlIslandTabActions(tab: tab, windowState: windowState, tabs: tabManager, bookmarks: bookmarks).copyLink()
                windowState.showToast("Address copied")
            }
            .help(item.detail)
        case .commandLens:
            control(item.title, symbol: item.symbol) {
                tabSwitcher.cancel()
                if windowState.showsCommandLens { windowState.closeCommandLens() }
                else { windowState.openCommandLens() }
            }
            .help(item.detail)
        case .floatingTabs:
            control(item.title, symbol: canvas.floatingVisibility.isRevealed ? "square.on.square.fill" : item.symbol) {
                dismissTransientOverlays()
                canvas.toggleFloatingTabs()
                showsShortcut = canvas.floatingVisibility.isRevealed
            }
            .overlay(alignment: .bottomTrailing) { unplacedBadge }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("browserControls")).midY } action: { shortcutRowMidY = $0 }
            .help("Show tabs · Hold \(revealKey.title) to peek")
        case .recentTabs:
            control(item.title, symbol: item.symbol, enabled: tabSwitcher.isActive || tabSwitcher.canShowSwitcher) {
                windowState.closeCommandLens()
                canvas.dismissFloatingTabs()
                tabSwitcher.toggle()
            }
            .help(item.detail)
        case .desk:
            control(item.title, symbol: TabCanvasManager.symbolName) {
                dismissTransientOverlays()
                canvas.show()
            }
            .help(item.detail)
        case .spaces:
            ControlIslandSpaces(destinations: spaces.spaces, focusedControl: $focusedControl)
        case .favoriteTabs:
            ControlIslandFavoriteTabs(favorites: favorites, focusedControl: $focusedControl)
        case .reload:
            control(windowState.activeWebPage?.isLoading == true ? "Stop loading" : "Reload",
                    symbol: windowState.activeWebPage?.isLoading == true ? "xmark" : item.symbol,
                    enabled: windowState.activeWebPage != nil) {
                if let page = windowState.activeWebPage {
                    if page.isLoading { page.stopLoading() } else { _ = page.reload() }
                }
            }
        case .favorites:
            control(item.title, symbol: item.symbol) { showsFavorites = true }
        case .history:
            control(item.title, symbol: item.symbol) { windowState.showDetailTray(.history) }
        case .downloads:
            control(item.title, symbol: item.symbol) { windowState.showDetailTray(.downloads) }
        case .bookmarks:
            control(item.title, symbol: item.symbol) { windowState.showDetailTray(.bookmarks) }
        case .settings:
            control(item.title, symbol: item.symbol) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
    }

    private var dragFeedback: ControlIslandDragFeedback { railDragFeedback }

    private var dragSurface: some View {
        draggableBackground(Color.clear.contentShape(Rectangle()))
    }

    @ViewBuilder
    private func draggableBackground(_ content: some View) -> some View {
        if state.configuration.optionDragTarget.backgroundTarget == .panel { content.gesture(moveGesture) }
        else { content.gesture(windowDrag) }
    }

    private var sectionDivider: some View {
        draggableBackground(Divider().frame(height: Layout.sectionGap).contentShape(Rectangle()))
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("browserControls"))
            .updating($isDraggingPanel) { _, dragging, _ in dragging = true }
            .onChanged { value in
                movePanel(by: value.translation)
            }
            .onEnded { _ in
                finishPanelDrag()
            }
    }

    private var windowDrag: some Gesture {
        WindowDragGesture()
            .updating($isDraggingWindow) { _, dragging, _ in dragging = true }
    }

    private var optionDrag: some View {
        ControlIslandOptionDrag(target: state.configuration.optionDragTarget, isEnabled: !state.isReorderingFavorites, onFeedback: { feedback in
            railDragFeedback = feedback
        }, onBegin: {
            isOptionDragging = true
            state.isDragging = true
        }, onMove: movePanel, onEnd: {
            isOptionDragging = false
            state.isDragging = false
            finishPanelDrag()
        })
    }

    private func movePanel(by translation: CGSize) {
        let origin = dragOrigin ?? effectivePlacement.railFrame(in: area, height: height).origin
        avoidancePlacement = nil
        dragOrigin = origin
        state.isDragging = true
        state.placement.move(to: CGPoint(x: origin.x + translation.width, y: origin.y + translation.height), in: area, height: height)
    }

    private func finishPanelDrag() {
        guard dragOrigin != nil else { return }
        dragOrigin = nil
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
            state.placement = state.placement.snapped(in: area, height: height)
        }
        savePlacement()
    }

    private var navigationControls: some View {
        let page = windowState.focusedWebPage
        let canGoForward = page?.canGoForward == true
        return HStack(spacing: 0) {
            AddressBarBackButton(
                webPage: page, canGoBack: page?.canGoBack == true,
                targetSize: CGSize(width: canGoForward ? Layout.contentWidth / 2 : Layout.contentWidth, height: Layout.rowHeight),
                highlightsOnHover: false, symbolWeight: .semibold,
            )
            .focusable()
            .focused($focusedControl, equals: "Back")
            .focusEffectDisabled()
            .help("Back")
            .accessibilityLabel("Back")
            if canGoForward {
                AddressBarForwardButton(
                    webPage: page, canGoForward: true,
                    targetSize: CGSize(width: Layout.contentWidth / 2, height: Layout.rowHeight),
                    highlightsOnHover: false, symbolWeight: .semibold,
                )
                .focusable()
                .focused($focusedControl, equals: "Forward")
                .focusEffectDisabled()
                .help("Forward")
                .accessibilityLabel("Forward")
            }
        }
        .frame(width: Layout.contentWidth, height: Layout.rowHeight)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: canGoForward)
        .onChange(of: canGoForward) { _, available in
            if !available, focusedControl == "Forward" { focusedControl = "Back" }
        }
    }

    /// The current page's icon is the card's trigger: hover unfolds the card, a click keeps it open.
    private var pageRow: some View {
        Button {
            tabSwitcher.cancel()
            if state.tabInfo.isLatched { state.tabInfo.dismiss() } else { state.tabInfo.show() }
        } label: {
            ControlIslandRow {
                ZStack {
                    if let page = windowState.activePage {
                        FaviconView(data: page.faviconData, url: page.url, size: Layout.pageIconSize)
                            .saturation(appearsActive ? 1 : 0)
                    }
                    if windowState.activeWebPage?.isLoading == true {
                        ProgressView(value: windowState.activeWebPage?.estimatedProgress ?? 0)
                            .progressViewStyle(.circular)
                            .frame(width: Layout.pageIconSize + 8, height: Layout.pageIconSize + 8)
                    }
                }
            }
        }
        .focusable()
        .focused($focusedControl, equals: "Page")
        .focusEffectDisabled()
        .onHover { hovering in
            if hovering, windowState.activePage != nil {
                state.showsAddress = true
            }
        }
        .help("Current page · Hover for its card · ⌘L edits the address")
        .accessibilityLabel("Current page")
        .accessibilityValue(windowState.activeWebPage?.isLoading == true ? "Loading" : (windowState.activePage?.url.safeDisplayDomain ?? "Ready"))
    }

    private func dismissTransientOverlays() {
        windowState.closeCommandLens()
        tabSwitcher.cancel()
    }

    /// How many pages wait without a place of their own, in the corner of the tab control.
    @ViewBuilder
    private var unplacedBadge: some View {
        let count = canvas.unplacedFloatingTabs.filter { $0.id != windowState.activeTabID }.count
        if count > 0 {
            Text(count, format: .number)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isResting || !appearsActive ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .padding(.trailing, Layout.badgeInset)
                .padding(.bottom, Layout.badgeInset)
                .allowsHitTesting(false)
                .accessibilityLabel("\(count) unplaced tabs")
        }
    }

    private func control(_ title: String, symbol: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ControlIslandRow { Image(systemName: symbol) }
        }
        .disabled(!enabled)
        .focusable()
        .focused($focusedControl, equals: title)
        .focusEffectDisabled()
        .accessibilityLabel(title)
        .help(title)
    }

    private func hoverChanged(_ phase: ControlIslandHoverPath.Phase) {
        guard pointerPhase != phase else { return }
        pointerPhase = phase
        if phase == .inside {
            state.isHovered = true
        }
    }

    private var keepsHoverOpen: Bool {
        pointerPhase == .inside || state.isDragging || state.isPresenting || state.showsCustomization || state.tabInfo.isMenuPresented
    }

    private func settleHover() async {
        guard !keepsHoverOpen else { return }
        try? await Task.sleep(for: .seconds(pointerPhase == .crossing ? ControlIslandHoverPath.grace : 0.15))
        guard !Task.isCancelled else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
            state.isHovered = false
            state.showsAddress = false
            state.tabInfo.isHovered = false
        }
    }

    private var interactionRegions: [CGRect] {
        var regions = [frame]
        if showsPageBranch, !canvas.recentIsOpen { regions.append(pageBranchFrame) }
        if canvas.recentIsOpen { regions.append(recentFrame) }
        if showsShortcut { regions.append(shortcutFrame) }
        return regions
    }

    private var avoidanceRevision: String {
        "\(windowState.activePageID?.uuidString ?? "")-\(windowState.activeWebPage?.documentRevision.uuidString ?? "")-\(windowState.activeWebPage?.isLoading ?? false)-\(state.configuration.avoidsPageControls)"
    }

    private var canYield: Bool {
        guard state.configuration.avoidsPageControls, !state.isHovered, !state.isDragging,
              !state.hasKeyboardFocus, !state.isPresenting, !state.showsCustomization, !state.tabInfo.isVisible,
              !showsPageBranch, !canvas.floatingVisibility.isRevealed, !canvas.recentIsOpen,
              !windowState.showsCommandLens, !windowState.showsAddressLens,
              let window = windowState.window, window.isKeyWindow, window.attachedSheet == nil,
              NSEvent.pressedMouseButtons == 0, Date().timeIntervalSince(state.lastPointerMovement) > 0.8,
              let content = window.contentView else { return false }
        let location = content.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let point = CGPoint(x: location.x, y: content.isFlipped ? location.y : content.bounds.height - location.y)
        return !frame.insetBy(dx: -96, dy: -96).contains(point)
    }

    private func yieldToPageControl() async {
        guard state.configuration.avoidsPageControls else { avoidancePlacement = nil; return }
        guard let page = windowState.activeWebPage, !page.isLoading, let window = windowState.window else { return }
        try? await Task.sleep(for: .seconds(1.2))
        guard !Task.isCancelled, canYield else { return }
        let placement = state.placement
        let revision = page.documentRevision
        guard let obstacles = await ControlIslandAvoidance.obstacles(on: page, in: window),
              !Task.isCancelled, canYield, state.placement == placement,
              windowState.activeWebPage === page, revision == page.documentRevision,
              window.contentView?.bounds.size == area.size else { return }
        let source = placement.railFrame(in: area, height: height)
        var adjusted: ControlIslandPlacement?
        if let origin = ControlIslandAvoidance.proposedOrigin(for: source, in: area, obstacles: obstacles) {
            var next = placement
            next.move(to: origin, in: area, height: height)
            adjusted = next
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { avoidancePlacement = adjusted }
    }

    private func moveBy(dx: CGFloat, dy: CGFloat) {
        let origin = effectivePlacement.railFrame(in: area, height: height).origin
        avoidancePlacement = nil
        state.placement.move(to: CGPoint(x: origin.x + dx, y: origin.y + dy), in: area, height: height)
        savePlacement()
    }

    private func savePlacement() {
        state.savePlacement()
        windowState.window?.invalidateRestorableState()
    }

    private func moveWindowBy(dx: CGFloat, dy: CGFloat) {
        guard let window = windowState.window, window.isMovable, !window.styleMask.contains(.fullScreen) else { return }
        window.setFrameOrigin(window.constrainFrameRect(window.frame.offsetBy(dx: dx, dy: dy), to: window.screen).origin)
    }
}
