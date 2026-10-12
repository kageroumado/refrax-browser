import SwiftUI

/// The current page as one card beside the rail: its icon, title, and domain, with reload,
/// favorite, and the page actions. Tapping the identity opens the Command Lens in the card's
/// place with the address in it.
struct ControlIslandPageBranch: View {
    let area: CGRect
    let frame: CGRect
    @Environment(WindowState.self) private var windowState
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(TabManager.self) private var tabs
    @Environment(BookmarksManager.self) private var bookmarks
    @Environment(EngineRegistry.self) private var engineRegistry
    @Environment(\.appearsActive) private var appearsActive

    private enum Layout {
        static let faviconSize: CGFloat = 18
        static let titleSize: CGFloat = 12.5
        static let domainSize: CGFloat = 11
        static let leadingInset: CGFloat = 12
        static let trailingInset: CGFloat = 6
        static let actionSize: CGFloat = 30
        static let returnRowHeight: CGFloat = 36
    }

    private var tab: Tab? { windowState.focusedPage?.tab ?? windowState.activeTab }
    private var page: WebPage? { tab.flatMap { tabs.pagePool.existingPage(for: $0.activePage) } }
    private var url: URL? { tab?.activePage.url }
    private var domain: String { url?.safeDisplayDomain ?? "" }
    private var isLoading: Bool { page?.isLoading == true }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                if let tab {
                    identity(tab)
                    Spacer(minLength: 6)
                    actions(tab)
                }
            }
            .padding(.leading, Layout.leadingInset)
            .padding(.trailing, Layout.trailingInset)
            .frame(height: ControlIslandPlacement.pageBranchHeight)
            .overlay(alignment: .bottom) {
                LoadingIndicatorBar(isLoading: isLoading, progress: page?.estimatedProgress ?? 0, horizontalInset: Layout.leadingInset)
            }
            if let destination = windowState.pageVisit.destination {
                Divider().padding(.horizontal, Layout.leadingInset)
                HStack(spacing: 4) {
                    Button {
                        tabs.returnFromLook(in: windowState)
                    } label: {
                        Label("Return to \(destination.title)", systemImage: "arrow.uturn.backward")
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: Layout.returnRowHeight, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    Button("Stay Here") { windowState.pageVisit.end() }
                        .frame(height: Layout.returnRowHeight)
                }.padding(.horizontal, Layout.leadingInset)
            }
        }
        .buttonStyle(ControlIslandButtonStyle())
        .focusEffectDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tab?.id == windowState.activeTabID ? "Current page" : "Focused preview")
        .onHover { windowState.controlIsland.tabInfo.isHovered = $0 }
    }

    private func identity(_ tab: Tab) -> some View {
        Button {
            windowState.addressBarFrame = frame
            windowState.openCommandLens(prefill: url?.absoluteString ?? "", anchor: frame)
        } label: {
            HStack(spacing: 9) {
                FaviconView(data: tab.activePage.faviconData, url: url, size: Layout.faviconSize)
                    .saturation(appearsActive ? 1 : 0)
                VStack(alignment: .leading, spacing: 1) {
                    Text(tab.displayTitle)
                        .font(.system(size: Layout.titleSize, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        engineBadge
                        Text(domain.isEmpty ? "Search or go…" : domain)
                            .font(.system(size: Layout.domainSize))
                            .foregroundStyle(domainColor)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .help("Edit address · ⌘L")
        .accessibilityLabel("Edit address")
        .accessibilityValue(isLoading ? "Loading \(domain)" : domain)
    }

    @ViewBuilder
    private var engineBadge: some View {
        if let engineID = page?.activeEngineID, engineID != .systemWebKit, let icon = engineRegistry.icon(for: engineID) {
            let descriptor = engineRegistry.descriptor(for: engineID)
            AddressBarEngineBadge(icon: icon, engineName: descriptor.map { "\($0.displayName) (\($0.engineVersion))" } ?? engineID.rawValue)
        }
    }

    /// Red only for a certificate failure or mixed content; orange for a local address.
    private var domainColor: Color {
        guard let page else { return .secondary }
        let certificate = page.certificateInfo
        switch page.securityState {
        case .mixedContent: return .red
        case .insecure: if case .invalid = certificate.trustState { return .red } else { return .secondary }
        case .localNetwork: return .orange
        case .secure: return .secondary
        }
    }

    private func actions(_ tab: Tab) -> some View {
        let actions = ControlIslandTabActions(tab: tab, windowState: windowState, tabs: tabs, bookmarks: bookmarks)
        return HStack(spacing: 0) {
            AddressBarReloadButton(
                isLoading: isLoading,
                onReload: { if isLoading { page?.stopLoading() } else { _ = page?.reload() } },
                onReloadFromOrigin: { _ = page?.reload(fromOrigin: true) },
                onReloadWithoutContentBlockers: { page?.reloadWithoutContentBlockers() },
                otherEngines: engineRegistry.descriptors.filter { $0.id != (page?.activeEngineID ?? .systemWebKit) },
                onReloadInEngine: { page?.reload(in: $0, registry: engineRegistry) },
            )
            .disabled(page == nil)
            action(actions.isFavorite ? "Remove from Favorites" : "Add to Favorites", symbol: actions.isFavorite ? "star.fill" : "star") {
                actions.toggleFavorite()
            }
            .disabled(!actions.canFavorite)
            PageActionsMenu(tab: tab, area: area)
                .frame(width: Layout.actionSize, height: Layout.actionSize)
        }
    }

    private func action(_ title: String, symbol: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol).frame(width: Layout.actionSize, height: Layout.actionSize).contentShape(Rectangle())
        }.help(title).accessibilityLabel(title).focusEffectDisabled()
    }
}
