import AppKit
import SwiftUI

/// Source identity and a way back to the person's arranged work.
struct BrowserMarks: View {
    let area: CGRect
    @Environment(WindowState.self) private var windowState
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(TabManager.self) private var tabs
    @Environment(BookmarksManager.self) private var bookmarks
    @Environment(SpaceManager.self) private var spaces
    @Environment(\.appearsActive) private var appearsActive
    @State private var dragOrigin: CGPoint?
    @FocusState private var focusedControl: String?
    @AppStorage("browserMarks.navigation") private var showsNavigation = false
    @AppStorage("browserMarks.favorites") private var keepsFavorites = false
    @AppStorage("floatingTabs.revealKey") private var revealKey = FloatingRevealKey.control

    private var x: Double { windowState.controlIsland.markPlacement.x }
    private var y: Double { windowState.controlIsland.markPlacement.y }
    private var tab: Tab? { windowState.focusedPage?.tab ?? windowState.activeTab }
    private var isPreview: Bool { tab?.id != windowState.activeTabID }
    private var revealed: Bool { canvas.floatingVisibility.isRevealed }
    private var width: CGFloat { min(320, max(1, area.width - 24)) }
    private var height: CGFloat {
        40 + (windowState.pageVisit.destination != nil ? 40 : 0)
            + (revealed ? 80 : 0) + (showsNavigation ? 36 : 0)
    }
    private var frame: CGRect {
        CGRect(x: 12 + min(1, max(0, x)) * max(0, area.width - width - 24),
               y: 48 + min(1, max(0, y)) * max(0, area.height - height - 60), width: width, height: height)
    }
    private var recentFrame: CGRect {
        let popupHeight = min(320, max(1, area.height - 24))
        let below = frame.maxY + 8
        let proposedY = below + popupHeight <= area.maxY - 12 ? below : frame.minY - popupHeight - 8
        return CGRect(x: frame.minX, y: min(max(12, proposedY), max(12, area.maxY - popupHeight - 12)),
                      width: width, height: popupHeight)
    }

