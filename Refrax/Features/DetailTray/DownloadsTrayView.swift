import SwiftUI

// MARK: - Downloads Tray View

/// Downloads panel for the detail tray.
///
/// Displays active and completed downloads with Apple Maps-style design:
/// - Large "Downloads" title with close button
/// - Active downloads section with progress
/// - Completed downloads grouped by date
/// - Bottom toolbar with Open Folder and Select mode
struct DownloadsTrayView: View {
    @Environment(WindowState.self) private var windowState
    @Environment(DownloadManager.self) private var downloadManager

    @State private var isSelectionMode = false
    @State private var selectedDownloads: Set<UUID> = []
    @State private var scrollOffset: CGFloat = 0
    @State private var initialScrollOffset: CGFloat?

    private enum Constants {
        static let rowPadding: CGFloat = 12
        static let iconSize: CGFloat = 32
        static let progressHeight: CGFloat = 4
    }

    var body: some View {
        Group {
            if downloadManager.downloads.isEmpty {
                emptyState
            } else {
                downloadsList
            }
        }
        .safeAreaBar(edge: .top) { header }
        .safeAreaBar(edge: .bottom) { footer }
    }

    // MARK: - Header

    private var header: some View {
        DetailTrayHeader(
            title: isSelectionMode ? "Select Downloads" : "Downloads",
            currentMode: .downloads,
            onExpand: isSelectionMode ? nil : { openFullDownloadsView() },
            onClose: {
                if isSelectionMode {
                    isSelectionMode = false
                    selectedDownloads.removeAll()
                } else {
                    windowState.hideDetailTray()
                }
            },
        )
    }

    private func openFullDownloadsView() {
        NSApp.typedDelegate.downloadsWindowController.showWindow()
        windowState.hideDetailTray()
    }

    // MARK: - Empty State

    private var emptyState: some View {
        DetailTrayEmptyState(
            icon: "arrow.down.circle",
            title: "No Downloads",
            message: "Files you download will appear here",
        )
    }

    // MARK: - Downloads List

    private var downloadsList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                // Active downloads
                if !activeDownloads.isEmpty {
                    Section {
                        ForEach(activeDownloads) { download in
                            downloadRow(download)
                                .transition(.asymmetric(
                                    insertion: .opacity,
                                    removal: .slide.combined(with: .opacity),
                                ))
                        }
                    } header: {
                        DetailTraySectionHeader(title: "Active", scrollOffset: scrollOffset)
                    }
                }

