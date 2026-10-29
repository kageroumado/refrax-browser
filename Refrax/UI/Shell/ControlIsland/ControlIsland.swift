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
    @Environment(FloatingTourManager.self) private var tour
    @Environment(AppUpdateManager.self) private var updates
    @Environment(MediaControlsManager.self) private var mediaControls
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.appearsActive) private var appearsActive
    @Namespace private var glassNamespace
    @FocusState private var focusedControl: String?
    @GestureState private var isDraggingWindow = false
    @GestureState private var isDraggingPanel = false
    @State private var dragOrigin: CGPoint?
    @State private var showsUpdate = false
    @State private var showsNowPlaying = false
    @State private var pointerPhase = ControlIslandHoverPath.Phase.outside
    @State private var shortcutRowMidY: CGFloat?
    @State private var showsShortcut = false
    /// Option is down: controls with a second meaning show it in place.
    @State private var optionIsDown = false
    @State private var flagsMonitor: Any?
    @State private var escapeMonitor: Any?
    @State private var avoidancePlacement: ControlIslandPlacement?
    @State private var hoverHasSettled = false
    @State private var railHelp = ControlIslandRailHelp()
    @State private var railHelpSize = CGSize.zero
    @AppStorage("floatingTabs.revealKey") private var revealKey = FloatingRevealKey.control
    private typealias Layout = ControlIslandPlacement
    private static let escapeKeyCode: UInt16 = 53

    private var state: ControlIslandState {
        windowState.controlIsland
    }
    private var favorites: [FavoriteItem] {
        bookmarks.favorites.filter { $0.tab != nil }
    }
    /// The grid holds favorites without a tab (shortcuts, folders, app shortcuts), which the
    /// column reaches through its chevron.
    private var favoritesOverflow: Bool {
        bookmarks.favorites.count > favorites.count
    }
    private var visibleItems: [ControlIslandItem] {
        state.configuration.visibleItems.filter { item in
            switch item {
            case .spaces: !spaces.spaces.isEmpty
            case .favoriteTabs: !bookmarks.favorites.isEmpty
            case .page: windowState.activePage != nil
            case .updates: updateIsReady
            case .nowPlaying: mediaControls.hasActiveMedia
            default: true
            }
        }
    }
    private var railLayout: ControlIslandRailLayout {
        ControlIslandRailLayout(visibleItems: visibleItems)
    }
    /// A downloaded update waits for a restart; the update badge is on the rail only then.
    private var updateIsReady: Bool {
        if case .readyToInstall = updates.phase {
            true
        } else {
            false
        }
    }

    private var height: CGFloat {
        Layout.railHeight(
            items: visibleItems, spaceCount: spaces.spaces.count, favoriteCount: favorites.count, favoritesOverflow: favoritesOverflow,
        )
    }

    /// The row keyboard focus lands on from View → Focus Browser Controls: the page icon, then the first focusable row.
    private var firstFocusID: String? {
        if visibleItems.contains(.page) {
            return "Page"
        }
        for item in railLayout.rows {
            switch item {
            case .windowControls, .spaces, .favoriteTabs, .page: continue
            case .navigation: return "Back"
            case .reload: return reloadTitle
            default: return item.title
            }
        }
        return nil
    }
    private var reloadTitle: String {
        windowState.activeWebPage?.isLoading == true ? "Stop loading" : "Reload"
    }
    private var frame: CGRect {
        effectivePlacement.railFrame(in: area, height: height)
    }
    /// The saved placement, or the nearby one that yields to a page control. A rail that hides
    /// at its edge keeps the saved one, so the edge it hides past stays put.
    private var effectivePlacement: ControlIslandPlacement {
        state.hiddenEdge == nil ? avoidancePlacement ?? state.placement : state.placement
    }
    private var isHiddenAtEdge: Bool {
        state.isHiddenAtEdge
    }
    /// Where the rail draws: its frame, or past the window edge while hidden there. Under Reduce
    /// Motion it stays in place and fades instead.
    private var railDisplayFrame: CGRect {
        guard isHiddenAtEdge, !reduceMotion, let edge = state.hiddenEdge else { return frame }
        return Layout.hiddenFrame(for: frame, at: edge, in: area)
    }
    /// The strip along the window edge that brings the hidden rail back.
    private var revealStrip: CGRect {
        guard let edge = state.hiddenEdge else { return .zero }
        return Layout.revealStrip(for: frame, at: edge, in: area)
    }
    /// VoiceOver keeps a hidden rail reachable and says where it went.
    private var accessibilityTitle: String {
        guard isHiddenAtEdge, let edge = state.hiddenEdge else { return "Browser controls" }
        return "Controls, hidden at the \(edge.name) edge"
    }
    /// Something beyond the rail needs it on screen: the tour or the anchored lens.
    private var railIsNeeded: Bool {
        tour.isActive || tourLightsRail || windowState.showsAnchoredLens
    }
    private var opensLeft: Bool {
        effectivePlacement.opensLeft(in: area)
    }
    private var pageBranchFrame: CGRect {
        let anchor = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: Layout.railWidth)
        return effectivePlacement.pageBranchFrame(
            in: area,
            anchor: anchor,
            height: Layout.pageBranchHeight + (windowState.pageVisit.destination == nil ? 0 : 37)
                + Layout.paneRowHeight * CGFloat(max(0, (windowState.focusedPage?.tab ?? windowState.activeTab)?.pages.count ?? 1) - 1),
        )
    }
    /// The page card accompanies deliberate use of the rail: a settled hover, the Address row,
    /// the revealed tab layer, or a visit that can return. A pointer crossing the rail leaves it closed.
    private var showsPageBranch: Bool {
        windowState.activePage != nil && !windowState.isDetailTrayVisible && !state.isDragging && !isHiddenAtEdge
            && (state.tabInfo.isVisible || state.showsAddress || hoverHasSettled || windowState.pageVisit.destination != nil
                || canvas.floatingVisibility.isRevealed)
    }

    /// The glass clears and the symbols recede while nothing on the rail is in use and the
    /// tour points elsewhere.
    private var isResting: Bool {
        state.configuration.restsWhenIdle && (state.isQuiet || !appearsActive) && !state.isEngaged
            && !showsPageBranch && !showsShortcut && !tourLightsRail
    }

    /// The tour points at the rail or one of its rows, which the rail lights above its glass.
    private var tourLightsRail: Bool {
        tour.highlightsRail || tour.highlightedItem != nil
    }

    /// At rest the glass is clear rather than frosted; the symbols stay opaque and step back one shade.
    private var glass: Glass {
        isResting && !reduceTransparency ? .clear : .regular
    }

    /// The space color is drawn as the rail's own layer under the symbols, so it can fade with
    /// the glass: a tint inside the glass would drop to white the moment the glass starts to clear.
    /// The window's resolved background, the same color the window tints its blur with: the
    /// space color, the website color, or the custom color, whichever the window settings resolve.
    private var spaceTint: Color {
        windowState.controlIslandTint
    }
    private var restAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.4)
    }
    /// The help of the control under the pointer, beside the rail on the side it opens to,
    /// level with the control and inside the window. The rail is drawn above the tour, so its
    /// help stays away while the tour's card is up.
    @ViewBuilder
    private var railHelpLabel: some View {
        if let shown = railHelp.shown, !isHiddenAtEdge, !state.isDragging, !tour.isActive {
            let bounds = area.insetBy(dx: Layout.margin, dy: Layout.margin)
            let x = opensLeft ? frame.minX - Layout.adjacentGap - railHelpSize.width : frame.maxX + Layout.adjacentGap
            let y = min(max(bounds.minY, shown.anchor.midY - railHelpSize.height / 2), max(bounds.minY, bounds.maxY - railHelpSize.height))
            ControlIslandRailHelpLabel(text: shown.text)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { railHelpSize = $0 }
                .offset(x: x, y: y)
                .transition(.opacity)
        }
    }

    private var shortcutFrame: CGRect {
        let width: CGFloat = 64
        let x = opensLeft ? frame.minX - Layout.adjacentGap - width : frame.maxX + Layout.adjacentGap
        return CGRect(x: x, y: (shortcutRowMidY ?? frame.midY) - 14, width: width, height: 28)
    }

    var body: some View {
        @Bindable var state = windowState.controlIsland
        GlassEffectContainer(spacing: Layout.adjacentGap) {
            ZStack(alignment: .topLeading) {
                controls
                    .frame(width: frame.width, height: frame.height)
                    .environment(\.controlIslandIsResting, isResting)
                    .windowGlassSurface(tint: spaceTint.opacity(isResting ? 0 : 1), glass: glass)
                    .glassEffectID("rail", in: glassNamespace)
                    .overlay {
                        if tour.highlightsRail {
                            railHighlight
                        }
                    }
                    .opacity(isHiddenAtEdge && reduceMotion ? 0 : 1)
                    .offset(x: railDisplayFrame.minX, y: railDisplayFrame.minY)
                if showsPageBranch, !windowState.showsAnchoredLens {
                    ControlIslandPageBranch(area: area, frame: pageBranchFrame)
                        .frame(width: pageBranchFrame.width, height: pageBranchFrame.height)
                        .windowGlassSurface(tint: spaceTint)
                        .glassEffectID("pageBranch", in: glassNamespace)
                        .offset(x: pageBranchFrame.minX, y: pageBranchFrame.minY)
                        // The field opens on the card's exact frame, so the card leaves at once
                        // and the field is what remains; it returns with a fade as the field folds.
                        .transition(windowState.showsAnchoredLens ? .identity : .opacity)
                }
                if showsShortcut, !tour.isActive, !isHiddenAtEdge {
                    Button { canvas.toggleFloatingTabs() } label: {
                        Text("Hold \(revealKey.glyph)").font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 8)
                            .frame(width: shortcutFrame.width, height: shortcutFrame.height)
                            .contentShape(Rectangle())
                    }
                    .background(spaceTint, in: .capsule)
                    .glassEffect(.regular, in: .capsule)
                    .glassEffectID("shortcut", in: glassNamespace)
                    .offset(x: shortcutFrame.minX, y: shortcutFrame.minY)
                    .transition(.opacity)
                    .help("Hold \(revealKey.title) for a glance at your islands; click to keep them up")
                    .accessibilityLabel("Show islands: hold \(revealKey.title)")
                }
                if isHiddenAtEdge, let edge = state.hiddenEdge {
                    let flap = CGRect(
                        x: edge == .left ? area.minX : area.maxX - Layout.flapWidth,
                        y: min(max(area.minY, frame.midY - Layout.flapHeight / 2), area.maxY - Layout.flapHeight),
                        width: Layout.flapWidth, height: Layout.flapHeight,
                    )
                    let shape = UnevenRoundedRectangle(
                        topLeadingRadius: edge == .left ? 0 : Layout.flapWidth, bottomLeadingRadius: edge == .left ? 0 : Layout.flapWidth,
                        bottomTrailingRadius: edge == .left ? Layout.flapWidth : 0, topTrailingRadius: edge == .left ? Layout.flapWidth : 0,
                    )
                    shape.fill(spaceTint)
                        .glassEffect(.regular, in: shape)
                        .frame(width: flap.width, height: flap.height)
                        .offset(x: flap.minX, y: flap.minY)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if state.isDragging {
                    let snap = state.placement.snapped(in: area, height: height)
                    if snap != state.placement {
                        let target = snap.railFrame(in: area, height: height)
                        WindowCorner.concentric
                            .stroke(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .padding(0.5)
                            .frame(width: target.width, height: target.height)
                            .offset(x: target.minX, y: target.minY)
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .overlay(alignment: .topLeading) { railHelpLabel }
        .environment(railHelp)
        .font(.system(size: 13, weight: Layout.symbolWeight))
        .buttonStyle(ControlIslandButtonStyle())
        .pageCardOpensForPasswordSave()
        .controlIslandSpaceSheets()
        .onAppear { state.pointerMoved = { hoverChanged(state.tracksPointer($0)) } }
        .onChange(of: interactionRegions, initial: true) { _, regions in state.hitRegions = regions }
        .onChange(of: isHiddenAtEdge ? .zero : frame, initial: true) { _, frame in state.railFrame = frame }
        .onChange(of: revealStrip, initial: true) { _, strip in state.revealStrip = strip }
        .onChange(of: area, initial: true) { _, area in state.areaBounds = area }
        .onChange(of: railIsNeeded, initial: true) { _, needed in state.setNeededOnScreen(needed) }
        .onChange(of: windowState.showsCommandLens) { _, shown in
            if shown {
                state.revealAtEdge(.request)
            }
        }
        .onChange(of: state.hasKeyboardFocus) { _, focused in
            if focused {
                state.revealAtEdge(.request)
            }
        }
        .onChange(of: state.placement) { avoidancePlacement = nil }
        .onChange(of: windowState.activeTabID) { state.showsAddress = false }
        .onChange(of: windowState.activeSpaceID) {
            state.showsAddress = false
            state.tabInfo.dismiss()
        }
        .onChange(of: focusedControl) {
            if focusedControl == nil {
                state.hasKeyboardFocus = false
            } else if NSApp.currentEvent?.type == .keyDown {
                state.hasKeyboardFocus = true
            }
        }
        .onChange(of: isDraggingWindow || isDraggingPanel || state.isReorderingFavorites) { _, dragging in
            state.isDragging = dragging
            railHelp.dismiss()
            if !dragging {
                finishPanelDrag()
            }
        }
        .onChange(of: showsUpdate || showsNowPlaying || windowState.showsAnchoredLens) { _, presented in
            state.isPresenting = presented
        }
        .onChange(of: state.focusRequest) {
            focusedControl = firstFocusID
        }
        .onChange(of: state.configuration.items) {
            focusedControl = nil
            if !visibleItems.contains(.page) {
                state.showsAddress = false
            }
        }
        .onChange(of: pageBranchFrame, initial: true) { windowState.pageCardFrame = pageBranchFrame }
        .onChange(of: showsPageBranch && !windowState.showsAnchoredLens ? pageBranchFrame : .zero, initial: true) { _, card in
            state.pageCardFrame = card
        }
        .sheet(isPresented: $state.showsCustomization) {
            ControlIslandCustomizationSheet(configuration: state.configuration)
        }
        .sheet(isPresented: $showsUpdate) {
            UpdateAvailableView()
        }
        .onChange(of: state.dismissalRequest) {
            focusedControl = nil
        }
        .onChange(of: state.pageFocusRequest) {
            windowState.window?.makeFirstResponder(windowState.activeWebPage?.contentView)
        }
        .onExitCommand {
            state.dismiss()
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
        .accessibilityLabel(accessibilityTitle)
        .accessibilityAction(named: "Show controls") { state.revealAtEdge(.request) }
        .accessibilityIdentifier("browser-control-island")
        .animation(restAnimation, value: isResting)
        .animation(restAnimation, value: windowState.activeSpaceID)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: showsPageBranch)
        .animation(reduceMotion ? .easeInOut(duration: 0.28) : .snappy(duration: 0.28), value: isHiddenAtEdge)
        .animation(reduceMotion ? .easeInOut(duration: 0.28) : .snappy(duration: 0.28), value: windowState.showsAnchoredLens)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: showsShortcut)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: tour.highlightedItem)
        .animation(reduceMotion ? nil : .snappy(duration: 0.25), value: tour.highlightsRail)
        .onAppear {
            state.wake()
            flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                optionIsDown = event.modifierFlags.contains(revealKey.secondMeaningFlag)
                return event
            }
            // Escape still reaches the page; a rail the pointer brought back also hides.
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak windowState = windowState] event in
                if event.keyCode == Self.escapeKeyCode, let windowState, event.window === windowState.window {
                    windowState.controlIsland.hideAfterPointerReveal()
                }
                return event
            }
        }
        .onDisappear {
            for monitor in [flagsMonitor, escapeMonitor].compactMap(\.self) {
                NSEvent.removeMonitor(monitor)
            }
            flagsMonitor = nil
            escapeMonitor = nil
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: optionIsDown)
        .task(id: state.isHovered) {
            hoverHasSettled = false
            guard state.isHovered else { return }
            try? await Task.sleep(for: .seconds(Layout.hoverSettle))
            guard !Task.isCancelled else { return }
            hoverHasSettled = true
        }
        .task(id: avoidanceRevision) { await yieldToPageControl() }
        .task(id: keepsHoverOpen ? .inside : pointerPhase) { await settleHover() }
        .task(id: briefCardIsUnattended) {
            guard briefCardIsUnattended else { return }
            try? await Task.sleep(for: ControlIslandTabInfoState.briefShowHold)
            guard !Task.isCancelled else { return }
            state.tabInfo.foldBriefShow()
        }
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
                let highlightedItem = tour.highlightedItem
                VStack(spacing: 0) {
                    ForEach(railLayout.elements) { element in
                        switch element {
                        case let .row(item):
                            itemControl(item)
                                .background {
                                    if highlightedItem == item {
                                        rowHighlight
                                    }
                                }
                                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("browserControls")) } action: {
                                    state.reportFrame($0, for: item)
                                }
                        case .line:
                            sectionDivider
                        case .gap:
                            draggableBackground(Color.clear.frame(height: Layout.sectionGap).contentShape(Rectangle()))
                        case .grip:
                            grip
                        }
                    }
                }
            }
            .scrollIndicators(.automatic)
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.top, Layout.contentInset)
        .padding(.bottom, Layout.contentInset)
        .padding(.horizontal, Layout.horizontalInset)
        .background { dragSurface }
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
            // The lights rest with the glass: gray and faint while the rail is clear.
            ControlIslandWindowButtons()
                .frame(height: Layout.lightPitch * 3)
                .saturation(isResting ? 0 : 1)
                .opacity(isResting ? Layout.restingLightsOpacity : 1)
        case .navigation:
            navigationControls
        case .page:
            pageRow
        case .copyLink:
            control(item.title, symbol: item.symbol, enabled: windowState.activeTab != nil, help: item.detail) {
                guard let tab = windowState.activeTab else { return }
                ControlIslandTabActions(tab: tab, windowState: windowState, tabs: tabManager, bookmarks: bookmarks).copyLink()
                windowState.showToast("Address copied")
            }
        case .floatingTabs:
            let showsRecent = optionIsDown
            control(
                showsRecent ? "Recent tabs" : item.title,
                symbol: showsRecent ? "clock.arrow.circlepath" : (canvas.floatingVisibility.isRevealed ? "square.on.square.fill" : item.symbol),
                enabled: !showsRecent || tabSwitcher.isActive || tabSwitcher.canShowSwitcher,
                help: showsRecent ? "Recent tabs · ⌃Tab" : "Show your islands · hold \(revealKey.glyph) for a glance · \(revealKey.secondMeaningGlyph) for recent tabs",
            ) {
                if optionIsHeld {
                    showRecentTabs()
                } else {
                    dismissTransientOverlays()
                    canvas.toggleFloatingTabs()
                    showsShortcut = canvas.floatingVisibility.isRevealed
                }
            }
            .contentTransition(.symbolEffect(.replace))
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("browserControls")).midY } action: { shortcutRowMidY = $0 }
        case .spaces:
            ControlIslandSpaces(destinations: spaces.spaces, focusedControl: $focusedControl)
        case .favoriteTabs:
            ControlIslandFavoriteTabs(
                favorites: favorites, overflows: favoritesOverflow, onShowAll: { windowState.toggleDetailTray(.favorites) }, focusedControl: $focusedControl,
            )
        case .reload:
            control(
                reloadTitle,
                symbol: windowState.activeWebPage?.isLoading == true ? "xmark" : item.symbol,
                enabled: windowState.activeWebPage != nil,
            ) {
                if let page = windowState.activeWebPage {
                    if page.isLoading {
                        page.stopLoading()
                    } else {
                        _ = page.reload()
                    }
                }
            }
        case .favorites:
            control(item.title, symbol: item.symbol) { windowState.toggleDetailTray(.favorites) }
        case .history:
            control(item.title, symbol: item.symbol) { windowState.showDetailTray(.history) }
        case .bookmarks:
            control(item.title, symbol: item.symbol) { windowState.showDetailTray(.bookmarks) }
        case .settings:
            control(item.title, symbol: item.symbol) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        case .nowPlaying:
            nowPlayingControl(item)
        case .updates:
            updateControl(item)
        }
    }

    /// The second-meaning modifier is down as the button fires: the macOS way to ask a control
    /// for its other action.
    private var optionIsHeld: Bool {
        NSEvent.modifierFlags.contains(revealKey.secondMeaningFlag)
    }

    /// The recent-tab picker, in place of the lens and the tab layer.
    private func showRecentTabs() {
        windowState.closeCommandLens()
        canvas.dismissFloatingTabs()
        tabSwitcher.toggle()
    }

    /// The update badge: green while the window is active and the rail awake; it opens the restart sheet.
    private func updateControl(_ item: ControlIslandItem) -> some View {
        Button {
            showsUpdate = true
        } label: {
            ControlIslandRow {
                Image(systemName: item.symbol)
                    .foregroundStyle(isResting || !appearsActive ? AnyShapeStyle(.secondary) : AnyShapeStyle(.green))
            }
        }
        .focusable()
        .focused($focusedControl, equals: item.title)
        .focusEffectDisabled()
        .accessibilityLabel(item.title)
        .railHelp("Update ready · Restart to install")
    }

    /// Now Playing: a speaker while any tab plays sound; it opens the per-tab media controls.
    private func nowPlayingControl(_ item: ControlIslandItem) -> some View {
        let symbol = ControlIslandNowPlaying.symbol(for: mediaControls.activeSections)
        return Button {
            showsNowPlaying.toggle()
        } label: {
            ControlIslandRow {
                Image(systemName: symbol)
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    .animation(reduceMotion ? nil : .default, value: symbol)
            }
        }
        .focusable()
        .focused($focusedControl, equals: item.title)
        .focusEffectDisabled()
        .popover(isPresented: $showsNowPlaying, arrowEdge: opensLeft ? .leading : .trailing) {
            ControlIslandNowPlaying(isPresented: $showsNowPlaying)
                .readablePopoverBackground()
        }
        .accessibilityLabel(item.title)
        .railHelp("Now Playing · ⌃M mutes this tab")
    }

    /// The row the tour points at: a capsule inset in the cell, above the glass, with a glow around it.
    private var rowHighlight: some View {
        Capsule()
            .fill(Color.appAccentColor.opacity(Layout.highlightFillOpacity))
            .overlay { Capsule().strokeBorder(Color.appAccentColor, lineWidth: Layout.highlightLineWidth) }
            .shadow(color: Color.appAccentColor.opacity(Layout.highlightGlowOpacity), radius: Layout.highlightGlowRadius)
            .padding(Layout.highlightInset)
            .transition(.opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The whole rail lit for the tour, along its own corner.
    private var railHighlight: some View {
        WindowCorner.concentric
            .stroke(Color.appAccentColor, lineWidth: Layout.highlightLineWidth)
            .padding(Layout.highlightLineWidth / 2)
            .shadow(color: Color.appAccentColor.opacity(Layout.highlightGlowOpacity), radius: Layout.highlightGlowRadius)
            .transition(.opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var dragSurface: some View {
        draggableBackground(Color.clear.contentShape(Rectangle()))
    }

    /// Empty glass drags the window natively and carries the rail's own menu on a right-click.
    private func draggableBackground(_ content: some View) -> some View {
        content
            .contextMenu { ControlIslandRailMenu() }
            .gesture(windowDrag)
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

    /// A 3 × 2 grid of dots centered in the rail's final control row. It fades with the glass at rest.
    private var grip: some View {
        Grid(horizontalSpacing: Layout.gripDotSpacing, verticalSpacing: Layout.gripDotSpacing) {
            ForEach(0 ..< Layout.gripRows, id: \.self) { _ in
                GridRow {
                    ForEach(0 ..< Layout.gripColumns, id: \.self) { _ in
                        Circle()
                            .fill(.secondary)
                            .frame(width: Layout.gripDot, height: Layout.gripDot)
                    }
                }
            }
        }
        .frame(width: Layout.gripSize.width, height: Layout.gripSize.height)
        .opacity(isResting ? 0 : 1)
        .frame(width: Layout.contentWidth, height: Layout.rowHeight)
        .contentShape(Rectangle())
        .contextMenu { ControlIslandRailMenu() }
        .gesture(moveGesture)
        .railHelp("Move controls")
        .accessibilityElement()
        .accessibilityLabel("Move controls")
        .accessibilityAction(named: "Move controls left") { moveBy(dx: -32, dy: 0) }
        .accessibilityAction(named: "Move controls right") { moveBy(dx: 32, dy: 0) }
        .accessibilityAction(named: "Move controls up") { moveBy(dx: 0, dy: -32) }
        .accessibilityAction(named: "Move controls down") { moveBy(dx: 0, dy: 32) }
    }

    /// The pointer in the rail's coordinate space: window content, origin top-left.
    private var pointerLocation: CGPoint? {
        guard let window = windowState.window, let content = window.contentView else { return nil }
        let location = content.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        return CGPoint(x: location.x, y: content.isFlipped ? location.y : content.bounds.height - location.y)
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
            PageBackButton(
                webPage: page, canGoBack: page?.canGoBack == true,
                targetSize: CGSize(width: canGoForward ? Layout.contentWidth / 2 : Layout.contentWidth, height: Layout.rowHeight),
                highlightsOnHover: false, symbolWeight: Layout.navigationSymbolWeight,
            )
            .focusable()
            .focused($focusedControl, equals: "Back")
            .focusEffectDisabled()
            .railHelp("Back · ⌥ for history")
            .accessibilityLabel("Back")
            if canGoForward {
                PageForwardButton(
                    webPage: page, canGoForward: true,
                    targetSize: CGSize(width: Layout.contentWidth / 2, height: Layout.rowHeight),
                    highlightsOnHover: false, symbolWeight: Layout.navigationSymbolWeight,
                )
                .focusable()
                .focused($focusedControl, equals: "Forward")
                .focusEffectDisabled()
                .railHelp("Forward · ⌥ for history")
                .accessibilityLabel("Forward")
            }
        }
        .frame(width: Layout.contentWidth, height: Layout.rowHeight)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: canGoForward)
        .onChange(of: canGoForward) { _, available in
            if !available, focusedControl == "Forward" {
                focusedControl = "Back"
            }
        }
    }

    /// The current page's icon is the card's trigger: hover unfolds the card, a click keeps it open.
    private var pageRow: some View {
        Button {
            tabSwitcher.cancel()
            if state.tabInfo.isLatched {
                state.tabInfo.dismiss()
            } else {
                state.tabInfo.show()
            }
        } label: {
            ControlIslandRow {
                ZStack {
                    if let page = windowState.activePage {
                        FaviconView(data: page.faviconData, url: page.url, size: Layout.pageIconSize)
                            .saturation(appearsActive ? 1 : 0)
                    }
                    if windowState.activeWebPage?.isLoading == true {
                        Circle()
                            .trim(from: 0, to: max(0.05, windowState.activeWebPage?.estimatedProgress ?? 0))
                            .stroke(Color.appAccentColor, lineWidth: 1.5)
                            .rotationEffect(.degrees(-90))
                            .frame(width: Layout.pageLoadingRingSize, height: Layout.pageLoadingRingSize)
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
        .railHelp("Current page · Hover for its card · ⌘L edits the address")
        .accessibilityLabel("Current page")
        .accessibilityValue(windowState.activeWebPage?.isLoading == true ? "Loading" : (windowState.activePage?.url.safeDisplayDomain ?? "Ready"))
    }

    private func dismissTransientOverlays() {
        windowState.closeCommandLens()
        tabSwitcher.cancel()
    }

    private func control(_ title: String, symbol: String, enabled: Bool = true, help: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ControlIslandRow { Image(systemName: symbol) }
        }
        .disabled(!enabled)
        .focusable()
        .focused($focusedControl, equals: title)
        .focusEffectDisabled()
        .accessibilityLabel(title)
        .railHelp(help ?? title)
    }

    private func hoverChanged(_ phase: ControlIslandHoverPath.Phase) {
        guard pointerPhase != phase else { return }
        pointerPhase = phase
        if phase == .inside {
            state.isHovered = true
        }
    }

    /// A briefly shown page card with the pointer elsewhere and nothing open from it.
    private var briefCardIsUnattended: Bool {
        state.tabInfo.isShownBriefly && pointerPhase != .inside && !state.tabInfo.isHovered
            && !state.tabInfo.isMenuPresented && !windowState.showsAnchoredLens
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
        guard !isHiddenAtEdge else { return [] }
        var regions = [frame]
        if showsPageBranch, !windowState.showsAnchoredLens {
            regions.append(pageBranchFrame)
        }
        if showsShortcut {
            regions.append(shortcutFrame)
        }
        return regions
    }

    private var avoidanceRevision: String {
        "\(windowState.activePageID?.uuidString ?? "")-\(windowState.activeWebPage?.documentRevision.uuidString ?? "")-\(windowState.activeWebPage?.isLoading ?? false)-\(state.configuration.avoidsPageControls)"
    }

    private var canYield: Bool {
        guard state.configuration.avoidsPageControls, !state.isHovered, !state.isDragging,
              !state.hasKeyboardFocus, !state.isPresenting, !state.showsCustomization, !state.tabInfo.isVisible,
              !showsPageBranch, !canvas.floatingVisibility.isRevealed,
              !windowState.showsCommandLens,
              let window = windowState.window, window.isKeyWindow, window.attachedSheet == nil,
              NSEvent.pressedMouseButtons == 0, Date().timeIntervalSince(state.lastPointerMovement) > 0.8,
              let point = pointerLocation else { return false }
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

extension ControlIslandPlacement {
    /// The weight of the rail's 13-point symbols and the space picker's icons.
    static let symbolWeight: Font.Weight = .regular
    /// Back and forward use the address bar's 12-point chevrons, one weight heavier to match
    /// the 13-point symbols' presence.
    static let navigationSymbolWeight: Font.Weight = .medium
}

extension WindowState {
    /// The color every island surface carries: the window's resolved background at the
    /// island's tint opacity, or clear when tinting is off or the window has no color.
    var controlIslandTint: Color {
        let background = resolvedBackground
        guard controlIsland.configuration.tintsWithSpaceColor, background.source != .none else { return .clear }
        return Color(background.color.color).opacity(ControlIslandPlacement.spaceTintOpacity)
    }
}
