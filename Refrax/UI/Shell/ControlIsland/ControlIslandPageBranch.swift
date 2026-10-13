import SwiftUI

/// The current page as one card beside the rail: its icon, title, and domain, then Reload,
/// Favorite, Copy Address while the pointer is on the card, and the page options. Tapping the
/// identity opens the Command Lens in the card's place with the address in it.
struct ControlIslandPageBranch: View {
    let area: CGRect
    let frame: CGRect
    @Environment(WindowState.self) private var windowState
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(TabManager.self) private var tabs
    @Environment(BookmarksManager.self) private var bookmarks
    @Environment(EngineRegistry.self) private var engineRegistry
    @Environment(ModifierKeysState.self) private var modifierKeys
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsOptions = false
    @State private var showsWebpageSettings = false
    @State private var showsSiteCookies = false
    @State private var showsCopiedFeedback = false

    private enum Layout {
        /// Spans the identity's ink: from the top of the title's capitals to the bottom of the
        /// domain line, about 24 points for 12.5-point over 11-point text.
        static let faviconSize: CGFloat = 24
        static let titleSize: CGFloat = 12.5
        static let domainSize: CGFloat = 11
        /// From the card's leading edge to the favicon.
        static let leadingInset: CGFloat = 12
        /// From the favicon to the title and domain.
        static let faviconGap: CGFloat = 9
        /// From the identity to the first control.
        static let identityGap: CGFloat = 6
        /// Every control is one square target of this size.
        static let controlSize: CGFloat = 30
        static let controlSpacing: CGFloat = 2
        /// From the last control to the card's trailing edge.
        static let trailingInset: CGFloat = 6
        static let copiedFeedback: TimeInterval = 1.5
    }

    private var tab: Tab? {
        windowState.focusedPage?.tab ?? windowState.activeTab
    }
    private var page: WebPage? {
        tab.flatMap { tabs.pagePool.existingPage(for: $0.activePage) }
    }
    private var url: URL? {
        tab?.activePage.url
    }
    private var domain: String {
        url?.safeDisplayDomain ?? ""
    }
    private var isLoading: Bool {
        page?.isLoading == true
    }
    private var tabInfo: ControlIslandTabInfoState {
        windowState.controlIsland.tabInfo
    }
    private var showsCopyAddress: Bool {
        tabInfo.showsHoverExtras
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Layout.identityGap) {
                if let tab {
                    identity(tab)
                    controls(tab)
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
                LookReturnRow(destination: destination, beganAt: windowState.pageVisit.beganAt)
            }
        }
        .buttonStyle(ControlIslandButtonStyle())
        .focusEffectDisabled()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(tab?.id == windowState.activeTabID ? "Current page" : "Focused preview")
        .onHover { tabInfo.isHovered = $0 }
        .onChange(of: showsOptions || showsWebpageSettings) { _, presented in
            tabInfo.isMenuPresented = presented
            canvas.menuTabID = presented ? tab?.id : nil
        }
        .onDisappear {
            if showsOptions || showsWebpageSettings {
                tabInfo.isMenuPresented = false
                canvas.menuTabID = nil
            }
        }
    }

    private func identity(_ tab: Tab) -> some View {
        Button {
            tabInfo.show()
            windowState.addressBarFrame = frame
            windowState.openCommandLens(prefill: url?.absoluteString ?? "", anchor: frame)
        } label: {
            HStack(spacing: Layout.faviconGap) {
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
        case .insecure: if case .invalid = certificate.trustState {
                return .red
            } else {
                return .secondary
            }
        case .localNetwork: return .orange
        case .secure: return .secondary
        }
    }

    // MARK: - Controls

    /// Copy Address (its slot reserved at the leading edge, shown while the card is hovered),
    /// Reload, Favorite, and the page options.
    private func controls(_ tab: Tab) -> some View {
        let actions = ControlIslandTabActions(tab: tab, windowState: windowState, tabs: tabs, bookmarks: bookmarks)
        return HStack(spacing: Layout.controlSpacing) {
            copyControl(actions)
                .opacity(showsCopyAddress ? 1 : 0)
                .allowsHitTesting(showsCopyAddress)
                .accessibilityHidden(!showsCopyAddress)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: showsCopyAddress)
            PageCardPromptControls(page: page)
            reloadControl
            control(actions.isFavorite ? "Remove from Favorites" : "Add to Favorites", symbol: actions.isFavorite ? "star.fill" : "star") {
                actions.toggleFavorite()
            }
            .disabled(!actions.canFavorite)
            optionsControl(tab)
        }
    }

    private var reloadControl: some View {
        control(isLoading ? "Stop loading" : "Reload page", symbol: isLoading ? "xmark" : "arrow.clockwise") {
            if isLoading {
                page?.stopLoading()
            } else {
                _ = page?.reload()
            }
        }
        .modifier(ReloadOptionsMenu(
            onReload: { _ = page?.reload() },
            onReloadFromOrigin: { _ = page?.reload(fromOrigin: true) },
            onReloadWithoutContentBlockers: { page?.reloadWithoutContentBlockers() },
            otherEngines: engineRegistry.descriptors.filter { $0.id != (page?.activeEngineID ?? .systemWebKit) },
            onReloadInEngine: { page?.reload(in: $0, registry: engineRegistry) },
        ))
        .disabled(page == nil)
    }

    /// Copies the address; with Option, the page as a Markdown link. A checkmark confirms either.
    private func copyControl(_ actions: ControlIslandTabActions) -> some View {
        let asMarkdown = modifierKeys.isOptionPressed
        return control(
            asMarkdown ? "Copy as Markdown Link" : "Copy Address",
            symbol: showsCopiedFeedback ? "checkmark" : "link",
            confirms: showsCopiedFeedback,
        ) {
            if asMarkdown {
                actions.copyMarkdownLink()
            } else {
                actions.copyLink()
            }
            showsCopiedFeedback = true
            Task(name: "Clear copied feedback") {
                try? await Task.sleep(for: .seconds(Layout.copiedFeedback))
                showsCopiedFeedback = false
            }
        }
    }

    private func optionsControl(_ tab: Tab) -> some View {
        control("Page options", symbol: "ellipsis") {
            showsOptions = true
        }
        .if(showsOptions) { view in
            view.popover(isPresented: $showsOptions, arrowEdge: .bottom) {
                PageCardOptionsPopover(
                    tab: tab,
                    area: area,
                    dismiss: { showsOptions = false },
                    onWebpageSettings: { showsWebpageSettings = true },
                    onShowCookies: { showsSiteCookies = true },
                )
            }
        }
        .if(showsWebpageSettings) { view in
            view.popover(isPresented: $showsWebpageSettings, arrowEdge: .bottom) {
                WebpageSettingsPopover(domain: domain, origin: url.flatMap(WebOrigin.init(url:)))
            }
        }
        .sheet(isPresented: $showsSiteCookies) {
            if let dataStore = page?.websiteDataStore {
                SiteCookiesView(domain: domain, dataStore: dataStore)
            }
        }
    }

    /// One square control; `confirms` draws its symbol green while an action is being confirmed.
    private func control(_ title: String, symbol: String, confirms: Bool = false, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Image(systemName: symbol)
                .if(confirms) { $0.foregroundStyle(.green) }
                .frame(width: Layout.controlSize, height: Layout.controlSize)
                .contentShape(Rectangle())
        }
        .help(title)
        .accessibilityLabel(title)
        .focusEffectDisabled()
    }
}

