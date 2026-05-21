import SwiftUI

/// A popover displaying detailed metadata about a tab and its pages.
///
/// Shows information organized in sections:
/// - **Tab Info**: Title, custom name, status, group, timestamps
/// - **Page Info**: URL, security, created date (nested for multi-page tabs)
/// - **Runtime Info**: Loading state, audio, navigation (if WebPage is active)
struct TabInfoPopover: View {
    let tab: Tab
    @Binding var isPresented: Bool

    @Environment(SidebarCellEnvironment.self) private var env
    @Environment(WebPagePool.self) private var pagePool

    @State private var domainTimeToday: TimeInterval?

    private enum Layout {
        static let popoverWidth: CGFloat = 320
        static let padding: CGFloat = 16
        static let sectionSpacing: CGFloat = 16
        static let itemSpacing: CGFloat = 8
        static let labelWidth: CGFloat = 90
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.sectionSpacing) {
                header
                Divider()
                tabInfoSection
                Divider()
                pagesSection
                runtimeSection
            }
            .padding(Layout.padding)
        }
        .frame(width: Layout.popoverWidth)
        .frame(maxHeight: 500)
        .task {
            guard let domain = tab.activePage.url.registrableDomain else { return }
            domainTimeToday = await env.browserState.domainTimeTracker.timeSpent(on: domain)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            // Favicon
            if let faviconData = tab.activePage.faviconData,
               let nsImage = NSImage(data: faviconData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tab.displayTitle)
                    .font(.headline)
                    .lineLimit(2)

                if let host = tab.activePage.url.host() {
                    Text(host)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
    }

    // MARK: - Tab Info Section

    private var tabInfoSection: some View {
        VStack(alignment: .leading, spacing: Layout.itemSpacing) {
            SectionHeader(title: "Tab")

            if let customName = tab.customName, !customName.isEmpty {
                InfoRow(label: "Custom Name", value: customName)
            }

            InfoRow(label: "Status", value: statusDescription)

            if let group = tab.group {
                InfoRow(label: "Group", value: group.name, color: group.color)
            }

            if let space = tab.space {
                InfoRow(label: "Space", value: space.name)
            }

            if tab.pages.count > 1 {
                InfoRow(label: "Pages", value: "\(tab.pages.count) pages (split view)")
            }

            InfoRow(label: "Created", value: formatDate(tab.createdAt))
            InfoRow(
                label: "Last Accessed",
                value: tab.lastAccessed.map(formatRelativeDate) ?? "Never",
            )

            // Time spent from history tracking
            if let timeSpent = activeTimeSpent, timeSpent >= 60 {
                InfoRow(
                    label: "Time Spent On This Page",
                    value: timeSpent.formattedDuration,
                    systemImage: "stopwatch",
                    imageColor: .secondary,
                )
            }

            // Domain time today (aggregated across all visits to this domain)
            if env.browserState.settings.showTimeSpentInTooltips, let domainTime = domainTimeToday, domainTime >= 60 {
                InfoRow(
                    label: "Time On This Domain Today",
                    value: domainTime.formattedDuration,
                    systemImage: "clock.arrow.2.circlepath",
                    imageColor: timeToday24h ? .orange : .secondary,
                )
            }
        }
    }

    /// Gets the time spent for the active history entry of this tab.
    private var activeTimeSpent: TimeInterval? {
        env.historyManager.activeEntry(for: tab.id)?.timeSpent
    }

    /// Whether the domain time exceeds 1 hour (to highlight in orange).
    private var timeToday24h: Bool {
        guard let time = domainTimeToday else { return false }
        return time >= 3_600
    }

    private var statusDescription: String {
        var parts: [String] = []
        if tab.isPinned { parts.append("Pinned") }
        if tab.isUnread { parts.append("Unread") }
        if tab.isReferenceTab { parts.append("Reference") }
        if tab.status == .liveFavorite { parts.append("Live Favorite") }
        return parts.isEmpty ? "Regular" : parts.joined(separator: ", ")
    }

    // MARK: - Pages Section

    @ViewBuilder
    private var pagesSection: some View {
        if tab.pages.count == 1 {
            // Single page - flat display
            singlePageInfo(tab.activePage)
        } else {
            // Multi-page - nested display
            VStack(alignment: .leading, spacing: Layout.itemSpacing) {
                SectionHeader(title: "Pages")

                ForEach(tab.sortedPages) { page in
                    multiPageInfo(page)
                }
            }
        }
    }

    private func singlePageInfo(_ page: TabPage) -> some View {
        VStack(alignment: .leading, spacing: Layout.itemSpacing) {
            SectionHeader(title: "Page")

            InfoRow(label: "URL", value: page.url.absoluteString, isURL: true)
            InfoRow(label: "Title", value: page.title.isEmpty ? "(no title)" : page.title)
            InfoRow(
                label: "Security",
                value: page.isSecure ? "Secure (HTTPS)" : "Not Secure",
                systemImage: page.isSecure ? "lock.fill" : "lock.open.fill",
                imageColor: page.isSecure ? .green : .orange,
            )
            InfoRow(label: "Created", value: formatDate(page.createdAt))

            if page.openerTabPageID != nil {
                InfoRow(label: "Opened By", value: "Popup from another tab")
            }
        }
    }

    private func multiPageInfo(_ page: TabPage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Page position header
            HStack {
                Text(positionLabel(for: page))
                    .font(.subheadline.weight(.medium))
                Spacer()
                if page.isSecure {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            // URL
            Text(page.url.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .textSelection(.enabled)

            // Title
            if !page.title.isEmpty {
                Text(page.title)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func positionLabel(for page: TabPage) -> String {
        switch page.position {
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        case .single, nil: "Primary"
        }
    }

    // MARK: - Runtime Section

    @ViewBuilder
    private var runtimeSection: some View {
        // Collect runtime info from all pages
        let runtimeInfo = collectRuntimeInfo()

        if !runtimeInfo.isEmpty {
            Divider()

            VStack(alignment: .leading, spacing: Layout.itemSpacing) {
                SectionHeader(title: "Runtime")

                ForEach(runtimeInfo, id: \.label) { info in
                    InfoRow(
                        label: info.label,
                        value: info.value,
                        systemImage: info.systemImage,
                        imageColor: info.imageColor,
                    )
                }
            }
        }
    }

    private struct RuntimeInfoItem {
        let label: String
        let value: String
        var systemImage: String?
        var imageColor: Color?
    }

    private func collectRuntimeInfo() -> [RuntimeInfoItem] {
        var items: [RuntimeInfoItem] = []

        // Check if any page has an active WebPage
        for page in tab.pages {
            guard let webPage = pagePool.existingPage(for: page) else { continue }

            // Loading state
            if webPage.isLoading {
                let progress = Int(webPage.estimatedProgress * 100)
                items.append(RuntimeInfoItem(
                    label: "Loading",
                    value: "\(progress)%",
                    systemImage: "arrow.trianglehead.2.clockwise.rotate.90",
                    imageColor: .blue,
                ))
            }

            // Audio state
            if webPage.isPlayingAudio {
                items.append(RuntimeInfoItem(
                    label: "Audio",
                    value: webPage.isAudioMuted ? "Playing (Muted)" : "Playing",
                    systemImage: webPage.isAudioMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    imageColor: webPage.isAudioMuted ? .secondary : .blue,
                ))
            }

            // Camera/Microphone
            if webPage.isCameraActive {
                items.append(RuntimeInfoItem(
                    label: "Camera",
                    value: "Active",
                    systemImage: "video.fill",
                    imageColor: .green,
                ))
            }
            if webPage.isMicrophoneActive {
                items.append(RuntimeInfoItem(
                    label: "Microphone",
                    value: "Active",
                    systemImage: "mic.fill",
                    imageColor: .green,
                ))
            }

            // Navigation
            if webPage.canGoBack || webPage.canGoForward {
                var nav: [String] = []
                if webPage.canGoBack { nav.append("Back") }
                if webPage.canGoForward { nav.append("Forward") }
                items.append(RuntimeInfoItem(
                    label: "Navigation",
                    value: nav.joined(separator: ", "),
                ))
            }

            // Security details
            if !webPage.hasOnlySecureContent {
                items.append(RuntimeInfoItem(
                    label: "Mixed Content",
                    value: "Page contains insecure resources",
                    systemImage: "exclamationmark.triangle.fill",
                    imageColor: .orange,
                ))
            }

            // Process state
            if webPage.isUnresponsive {
                items.append(RuntimeInfoItem(
                    label: "Process",
                    value: "Unresponsive",
                    systemImage: "exclamationmark.circle.fill",
                    imageColor: .red,
                ))
            }

            // Only show info from first active WebPage to avoid duplicates
            break
        }

        return items
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private func formatRelativeDate(_ date: Date) -> String {
        date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }
}

// MARK: - Supporting Views

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var color: Color?
    var systemImage: String?
    var imageColor: Color?
    var isURL: Bool = false

    private enum Layout {
        static let labelWidth: CGFloat = 90
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: Layout.labelWidth, alignment: .trailing)

            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(imageColor ?? .secondary)
            }

            if let color {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
            }

            if isURL {
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            } else {
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Preview

#Preview(traits: .modifier(RefraxPreviewModifier())) {
    TabInfoPopover(
        tab: Tab(space: nil, url: URL.staticRequired("https://apple.com"), title: "Apple"),
        isPresented: .constant(true),
    )
    .padding()
}
