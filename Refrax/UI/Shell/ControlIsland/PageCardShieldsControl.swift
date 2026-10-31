import SwiftUI

/// The page card's Shields control: a shield with the number of loads Shields blocked on this
/// page, and a popover that names them and turns Shields off or on for the site.
struct PageCardShieldsControl: View {
    let page: WebPage?
    @Environment(BrowserState.self) private var browserState
    @Environment(BrowserSettings.self) private var settings
    @Environment(WindowState.self) private var windowState
    @State private var showsPopover = false

    private var url: URL? {
        page?.url
    }

    private var isOnForSite: Bool {
        guard let url else { return true }
        return browserState.siteSettingsCoordinator.contentBlockersEnabled(for: url)
    }

    private var blockedCount: Int {
        page?.shieldsLog.blockedCount ?? 0
    }

    private var title: String {
        if !settings.enableContentBlocking {
            return "Shields are off"
        }
        if !isOnForSite {
            return "Shields are off for this site"
        }
        return blockedCount == 1 ? "Shields blocked 1 load" : "Shields blocked \(blockedCount) loads"
    }

    var body: some View {
        Button {
            showsPopover = true
        } label: {
            Image(systemName: settings.enableContentBlocking && isOnForSite ? "shield.lefthalf.filled" : "shield.slash")
                .foregroundStyle(settings.enableContentBlocking && isOnForSite ? .primary : .secondary)
                .frame(width: PageCardPromptControls.Layout.controlSize, height: PageCardPromptControls.Layout.controlSize)
                .overlay(alignment: .topTrailing) {
                    if blockedCount > 0, isOnForSite {
                        Text(blockedCount < 100 ? "\(blockedCount)" : "99+")
                            .font(.system(size: 8.5, weight: .semibold).monospacedDigit())
                            .padding(.horizontal, 3)
                            .background(Capsule().fill(.background.secondary))
                            .offset(x: 1, y: 2)
                    }
                }
                .contentShape(Rectangle())
        }
        .disabled(page == nil || url?.isWebURL != true)
        .help(title)
        .accessibilityLabel(title)
        .focusEffectDisabled()
        .popover(isPresented: $showsPopover, arrowEdge: .bottom) {
            if let page {
                ShieldsPagePopover(page: page)
                    .readablePopoverBackground()
            }
        }
        .onChange(of: showsPopover) { _, presented in
            windowState.controlIsland.tabInfo.isMenuPresented = presented
        }
    }
}

/// What Shields did on one page, and the site switch.
private struct ShieldsPagePopover: View {
    let page: WebPage
    @Environment(BrowserState.self) private var browserState
    @Environment(BrowserSettings.self) private var settings
    @State private var log: RequestLog?
    @State private var isOnForSite = true

    private enum Layout {
        static let width: CGFloat = 320
        static let padding: CGFloat = 14
        static let shownHosts = 8
    }

    private var host: String {
        page.url?.safeDisplayDomain ?? ""
    }

    /// Blocked and redirected loads, counted by host, most first.
    private var blockedHosts: [(host: String, count: Int)] {
        let blocked = (log?.entries ?? []).filter { $0.decision == .blocked || $0.decision == .redirected }
        let counts = Dictionary(grouping: blocked) { $0.url.host() ?? $0.url.absoluteString }.mapValues(\.count)
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map { ($0.key, $0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: Binding(get: { isOnForSite }, set: setSite)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shields")
                        .font(.headline)
                    Text(host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .disabled(!settings.enableContentBlocking)

            Divider()

            if !settings.enableContentBlocking {
                Text("Shields are off in Settings → Privacy.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if !isOnForSite {
                Text("Nothing is filtered on \(host).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let log {
                summary(log)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(Layout.padding)
        .frame(width: Layout.width, alignment: .leading)
        .task(id: page.url) {
            if let url = page.url {
                isOnForSite = browserState.siteSettingsCoordinator.contentBlockersEnabled(for: url)
            }
            log = try? await browserState.shields.requestLog(for: page)
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
        if log.entries.contains(where: { $0.exactness == .attributed }) {
            Text("refrax-ctl page requests lists each load with the filter that blocked it.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Turns Shields off or on for the page's site and reloads, since WebKit applies content
    /// rules per navigation.
    private func setSite(_ enabled: Bool) {
        guard let url = page.url,
              let siteSettings = browserState.siteSettingsManager.settingsOrCreate(for: url)
        else { return }
        siteSettings.enableContentBlockers = enabled
        browserState.siteSettingsManager.save(siteSettings)
        isOnForSite = enabled
        _ = page.reload()
    }
}