                // Completed downloads grouped by date
                ForEach(completedDownloadGroups, id: \.title) { group in
                    Section {
                        ForEach(group.downloads) { download in
                            downloadRow(download)
                                .transition(.asymmetric(
                                    insertion: .opacity,
                                    removal: .slide.combined(with: .opacity),
                                ))
                        }
                    } header: {
                        DetailTraySectionHeader(title: group.title, scrollOffset: scrollOffset)
                    }
                }
            }
            .padding(.bottom, 8)
            .animation(.easeInOut(duration: 0.25), value: downloadManager.downloads.map(\.id))
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y
        } action: { _, newOffset in
            // Capture initial offset on first callback, then track delta from it
            if initialScrollOffset == nil, newOffset != 0 {
                initialScrollOffset = newOffset
            }
            scrollOffset = newOffset - (initialScrollOffset ?? newOffset)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    // MARK: - Download Row

    @ViewBuilder
    private func downloadRow(_ download: Download) -> some View {
        Button {
            if isSelectionMode {
                toggleSelection(download.id)
            } else if download.state == .completed {
                downloadManager.openFile(download.id)
            }
        } label: {
            HStack(spacing: 12) {
                if isSelectionMode {
                    selectionIndicator(isSelected: selectedDownloads.contains(download.id))
                }

                fileIcon(for: download)

                VStack(alignment: .leading, spacing: 2) {
                    Text(download.destinationFilename)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)

                    if download.state.isActive {
                        activeDownloadStatus(download)
                    } else {
                        completedDownloadStatus(download)
                    }
                }

                Spacer(minLength: 0)

                if !isSelectionMode {
                    downloadActions(download)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, Constants.rowPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            downloadContextMenu(download)
        }
    }

    // MARK: - Selection Indicator

    private func selectionIndicator(isSelected: Bool) -> some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(.blue)
                    .frame(width: 22, height: 22)

                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .stroke(.secondary.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
            }
        }
    }

    // MARK: - File Icon

    private func fileIcon(for download: Download) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(download.downloadType.isBitTorrent ? AnyShapeStyle(.orange.opacity(0.15)) : AnyShapeStyle(.quaternary))
                .frame(width: Constants.iconSize, height: Constants.iconSize)

            if download.downloadType.isBitTorrent {
                // BitTorrent icon
                Image(systemName: download.downloadType.iconName)
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
            } else if let contentType = download.contentType {
                Image(nsImage: NSWorkspace.shared.icon(for: contentType))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: Constants.iconSize - 4, height: Constants.iconSize - 4)
            } else {
                Image(systemName: "doc")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Active Download Status

    private func activeDownloadStatus(_ download: Download) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(download.state.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let progress = download.progress {
                    Text("(\(Int(progress * 100))%)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if download.bytesPerSecond > 0 {
                    Text(formatSpeed(download.bytesPerSecond))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                // Show peer count for BitTorrent downloads
                if download.downloadType.isBitTorrent, let peers = download.btPeers, peers > 0 {
                    Text("• \(peers) peer\(peers == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            // Progress bar (orange for BitTorrent, blue for HTTP)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.quaternary)

                    if let progress = download.progress {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(download.downloadType.isBitTorrent ? .orange : .blue)
                            .frame(width: geometry.size.width * progress)
                    }
                }
            }
            .frame(height: Constants.progressHeight)
        }
    }

    // MARK: - Completed Download Status

    private func completedDownloadStatus(_ download: Download) -> some View {
        HStack(spacing: 4) {
            if download.state == .failed {
                Text(download.errorMessage ?? "Failed")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text(formatFileSize(download.bytesReceived))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let completedAt = download.completedAt {
                    Text(formatTime(completedAt))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Download Actions

    @ViewBuilder
    private func downloadActions(_ download: Download) -> some View {
        switch download.state {
        case .downloading:
            Button {
                Task { await downloadManager.pause(download.id) }
            } label: {
                Image(systemName: "pause.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

        case .paused:
            Button {
                Task { try? await downloadManager.resume(download.id) }
            } label: {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.blue)
            }
            .buttonStyle(.plain)

        case .failed:
            Button {
                Task { try? await downloadManager.retry(download.id) }
            } label: {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)

        case .completed:
            Button {
                downloadManager.revealInFinder(download.id)
            } label: {
                Image(systemName: "folder.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Show in Finder")

        case .pending:
            ProgressView()
                .scaleEffect(0.6)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func downloadContextMenu(_ download: Download) -> some View {
        if download.state == .completed {
            Button("Open") {
                downloadManager.openFile(download.id)
            }

            Button("Show in Finder") {
                downloadManager.revealInFinder(download.id)
            }

            Divider()
        }

        if download.state == .downloading {
            Button("Pause") {
                Task { await downloadManager.pause(download.id) }
            }
        }

        if download.canResume {
            Button("Resume") {
                Task { try? await downloadManager.resume(download.id) }
            }
        }

        if download.canRetry {
            Button("Retry") {
                Task { try? await downloadManager.retry(download.id) }
            }
        }

        if download.state.isActive {
            Button("Cancel", role: .destructive) {
                downloadManager.cancel(download.id)
            }
        }

        Divider()

        Button("Remove from List", role: .destructive) {
            downloadManager.remove(download.id)
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        if isSelectionMode {
            DetailTraySelectionFooter(
                deleteAction: deleteSelectedDownloads,
                doneAction: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSelectionMode = false
                    }
                    selectedDownloads.removeAll()
                },
                hasSelection: !selectedDownloads.isEmpty,
            )
            .transition(.opacity)
        } else {
            DetailTrayFooter {
                DetailTrayToolbar {
                    DetailTrayToolbarButton(
                        icon: "folder",
                        action: { downloadManager.openDownloadsFolder() },
                        help: "Open Downloads Folder",
                    )

                    DetailTrayToolbarButton(
                        icon: "circle.grid.2x2.topleft.checkmark.filled",
                        action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSelectionMode = true
                            }
                        },
                        isDisabled: downloadManager.downloads.isEmpty,
                        help: "Select Downloads",
                    )
                }
            }
            .transition(.opacity)
        }
    }

    // MARK: - Helpers

    private var activeDownloads: [Download] {
        downloadManager.downloads.filter { $0.state.isActive || $0.state == .paused }
    }

    private var completedDownloadGroups: [DownloadGroup] {
        let completed = downloadManager.downloads.filter {
            $0.state == .completed || $0.state == .failed
        }

        let calendar = Calendar.current
        let now = Date()
        var groups: [String: [Download]] = [:]

        for download in completed {
            let date = download.completedAt ?? download.modifiedAt
            let key = dateGroupKey(for: date, calendar: calendar, now: now)
            groups[key, default: []].append(download)
        }

        let order = ["Today", "Yesterday", "This Week", "This Month", "Older"]
        return order.compactMap { title in
            groups[title].map { DownloadGroup(title: title, downloads: $0) }
        }
    }

    private func dateGroupKey(for date: Date, calendar: Calendar, now: Date) -> String {
        if calendar.isDateInToday(date) {
            return "Today"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday"
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            return "This Week"
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            return "This Month"
        }
        return "Older"
    }

    private func toggleSelection(_ id: UUID) {
        if selectedDownloads.contains(id) {
            selectedDownloads.remove(id)
        } else {
            selectedDownloads.insert(id)
        }
    }

    private func deleteSelectedDownloads() {
        for id in selectedDownloads {
            downloadManager.remove(id)
        }
        selectedDownloads.removeAll()
        isSelectionMode = false
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        "\(Int64(bytesPerSecond).formatted(.byteCount(style: .file)))/s"
    }

    private func formatTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Download Group

private struct DownloadGroup {
    let title: String
    let downloads: [Download]
}
