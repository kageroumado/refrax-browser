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
    @State private var addressRowMidY: CGFloat?
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
            default: true
            }
        }
    }
    private var height: CGFloat {
        let rowCount = visibleItems.reduce(1) { count, item in
            switch item {
            case .windowControls: count + 3
            case .spaces: count
            case .favoriteTabs: count
            default: count + 1
            }
        }
        let separators = visibleItems.filter(hasSeparator).count + (visibleItems.last?.isGroup == true ? 1 : 0)
        return Layout.contentInset * 2
            + Layout.rowHeight * CGFloat(rowCount) + Layout.sectionGap * CGFloat(separators)
            + (visibleItems.contains(.spaces) ? CGFloat(min(spaces.spaces.count, Layout.maximumVisibleSpaces)) * Layout.spaceRowHeight : 0)
            + (visibleItems.contains(.favoriteTabs) ? ControlIslandFavoriteTabs.height(for: favorites.count) : 0)
    }

    private func hasSeparator(before item: ControlIslandItem) -> Bool {
        guard let index = visibleItems.firstIndex(of: item), index > 0 else { return false }
        return item.isGroup || visibleItems[index - 1].isGroup
    }
    private var frame: CGRect {
        state.mode == .button
            ? state.placement.buttonPanelFrame(in: area, height: height)
            : state.placement.railFrame(in: area, height: height)
    }
    private var opensLeft: Bool {
        state.placement.opensLeft(in: area)
    }
    private var addressFrame: CGRect {
        state.placement.addressFrame(in: area, island: frame, rowMidY: addressRowMidY)
    }
    private var tabInfoFrame: CGRect {
        state.placement.tabInfoFrame(in: area, island: frame)
    }

    var body: some View {
        @Bindable var state = windowState.controlIsland
        GlassEffectContainer(spacing: 6) {
            ZStack(alignment: .topLeading) {
                if state.mode == .button {
                    revealButton
                }
                if state.isRevealed {
                    controls
                        .frame(width: frame.width, height: frame.height)
                        .glassEffect(.regular, in: .rect(cornerRadius: Layout.cornerRadius))
                        .offset(x: frame.minX, y: frame.minY)
                        .onHover(perform: hoverChanged)
                }
                if state.showsAddress, !state.tabInfo.isVisible, dragFeedback == .idle {
                    AddressBar(onPresentationChange: { presented in
                        showsAddressTools = presented
                        if !presented, !isPointerInside {
                            hoverChanged(false)
                        }
                    })
                    .environment(\.addressBarIsFloating, true)
                    .frame(width: addressFrame.width, height: addressFrame.height)
                    .glassEffect(.regular, in: Capsule())
                    .offset(x: addressFrame.minX, y: addressFrame.minY)
                    .onHover(perform: hoverChanged)
                }
                if state.tabInfo.isVisible {
                    ControlIslandTabInfo(area: area)
                        .frame(width: tabInfoFrame.width, height: tabInfoFrame.height)
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                        .offset(x: tabInfoFrame.minX, y: tabInfoFrame.minY)
                }
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .buttonStyle(ControlIslandButtonStyle())
        .onAppear(perform: updateHitRegions)
        .onChange(of: frame) { updateHitRegions() }
        .onChange(of: buttonFrame) { updateHitRegions() }
        .onChange(of: addressFrame) { updateHitRegions() }
        .onChange(of: tabInfoFrame) { updateHitRegions() }
        .onChange(of: state.tabInfo.isVisible) { updateHitRegions() }
        .onChange(of: state.showsAddress) { updateHitRegions() }
        .onChange(of: dragFeedback) { updateHitRegions() }
        .onChange(of: state.isRevealed) { updateHitRegions() }
        .onChange(of: state.mode) { oldMode, _ in
            let oldHeight = oldMode == .button ? Layout.railWidth : height
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
        .onChange(of: focusedControl) { state.hasKeyboardFocus = focusedControl != nil }
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
                addressRowMidY = nil
            }
        }
        .sheet(isPresented: $state.showsCustomization) {
            ControlIslandCustomizationSheet(configuration: state.configuration)
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
        .onChange(of: windowState.showsCompactAddressBar) { _, shown in
            if shown {
                windowState.showsCompactAddressBar = false
            }
        }
        .onDisappear {
            collapseTask?.cancel()
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
            }
            .help(item.detail)
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

    private var buttonFrame: CGRect { state.placement.railFrame(in: area, height: Layout.railWidth) }

    private var sectionDivider: some View {
        Divider()
            .frame(height: Layout.sectionGap)
            .contentShape(Rectangle())
            .modifier(ControlIslandBackgroundDrag(target: state.configuration.optionDragTarget.backgroundTarget,
                                                  panelDrag: moveGesture, windowDrag: windowDrag))
    }

    private var revealButton: some View {
        Button {
            if state.isLatched { state.dismiss() } else { state.isLatched = true }
        } label: {
            Image(systemName: "circle.grid.2x2")
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
        let origin = dragOrigin ?? state.placement.railFrame(in: area, height: anchorHeight).origin
        dragOrigin = origin
        state.isDragging = true
        state.placement.move(to: CGPoint(x: origin.x + translation.width, y: origin.y + translation.height), in: area, height: anchorHeight)
    }

    private func finishPanelDrag() {
        guard dragOrigin != nil else { return }
        dragOrigin = nil
        savePlacement()
    }

    private var navigationControls: some View {
        let page = windowState.activeWebPage
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
                windowState.addressBarFrame = addressFrame
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
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("browserControls")).midY } action: { addressRowMidY = $0 }
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
        collapseTask?.cancel()
        if hovering {
            state.isHovered = true
        } else {
            collapseTask = Task(name: "Collapse browser controls") {
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled, !state.isDragging, !showsFavorites, !showsAddressTools else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
                    state.isHovered = false
                    state.showsAddress = false
                }
            }
        }
    }

    private func updateHitRegions() {
        var regions: [CGRect] = []
        if state.mode == .button { regions.append(buttonFrame) }
        if state.isRevealed { regions.append(frame) }
        if state.showsAddress, !state.tabInfo.isVisible, dragFeedback == .idle { regions.append(addressFrame) }
        if state.tabInfo.isVisible { regions.append(tabInfoFrame) }
        state.hitRegions = regions
    }

    private func moveBy(dx: CGFloat, dy: CGFloat) {
        let origin = state.placement.railFrame(in: area, height: anchorHeight).origin
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