/// The way back from a Look: "Return to *title*" beside "Stay Here". A visit that has just
/// begun underlines the row in the space color and the underline fades, so the row is seen
/// before the rail rests; with Reduce Motion the underline stays for the visit.
private struct LookReturnRow: View {
    let destination: PageVisitState.Destination
    let beganAt: Date?
    @Environment(WindowState.self) private var windowState
    @Environment(TabManager.self) private var tabs
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var emphasis = 1.0

    private enum Layout {
        static let inset: CGFloat = 12
        static let rowHeight: CGFloat = 36
        static let underlineHeight: CGFloat = 2
        static let emphasisDuration: TimeInterval = 1.2
    }

    /// The visit began within the emphasis; a row shown later stays plain.
    private var isFresh: Bool {
        guard let beganAt else { return false }
        return Date().timeIntervalSince(beganAt) < Layout.emphasisDuration
    }

    var body: some View {
        HStack(spacing: 4) {
            Button {
                tabs.returnFromLook(in: windowState)
            } label: {
                Label("Return to \(destination.title)", systemImage: "arrow.uturn.backward")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: Layout.rowHeight, alignment: .leading)
                    .contentShape(Rectangle())
            }
            Button("Stay Here") { windowState.pageVisit.end() }
                .frame(height: Layout.rowHeight)
        }
        .padding(.horizontal, Layout.inset)
        .overlay(alignment: .bottom) {
            Capsule()
                .fill(windowState.activeSpace?.color ?? Color.appAccentColor)
                .frame(height: Layout.underlineHeight)
                .padding(.horizontal, Layout.inset)
                .opacity(reduceMotion ? 1 : (isFresh ? emphasis : 0))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .onAppear {
            guard !reduceMotion, isFresh else { return }
            withAnimation(.easeOut(duration: Layout.emphasisDuration)) { emphasis = 0 }
        }
    }
}