    var body: some View {
        @Bindable var controls = windowState.controlIsland
        VStack(alignment: .leading, spacing: 4) {
            markRow
            if let destination = windowState.pageVisit.destination {
                returnRow(destination)
            }
            if showsNavigation { navigationRow }
            if revealed { revealedControls }
        }
        .padding(4)
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .overlay {
            ControlIslandOptionDrag(target: controls.configuration.optionDragTarget, onFeedback: { _ in }, onBegin: {
                dragOrigin = frame.origin
                controls.isDragging = true
            }, onMove: { translation in
                guard let origin = dragOrigin else { return }
                controls.markPlacement.x = min(1, max(0, (origin.x + translation.width - 12) / max(1, area.width - width - 24)))
                controls.markPlacement.y = min(1, max(0, (origin.y + translation.height - 48) / max(1, area.height - height - 60)))
            }, onEnd: {
                dragOrigin = nil
                controls.isDragging = false
                windowState.window?.invalidateRestorableState()
            })
        }
        .offset(x: frame.minX, y: frame.minY)
        .font(.system(size: 12, weight: .medium))
        .buttonStyle(.plain)
        .foregroundStyle(appearsActive ? Color.primary : Color.secondary)
        .onAppear(perform: updateHitRegions)
        .onChange(of: frame) { updateHitRegions() }
        .onChange(of: revealed) { updateHitRegions() }
        .onChange(of: canvas.recentIsOpen) { updateHitRegions() }
        .onDisappear { controls.hitRegions = [] }
        .onChange(of: controls.focusRequest) { focusedControl = "page" }
        .onExitCommand {
            if windowState.pageVisit.destination != nil { tabs.returnFromLook(in: windowState) }
            else { canvas.dismissFloatingTabs() }
        }
        .sheet(isPresented: $controls.showsCustomization) {
            ControlIslandCustomizationSheet(configuration: controls.configuration)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Page and space")
        .overlay(alignment: .topLeading) {
            if canvas.recentIsOpen {
                FloatingRecentTabs(area: area)
                    .frame(width: recentFrame.width, height: recentFrame.height)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
                    .offset(x: recentFrame.minX, y: recentFrame.minY)
            }
        }
    }

    private var markRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
            Button { windowState.openAddressLens() } label: {
                HStack(spacing: 6) {
                    if let data = tab?.activePage.faviconData, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().frame(width: 16, height: 16)
                    } else { Image(systemName: "globe") }
                    Text(tab?.activePage.url.host ?? tab?.displayTitle ?? "Refrax")
                        .lineLimit(1).truncationMode(.middle)
                    if isPreview { Text("Preview").font(.caption2).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 8).frame(height: 32).contentShape(Rectangle())
            }
            .focused($focusedControl, equals: "page")
            .help(tab.map { "\($0.displayTitle) · Edit address" } ?? "Open address")
            .accessibilityLabel("Address: \(tab?.displayTitle ?? "Refrax")\(isPreview ? ", focused preview" : "")")
            if let tab {
                let actions = ControlIslandTabActions(tab: tab, windowState: windowState, tabs: tabs, bookmarks: bookmarks)
                markButton(actions.isFavorite ? "Remove Favorite" : "Favorite \(tab.displayTitle)", icon: actions.isFavorite ? "star.fill" : "star") {
                    actions.toggleFavorite()
                }.disabled(!actions.canFavorite)
            }
            if let tab { PageActionsMenu(tab: tab, area: area) }
            }
            .padding(.trailing, 4)
            .glassEffect(.regular, in: Capsule())
            Button { canvas.toggleFloatingTabs() } label: {
                Group {
                    if let space = windowState.activeSpace, space.isEmoji { Text(space.iconName) }
                    else { Image(systemName: windowState.activeSpace?.iconName ?? "square.on.square") }
                }.frame(width: 32, height: 32).contentShape(Circle())
            }
            .glassEffect(.regular, in: Circle())
            .help("Tabs · hold \(revealKey.title)")
            .accessibilityLabel("\(windowState.activeSpace?.name ?? "Space") · Show tabs · Hold \(revealKey.title)")
            .accessibilityValue(revealed ? "Tabs shown" : "Tabs hidden")
            .contextMenu {
                Button("Command Lens", systemImage: "sparkle.magnifyingglass") { windowState.openCommandLens() }
                ControlIslandAppearanceMenu()
            }
        }
    }

    private var browserMenu: some View {
        Menu {
            Toggle("Show Navigation", isOn: $showsNavigation)
            Toggle("Keep Favorites Visible", isOn: $keepsFavorites)
            Button("History") { windowState.showDetailTray(.history) }
            Button("Downloads") { windowState.showDetailTray(.downloads) }
            ControlIslandAppearanceMenu()
        } label: { Image(systemName: "ellipsis").frame(width: 28, height: 32).contentShape(Rectangle()) }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Browser actions")
    }

    private var revealedControls: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                if let tab {
                    Text(tab.displayTitle).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    PageActionsMenu(tab: tab, area: area)
                }
                if canvas.selectedFloatingTabIDs.count > 1 {
                    Button("Group Selected") { canvas.groupFloatingSelection() }
                }
                markButton("Command Lens", icon: "sparkle.magnifyingglass") { windowState.openCommandLens() }
                browserMenu
            }.padding(.horizontal, 8).frame(height: 32)
            HStack(spacing: 6) {
                ScrollView(.horizontal) {
                    HStack(spacing: 4) {
                        ForEach(spaces.spaces) { space in
                            Button {
                                guard space.id != windowState.activeSpaceID else { return }
                                windowState.pageVisit.end()
                                Task.immediate(name: "Recall space arrangement") {
                                    canvas.spaceToReveal = space.id
                                    await spaces.switchToSpace(space, for: windowState)
                                    if windowState.activeSpaceID != space.id { canvas.spaceToReveal = nil }
                                }
                            } label: {
                                Group {
                                    if space.isEmoji { Text(space.iconName) }
                                    else { Image(systemName: space.iconName) }
                                }
                                .foregroundStyle(space.id == windowState.activeSpaceID ? Color.primary : Color.secondary)
                                .frame(width: 30, height: 30).contentShape(Rectangle())
                                .background(space.id == windowState.activeSpaceID ? Color.primary.opacity(0.12) : .clear, in: Circle())
                            }.help(space.name).accessibilityLabel("Space: \(space.name)")
                                .accessibilityValue(space.id == windowState.activeSpaceID ? "Selected" : "")
                        }
                    }
                }.scrollIndicators(.hidden)
                Button("Recent · \(canvas.unplacedFloatingTabs.count)") { canvas.recentIsOpen.toggle() }
                    .padding(.trailing, 8)
            }.frame(height: 32)
        }
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var navigationRow: some View {
        HStack(spacing: 6) {
            markButton("Back", icon: "chevron.backward") { windowState.focusedWebPage?.goBack() }
                .disabled(windowState.focusedWebPage?.canGoBack != true)
            if windowState.focusedWebPage?.canGoForward == true {
                markButton("Forward", icon: "chevron.forward") { windowState.focusedWebPage?.goForward() }
            }
            markButton("Reload", icon: "arrow.clockwise") { _ = windowState.focusedWebPage?.reload() }
            Spacer()
            if let tab { PageActionsMenu(tab: tab, area: area) }
        }.frame(height: 32).padding(.horizontal, 8)
            .glassEffect(.regular, in: Capsule())
    }

    private func returnRow(_ destination: PageVisitState.Destination) -> some View {
        HStack {
            Button { tabs.returnFromLook(in: windowState) } label: {
                Label("Return to \(destination.title)", systemImage: "arrow.uturn.backward")
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).frame(height: 32).contentShape(Rectangle())
            }
            Button("Stay Here") { windowState.pageVisit.end() }.frame(height: 32)
        }.padding(.horizontal, 8).glassEffect(.regular, in: Capsule())
    }

    private func markButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 28, height: 32).contentShape(Rectangle()) }
            .help(title).accessibilityLabel(title)
    }

    private func updateHitRegions() {
        var regions = [frame]
        if canvas.recentIsOpen {
            regions.append(recentFrame)
        }
        windowState.controlIsland.hitRegions = regions
    }
}
