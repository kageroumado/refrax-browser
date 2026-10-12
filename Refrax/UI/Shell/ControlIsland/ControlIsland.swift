import AppKit
import SwiftUI

/// A movable, fixed-width rail of browser controls.
struct ControlIsland: View {
    let area: CGRect

    @Environment(WindowState.self) private var windowState
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(TabSwitcherManager.self) private var tabSwitcher
    @Environment(BookmarksManager.self) private var bookmarks
    @Environment(SpaceManager.self) private var spaces
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive
    @FocusState private var focusedControl: String?
    @GestureState private var isDraggingWindow = false
    @GestureState private var isDraggingPanel = false
    @State private var isOptionDragging = false
    @State private var railDragFeedback: ControlIslandDragFeedback = .idle
    @State private var buttonDragFeedback: ControlIslandDragFeedback = .idle
    @State private var dragOrigin: CGPoint?
    @State private var collapseTask: Task<Void, Never>?
    @State private var showsFavorites = false
    @State private var showsAddressTools = false
    @State private var isPointerInside = false
    @State private var hoverPath = ControlIslandHoverPath()
    @State private var shortcutRowMidY: CGFloat?
    @State private var showsShortcut = false
    @State private var shortcutTask: Task<Void, Never>?
    @State private var avoidancePlacement: ControlIslandPlacement?
    @State private var showsInvitation = false
    @AppStorage("controlIsland.hasOpened") private var hasOpened = false
    @AppStorage("floatingTabs.revealKey") private var revealKey = FloatingRevealKey.control
    private typealias Layout = ControlIslandPlacement

    private var state: ControlIslandState {
        windowState.controlIsland
    }
    private var favorites: [FavoriteItem] {
        bookmarks.favorites.filter { $0.tab != nil }
    }
    private var visibleItems: [ControlIslandItem] { visibleItems(in: state.mode) }

    private func visibleItems(in mode: ControlIslandState.Mode) -> [ControlIslandItem] {
        state.configuration.visibleItems.filter { item in
            if mode == .button, [.navigation, .address, .reload].contains(item) { return false }
            return switch item {
            case .spaces: !spaces.spaces.isEmpty
            case .favoriteTabs: !favorites.isEmpty
            default: true
            }
        }
    }
    private var height: CGFloat { height(for: visibleItems) }

    private func height(for items: [ControlIslandItem]) -> CGFloat {
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
    private var frame: CGRect {
        state.mode == .button
            ? effectivePlacement.buttonPanelFrame(in: area, height: height)
            : effectivePlacement.railFrame(in: area, height: height)
    }
    private var effectivePlacement: ControlIslandPlacement { avoidancePlacement ?? state.placement }
    private var opensLeft: Bool {
        effectivePlacement.opensLeft(in: area)
    }
    private var pageBranchFrame: CGRect {
        let anchor = state.mode == .button ? buttonFrame : CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: Layout.railWidth)
        return effectivePlacement.pageBranchFrame(in: area, anchor: anchor,
            height: Layout.pageBranchHeight + (windowState.pageVisit.destination == nil ? 0 : 37))
    }
    private var showsPageBranch: Bool {
        windowState.activePage != nil && dragFeedback == .idle && !state.isDragging
            && (state.tabInfo.isVisible || state.showsAddress || state.isHovered || windowState.pageVisit.destination != nil
                || (state.mode == .button && state.isRevealed))
    }
    private var recentFrame: CGRect {
        effectivePlacement.pageBranchFrame(in: area, anchor: frame, height: min(320, area.height - Layout.margin * 2))
    }
    private var shortcutFrame: CGRect {
        let x = opensLeft ? frame.minX - 38 : frame.maxX + 8
        return CGRect(x: x, y: (shortcutRowMidY ?? frame.midY) - 14, width: 30, height: 28)
    }

