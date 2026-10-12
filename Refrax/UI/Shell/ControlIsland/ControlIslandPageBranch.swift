import SwiftUI

/// Page identity and actions stay attached to the panel while working with a page or preview.
struct ControlIslandPageBranch: View {
    let area: CGRect
    let onPresentationChange: (Bool) -> Void
    @Environment(WindowState.self) private var windowState
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(TabManager.self) private var tabs
    @Environment(BookmarksManager.self) private var bookmarks

    private var tab: Tab? { windowState.focusedPage?.tab ?? windowState.activeTab }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                AddressBar(onPresentationChange: onPresentationChange)
                    .environment(\.addressBarIsFloating, true)
                    .frame(maxWidth: .infinity)
                if let tab {
                    Divider().frame(height: 16).padding(.horizontal, 4)
                    pageActions(tab)
                }
            }
            .padding(.horizontal, 4)
            .frame(height: ControlIslandPlacement.pageBranchHeight)
            if let destination = windowState.pageVisit.destination {
                Divider().padding(.horizontal, 12)
                HStack(spacing: 4) {
                    Button {
                        tabs.returnFromLook(in: windowState)
                    } label: {
                        Label("Return to \(destination.title)", systemImage: "arrow.uturn.backward")
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    Button("Stay Here") { windowState.pageVisit.end() }
                        .frame(height: 36)
                }.padding(.horizontal, 12)
            }
        }
        .buttonStyle(ControlIslandButtonStyle())
        .focusEffectDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tab?.id == windowState.activeTabID ? "Current page controls" : "Focused preview controls")
        .onHover { windowState.controlIsland.tabInfo.isHovered = $0 }
    }

    private func pageActions(_ tab: Tab) -> some View {
        let actions = ControlIslandTabActions(tab: tab, windowState: windowState, tabs: tabs, bookmarks: bookmarks)
        let pinned = canvas.floatingPlacement(for: tab).isPinned
        return HStack(spacing: 0) {
            action(actions.isFavorite ? "Remove Favorite" : "Favorite this tab", symbol: actions.isFavorite ? "star.fill" : "star") {
                actions.toggleFavorite()
            }.disabled(!actions.canFavorite)
            action(pinned ? "Hide pinned preview" : "Keep preview visible", symbol: pinned ? "pin.fill" : "pin") {
                var placement = canvas.floatingPlacement(for: tab)
                placement.isPinned.toggle()
                if placement.isPinned { placement.setCompact(false, in: area) }
                canvas.updateFloatingPlacement(placement, for: tab)
            }
            PageActionsMenu(tab: tab, area: area)
                .frame(width: 32, height: 32)
        }
    }

    private func action(_ title: String, symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol).frame(width: 32, height: 32).contentShape(Rectangle())
        }.help(title).accessibilityLabel(title).focusEffectDisabled()
    }
}
