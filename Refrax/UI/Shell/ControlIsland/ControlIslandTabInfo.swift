import AppKit
import SwiftUI

/// Identifies the full-page tab and keeps its frequent actions beside the controls.
struct ControlIslandTabInfo: View {
    let area: CGRect
    @Environment(WindowState.self) private var windowState
    @Environment(TabManager.self) private var tabs
    @Environment(BookmarksManager.self) private var bookmarks
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(SpaceManager.self) private var spaces

    private enum Layout {
        static let inset: CGFloat = 12
        static let spacing: CGFloat = 8
        static let actionSize: CGFloat = 32
        static let faviconSize: CGFloat = 28
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.spacing) {
            HStack {
                Text("Current tab").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button { windowState.controlIsland.tabInfo.dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                    .accessibilityLabel("Dismiss tab info")
                    .focusEffectDisabled()
            }
            if let tab = windowState.activeTab {
                identity(tab)
                actions(tab)
            } else {
                Text("Choose a page to begin").font(.body)
                Button("Command Lens", systemImage: "sparkle.magnifyingglass") {
                    windowState.controlIsland.tabInfo.dismiss()
                    windowState.openCommandLens()
                }
                .frame(height: Layout.actionSize)
                .focusEffectDisabled()
            }
        }
        .padding(Layout.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onHover { windowState.controlIsland.tabInfo.isHovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Current tab")
    }

    private func identity(_ tab: Tab) -> some View {
        HStack(spacing: Layout.spacing) {
            FaviconView(data: tab.activePage.largeFaviconData ?? tab.activePage.faviconData,
                        url: tab.activePage.url, size: Layout.faviconSize)
                .faviconBackground()
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(tab.displayTitle).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    .help(tab.displayTitle)
                Text(tab.activePage.url.safeDisplayDomain).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
    }

    private func actions(_ tab: Tab) -> some View {
        let actions = ControlIslandTabActions(tab: tab, windowState: windowState, tabs: tabs, bookmarks: bookmarks)
        let pinned = tab.floatingPlacement?.isPinned == true
        return HStack(spacing: 4) {
            Button {
                actions.toggleFavorite()
            } label: {
                Label(actions.isFavorite ? "Favorited" : "Favorite", systemImage: actions.isFavorite ? "star.fill" : "star")
                    .frame(maxWidth: .infinity, minHeight: Layout.actionSize, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .disabled(!actions.canFavorite)
            .help(actions.canFavorite ? (actions.isFavorite ? "Remove from Favorites" : "Keep this tab in Favorites, in every space")
                  : "Favorites can hold up to \(bookmarks._maxLiveFavoriteTabs) live tabs")
            .accessibilityLabel(actions.isFavorite ? "Remove current tab from Favorites" : "Favorite current tab")
            .focusEffectDisabled()
            action(pinned ? "Hide pinned preview" : "Keep preview visible", symbol: pinned ? "pin.fill" : "rectangle.inset.filled") {
                var placement = canvas.floatingPlacement(for: tab)
                if !pinned { placement.setCompact(false, in: area) }
                placement.isPinned = !pinned
                canvas.updateFloatingPlacement(placement, for: tab)
            }
            action("Copy link", symbol: "link", perform: actions.copyLink)
            ControlIslandTabMenuButton(state: windowState.controlIsland.tabInfo, makeMenu: { menu(for: tab) }, onClose: {
                if !NSEvent.modifierFlags.contains(.control) { canvas.releaseFloatingTabs() }
            })
                .frame(width: Layout.actionSize, height: Layout.actionSize)
        }
    }

    private func action(_ title: String, symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .frame(width: Layout.actionSize, height: Layout.actionSize)
                .contentShape(Rectangle())
        }
        .help(title)
        .accessibilityLabel(title)
        .focusEffectDisabled()
    }

    private func menu(for tab: Tab) -> NSMenu {
        var items: [any MenuItemConvertible] = [
            MenuItem("Reload", systemImage: "arrow.clockwise") { _ = tabs.pagePool.existingPage(for: tab.activePage)?.reload() },
            MenuItem("Duplicate Tab", systemImage: "plus.square.on.square") {
                ControlIslandTabActions(tab: tab, windowState: windowState, tabs: tabs, bookmarks: bookmarks).duplicate()
            },
        ]
        let destinations = spaces.spaces.filter { $0.id != tab.space?.id }
        if !tab.isLiveFavorite, !destinations.isEmpty {
            items.append(SubMenu("Move to Space", systemImage: "square.stack") {
                for space in destinations {
                    MenuItem(space.name, systemImage: space.isEmoji ? nil : space.iconName) { tabs.moveTabs([tab], to: space) }
                }
            })
        }
        items.append(MenuDivider())
        items.append(MenuItem("Copy Link as Markdown", systemImage: "link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("[\(tab.displayTitle)](\(tabs.copyableURL(for: tab)))", forType: .string)
        })
        items.append(MenuDivider())
        items.append(MenuItem("Close Tab", systemImage: "xmark") { tabs.requestCloseTab(tab) })
        return items.asNSMenu()
    }
}