    var body: some View {
        @Bindable var state = windowState.controlIsland
        GlassEffectContainer(spacing: 6) {
            ZStack(alignment: .topLeading) {
                if state.mode == .button {
                    revealButton
                }
                if showsInvitation, !state.isRevealed, state.mode == .button {
                    Button {
                        hasOpened = true
                        showsInvitation = false
                        windowState.openCommandLens()
                    } label: {
                        Image(systemName: "sparkle.magnifyingglass")
                            .frame(width: Layout.railWidth, height: Layout.rowHeight)
                            .contentShape(Rectangle())
                    }
                        .glassEffect(.regular, in: Capsule())
                        .offset(x: frame.minX, y: frame.minY)
                        .accessibilityLabel("Command Lens")
                }
                if state.isRevealed {
                    controls
                        .frame(width: frame.width, height: frame.height)
                        .glassEffect(.regular, in: .rect(cornerRadius: Layout.cornerRadius))
                        .offset(x: frame.minX, y: frame.minY)
                        .onHover(perform: hoverChanged)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: frame.midY > buttonFrame.midY ? .top : .bottom)))
                }
                if showsPageBranch, !canvas.recentIsOpen {
                    ControlIslandPageBranch(area: area, onPresentationChange: { presented in
                        showsAddressTools = presented
                        if !presented, !isPointerInside {
                            hoverChanged(false)
                        }
                    })
                    .frame(width: pageBranchFrame.width, height: pageBranchFrame.height)
                    .glassEffect(.regular, in: .rect(cornerRadius: Layout.pageBranchHeight / 2))
                    .offset(x: pageBranchFrame.minX, y: pageBranchFrame.minY)
                    .onHover(perform: hoverChanged)
                    .transition(.opacity)
                }
                if canvas.recentIsOpen {
                    FloatingRecentTabs(area: area)
                        .frame(width: recentFrame.width, height: recentFrame.height)
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                        .offset(x: recentFrame.minX, y: recentFrame.minY)
                        .onHover(perform: hoverChanged)
                }
                if showsShortcut, state.isRevealed {
                    Button { canvas.toggleFloatingTabs() } label: {
                        Text(revealKey.glyph).font(.system(size: 16, weight: .medium))
                            .frame(width: shortcutFrame.width, height: shortcutFrame.height)
                            .contentShape(Rectangle())
                    }
                    .glassEffect(.regular, in: .rect(cornerRadius: 7))
                    .offset(x: shortcutFrame.minX, y: shortcutFrame.minY)
                    .help("Hold \(revealKey.title) to reveal tabs; release to hide")
                    .accessibilityLabel("Tabs shortcut: hold \(revealKey.title)")
                }
                if state.isDragging {
                    let snap = state.placement.snapped(in: area, height: anchorHeight)
                    if snap != state.placement {
                        let target = snap.railFrame(in: area, height: anchorHeight)
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
        .onAppear(perform: updateHitRegions)
        .onChange(of: frame) { updateHitRegions() }
        .onChange(of: state.placement) { avoidancePlacement = nil }
        .onChange(of: buttonFrame) { updateHitRegions() }
        .onChange(of: pageBranchFrame) { updateHitRegions() }
        .onChange(of: showsPageBranch) { updateHitRegions() }
        .onChange(of: canvas.recentIsOpen) { updateHitRegions() }
        .onChange(of: showsShortcut) { updateHitRegions() }
        .onChange(of: showsInvitation) { updateHitRegions() }
        .onChange(of: shortcutFrame) { updateHitRegions() }
        .onChange(of: state.tabInfo.isVisible) { updateHitRegions() }
        .onChange(of: state.showsAddress) { updateHitRegions() }
        .onChange(of: dragFeedback) { updateHitRegions() }
        .onChange(of: state.isRevealed) { updateHitRegions() }
        .onChange(of: state.mode) { oldMode, _ in
            avoidancePlacement = nil
            let oldHeight = oldMode == .button ? Layout.railWidth : height(for: visibleItems(in: oldMode))
            let origin = state.placement.railFrame(in: area, height: oldHeight).origin
            state.placement.move(to: origin, in: area, height: anchorHeight)
            savePlacement()
            updateHitRegions()
        }
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
                if !isPointerInside { hoverChanged(false) }
            }
        }
        .onChange(of: showsFavorites || showsAddressTools) { _, presented in
            state.isPresenting = presented
            if !presented, !isPointerInside { hoverChanged(false) }
        }
        .onChange(of: state.focusRequest) {
            focusedControl = visibleItems.contains(.address) ? "Address" : "More"
        }
        .onChange(of: state.configuration.items) {
            focusedControl = nil
            if !visibleItems.contains(.address) {
                state.showsAddress = false
            }
        }
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
            collapseTask?.cancel()
            shortcutTask?.cancel()
            state.pointerMoved = nil
            state.hitRegions = []
            state.isHovered = false
            state.showsAddress = false
            state.hasKeyboardFocus = false
            state.isPresenting = false
            state.isLatched = false
            state.isDragging = false
            state.tabInfo.dismiss()
            dragOrigin = nil
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Browser controls")
        .accessibilityIdentifier("browser-control-island")
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: state.isRevealed)
        .task(id: state.mode) {
            guard state.mode == .button, !hasOpened else { return }
            showsInvitation = true
            guard !reduceMotion else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            showsInvitation = false
        }
        .task(id: avoidanceRevision) { await yieldToPageControl() }
    }

    private var controls: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(visibleItems) { item in
                        if hasSeparator(before: item) { sectionDivider }
                        itemControl(item)
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
        .background { optionDrag(isTrigger: false) }
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
        case .address:
            addressButton
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
                teachTabShortcut()
            }
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

    private var dragFeedback: ControlIslandDragFeedback {
        railDragFeedback == .idle ? buttonDragFeedback : railDragFeedback
    }

    private var dragSurface: some View {
        Color.clear
            .contentShape(Rectangle())
            .modifier(ControlIslandBackgroundDrag(target: state.configuration.optionDragTarget.backgroundTarget,
                                                  panelDrag: moveGesture, windowDrag: windowDrag))
    }

    private var anchorHeight: CGFloat { state.mode == .button ? Layout.railWidth : height }

    private var buttonFrame: CGRect { effectivePlacement.railFrame(in: area, height: Layout.railWidth) }

    private var sectionDivider: some View {
        Divider()
            .frame(height: Layout.sectionGap)
            .contentShape(Rectangle())
            .modifier(ControlIslandBackgroundDrag(target: state.configuration.optionDragTarget.backgroundTarget,
                                                  panelDrag: moveGesture, windowDrag: windowDrag))
    }

    private var revealButton: some View {
        Button {
            hasOpened = true
            showsInvitation = false
            if state.isLatched { state.dismiss() } else { state.isLatched = true }
        } label: {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: 17, weight: .medium))
                .frame(width: Layout.railWidth, height: Layout.railWidth)
                .contentShape(Circle())
        }
        .buttonStyle(ControlIslandButtonStyle())
        .glassEffect(.regular, in: Circle())
        .background { optionDrag(isTrigger: true) }
        .offset(x: buttonFrame.minX, y: buttonFrame.minY)
        .onHover(perform: hoverChanged)
        .contextMenu { ControlIslandAppearanceMenu() }
        .focusable()
        .focused($focusedControl, equals: "Reveal")
        .focusEffectDisabled()
        .accessibilityLabel(state.isLatched ? "Dismiss browser controls" : "Show browser controls")
        .help("Hover to reveal · Click to keep open or dismiss · Option-drag to move \(state.configuration.optionDragTarget == .panel ? "controls" : "window")")
        .accessibilityAction(named: "Move controls left") { moveBy(dx: -32, dy: 0) }
        .accessibilityAction(named: "Move controls right") { moveBy(dx: 32, dy: 0) }
        .accessibilityAction(named: "Move controls up") { moveBy(dx: 0, dy: -32) }
        .accessibilityAction(named: "Move controls down") { moveBy(dx: 0, dy: 32) }
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

    private func optionDrag(isTrigger: Bool) -> some View {
        ControlIslandOptionDrag(target: state.configuration.optionDragTarget, isEnabled: !state.isReorderingFavorites, onFeedback: { feedback in
            if isTrigger { buttonDragFeedback = feedback } else { railDragFeedback = feedback }
        }, onBegin: {
            isOptionDragging = true
            state.isDragging = true
        }, onMove: movePanel, onEnd: {
            isOptionDragging = false
            state.isDragging = false
            finishPanelDrag()
            if !isPointerInside { hoverChanged(false) }
        })
    }

    private func movePanel(by translation: CGSize) {
        let origin = dragOrigin ?? effectivePlacement.railFrame(in: area, height: anchorHeight).origin
        avoidancePlacement = nil
        dragOrigin = origin
        state.isDragging = true
        state.placement.move(to: CGPoint(x: origin.x + translation.width, y: origin.y + translation.height), in: area, height: anchorHeight)
    }

    private func finishPanelDrag() {
        guard dragOrigin != nil else { return }
        dragOrigin = nil
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.18)) {
            state.placement = state.placement.snapped(in: area, height: anchorHeight)
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

    private var addressButton: some View {
        Button {
            tabSwitcher.cancel()
            if windowState.activePage == nil {
                windowState.openCommandLens()
            } else {
                state.showsAddress = true
                windowState.addressBarFrame = pageBranchFrame
                windowState.openAddressLens()
            }
        } label: {
            ControlIslandRow {
                ZStack {
                    Image(systemName: "link")
                    if windowState.activeWebPage?.isLoading == true {
                        ProgressView(value: windowState.activeWebPage?.estimatedProgress ?? 0)
                            .progressViewStyle(.circular)
                            .frame(width: 26, height: 26)
                    }
                }
            }
        }
        .focusable()
        .focused($focusedControl, equals: "Address")
        .focusEffectDisabled()
        .onHover { hovering in
            if hovering, windowState.activePage != nil {
                state.showsAddress = true
            }
        }
        .help("Edit address · ⌘L · Hover for page controls")
        .accessibilityLabel("Edit address")
        .accessibilityValue(windowState.activeWebPage?.isLoading == true ? "Loading" : (windowState.activePage?.url.safeDisplayDomain ?? "Ready"))
    }

    private func dismissTransientOverlays() {
        windowState.closeCommandLens()
        tabSwitcher.cancel()
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

    private func hoverChanged(_ hovering: Bool) {
        isPointerInside = hovering
        if hovering {
            collapseTask?.cancel()
            collapseTask = nil
            state.isHovered = true
            hasOpened = true
            showsInvitation = false
        } else {
            guard collapseTask == nil else { return }
            collapseTask = Task(name: "Collapse browser controls") {
                defer { collapseTask = nil }
                try? await Task.sleep(for: .milliseconds(550))
                guard !Task.isCancelled, !state.isDragging, !showsFavorites, !showsAddressTools else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                    state.isHovered = false
                    state.showsAddress = false
                    state.tabInfo.isHovered = false
                }
            }
        }
    }

    private func updateHitRegions() {
        state.pointerMoved = { point in
            hoverChanged(hoverPath.contains(point, regions: state.hitRegions))
        }
        var regions: [CGRect] = []
        if state.mode == .button { regions.append(buttonFrame) }
        if showsInvitation, !state.isRevealed, state.mode == .button {
            regions.append(CGRect(x: frame.minX, y: frame.minY, width: Layout.railWidth, height: Layout.rowHeight))
        }
        if state.isRevealed { regions.append(frame) }
        if showsPageBranch, !canvas.recentIsOpen { regions.append(pageBranchFrame) }
        if canvas.recentIsOpen { regions.append(recentFrame) }
        if showsShortcut, state.isRevealed { regions.append(shortcutFrame) }
        state.hitRegions = regions
    }

    private func teachTabShortcut() {
        shortcutTask?.cancel()
        showsShortcut = canvas.floatingVisibility.isRevealed
        shortcutTask = Task(name: "Settle tab shortcut reminder") {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            showsShortcut = false
        }
    }

    private var avoidanceRevision: String {
        "\(windowState.activePageID?.uuidString ?? "")-\(windowState.activeWebPage?.documentRevision.uuidString ?? "")-\(windowState.activeWebPage?.isLoading ?? false)-\(state.configuration.avoidsPageControls)-\(state.mode.rawValue)"
    }

    private var canYield: Bool {
        guard state.configuration.avoidsPageControls, !state.isHovered, !state.isDragging, !state.isLatched,
              !state.hasKeyboardFocus, !state.isPresenting, !state.showsCustomization, !state.tabInfo.isVisible,
              !showsPageBranch, !canvas.floatingVisibility.isRevealed, !canvas.recentIsOpen,
              !windowState.showsCommandLens, !windowState.showsAddressLens,
              let window = windowState.window, window.isKeyWindow, window.attachedSheet == nil,
              NSEvent.pressedMouseButtons == 0, Date().timeIntervalSince(state.lastPointerMovement) > 0.8,
              let content = window.contentView else { return false }
        let location = content.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let point = CGPoint(x: location.x, y: content.isFlipped ? location.y : content.bounds.height - location.y)
        let anchor = effectivePlacement.railFrame(in: area, height: anchorHeight)
        return !anchor.insetBy(dx: -96, dy: -96).contains(point)
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
              windowState.activeWebPage === page, revision == page.documentRevision else { return }
        let source = placement.railFrame(in: area, height: anchorHeight)
        var adjusted: ControlIslandPlacement?
        if let origin = ControlIslandAvoidance.proposedOrigin(for: source, in: area, obstacles: obstacles) {
            var next = placement
            next.move(to: origin, in: area, height: anchorHeight)
            adjusted = next
        }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { avoidancePlacement = adjusted }
    }

    private func moveBy(dx: CGFloat, dy: CGFloat) {
        let origin = effectivePlacement.railFrame(in: area, height: anchorHeight).origin
        avoidancePlacement = nil
        state.placement.move(to: CGPoint(x: origin.x + dx, y: origin.y + dy), in: area, height: anchorHeight)
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

private struct ControlIslandBackgroundDrag<PanelMovement: Gesture, WindowMovement: Gesture>: ViewModifier {
    let target: ControlIslandDragTarget
    let panelDrag: PanelMovement
    let windowDrag: WindowMovement

    @ViewBuilder
    func body(content: Content) -> some View {
        if target == .panel { content.gesture(panelDrag) }
        else { content.gesture(windowDrag) }
    }
}
