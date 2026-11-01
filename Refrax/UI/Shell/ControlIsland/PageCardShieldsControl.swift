import SwiftUI

/// The page card's Shields control: a shield with the number of loads Shields blocked on this
/// page, or a struck-through shield in the warning color while Shields is off for the page, and
/// a popover that names what was blocked or turns Shields back on.
struct PageCardShieldsControl: View {
    let page: WebPage?
    @Environment(BrowserState.self) private var browserState
    @Environment(BrowserSettings.self) private var settings
    @Environment(WindowState.self) private var windowState
    @State private var showsPopover = false

    private var state: ShieldsPageState {
        ShieldsPageState(
            isEnabled: settings.enableContentBlocking,
            host: page?.url?.host(),
            offSites: browserState.shields.allowlistedHosts,
            blocked: page?.shieldsLog.blockedCount ?? 0,
        )
    }

    var body: some View {
        let state = state
        Button {
            showsPopover = true
        } label: {
            Image(systemName: state.symbolName)
                .foregroundStyle(state.isFiltering ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.coral))
                .frame(width: PageCardPromptControls.Layout.controlSize, height: PageCardPromptControls.Layout.controlSize)
                .overlay(alignment: .topTrailing) {
                    if let badge = state.badge {
                        Text(badge)
                            .font(.system(size: 8.5, weight: .semibold).monospacedDigit())
                            .padding(.horizontal, 3)
                            .background(Capsule().fill(.background.secondary))
                            .offset(x: 1, y: 2)
                    }
                }
                .contentShape(Rectangle())
        }
        .disabled(page == nil || page?.url?.isWebURL != true)
        .help(state.title)
        .accessibilityLabel(state.title)
        .focusEffectDisabled()
        .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
            if let page {
                ShieldsPagePopover(page: page, state: state)
                    .readablePopoverBackground()
            }
        }
        .onChange(of: showsPopover) { _, presented in
            windowState.controlIsland.tabInfo.isMenuPresented = presented
        }
    }
}

/// What Shields did on one page and the site switch; while Shields is off for the page, it
/// leads with that and a button that turns it back on.
private struct ShieldsPagePopover: View {
    let page: WebPage
    let state: ShieldsPageState
    @Environment(BrowserState.self) private var browserState
    @Environment(BrowserSettings.self) private var settings
    @State private var log: RequestLog?

    private enum Layout {
        static let width: CGFloat = 320
        static let padding: CGFloat = 14
        static let shownHosts = 8
    }

    private var host: String {
        page.url?.safeDisplayDomain ?? ""
    }

    /// The current document's blocked and redirected loads, counted by host, most first.
    private var blockedHosts: [(host: String, count: Int)] {
        let documentStart = page.shieldsLog.documentStart
        let blocked = (log?.entries ?? []).filter { entry in
            entry.time >= documentStart && (entry.decision == .blocked || entry.decision == .redirected)
        }
        let counts = Dictionary(grouping: blocked) { $0.url.host() ?? $0.url.absoluteString }.mapValues(\.count)
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let explanation = state.offExplanation {
                offNotice(explanation)
            } else {
                Toggle(isOn: Binding(get: { true }, set: { _ in setSite(enabled: false) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Shields")
                            .font(.headline)
                        Text(host)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)

                Divider()

                if let log {
                    summary(log)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(Layout.padding)
        .frame(width: Layout.width, alignment: .leading)
        .task(id: [page.url?.absoluteString ?? "", "\(state.isFiltering)"]) {
            guard state.isFiltering else { return }
            log = try? await browserState.shields.requestLog(for: page, attributed: false)
        }
    }

    private func offNotice(_ explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(state.title, systemImage: state.symbolName)
                .font(.headline)
                .foregroundStyle(Color.coral)
            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Turn On") {
                turnOn()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private func summary(_ log: RequestLog) -> some View {
        let hosts = blockedHosts
        let total = hosts.reduce(0) { $0 + $1.count }
        Text(total == 1 ? "1 load blocked on this page" : "\(total) loads blocked on this page")
            .font(.callout.weight(.medium))
        if !hosts.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(hosts.prefix(Layout.shownHosts), id: \.host) { entry in
                    HStack {
                        Text(entry.host)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text("\(entry.count)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
        if !log.entries.isEmpty {
            Text("refrax-ctl page requests lists each load with the filter that blocked it.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Turns Shields back on where it is off (everywhere, or for the site that turned it off)
    /// and reloads, since WebKit applies content rules per navigation.
    private func turnOn() {
        switch state {
        case .off:
            settings.enableContentBlocking = true
        case let .offForSite(site):
            browserState.siteSettingsCoordinator.setContentBlockersEnabled(true, forSite: site)
        case .on:
            return
        }
        _ = page.reload()
    }

    /// Turns Shields off for the page's site and reloads.
    private func setSite(enabled: Bool) {
        guard let url = page.url else { return }
        browserState.siteSettingsCoordinator.setContentBlockersEnabled(enabled, for: url)
        _ = page.reload()
    }
}
