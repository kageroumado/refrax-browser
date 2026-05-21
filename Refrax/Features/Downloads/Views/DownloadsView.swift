import SwiftUI

/// Downloads window view displaying all downloads with enhanced functionality.
///
/// Provides a full-featured downloads manager interface with search/filter,
/// date-grouped sections, and per-download actions. Enhanced columns and
/// multi-select are planned for Phase 3.2.
struct DownloadsView: View {
    @Environment(DownloadManager.self) private var downloadManager

    @State private var searchText = ""

    private enum Constants {
        static let rowPadding: CGFloat = 12
        static let iconSize: CGFloat = 32
        static let progressHeight: CGFloat = 4
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            Divider()

            // Content
            if downloadManager.downloads.isEmpty {
                emptyState
            } else {
                downloadsList
            }
        }
        .frame(minWidth: 500, minHeight: 300)
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            // Search field (Phase 3.2 enhancement)
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search downloads...", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 300)

            Spacer()

            // Actions
            Button {
                downloadManager.openDownloadsFolder()
            } label: {
                Label("Open Folder", systemImage: "folder")
            }
            .buttonStyle(.borderless)

            Button {
                clearCompleted()
            } label: {
                Label("Clear Completed", systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .disabled(!hasCompletedDownloads)
        }
        .padding(12)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No Downloads")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Files you download will appear here")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Downloads List

    private var downloadsList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
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
                        sectionHeader("Active")
                    }
                }

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
                        sectionHeader(group.title)
                    }
                }
            }
            .padding(.bottom, 8)
            .animation(.easeInOut(duration: 0.25), value: downloadManager.downloads.map(\.id))
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.background)
    }

    // MARK: - Download Row

    private func downloadRow(_ download: Download) -> some View {
        HStack(spacing: 12) {
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

            downloadActions(download)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, Constants.rowPadding)
        .contentShape(Rectangle())
        .onTapGesture {
            if download.state == .completed {
                downloadManager.openFile(download.id)
            }
        }
        .contextMenu {
            downloadContextMenu(download)
        }
    }

    // MARK: - File Icon

    private func fileIcon(for download: Download) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .frame(width: Constants.iconSize, height: Constants.iconSize)

            if let contentType = download.contentType {
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
            HStack(spacing: 8) {
                // Size info (received of total)
                sizeInfo(download)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                // Speed
                if download.bytesPerSecond > 0 {
                    Text(formatSpeed(download.bytesPerSecond))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Time remaining
                if let remaining = download.estimatedTimeRemaining {
                    Text(formatTimeRemaining(remaining))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.quaternary)

                    if let progress = download.progress {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.blue)
                            .frame(width: geometry.size.width * progress)
                    }
                }
            }
            .frame(height: Constants.progressHeight)
        }
    }

    @ViewBuilder
    private func sizeInfo(_ download: Download) -> some View {
        if let total = download.totalBytes {
            Text("\(formatFileSize(download.bytesReceived)) of \(formatFileSize(total))")
        } else {
            Text(formatFileSize(download.bytesReceived))
        }
    }

    // MARK: - Completed Download Status

    private func completedDownloadStatus(_ download: Download) -> some View {
        HStack(spacing: 8) {
            if download.state == .failed {
                // Status indicator for failed downloads
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                Text(download.errorMessage ?? "Failed")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                // Status indicator for completed downloads
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)

                // Show total size (or received if total unknown)
                Text(formatFileSize(download.totalBytes ?? download.bytesReceived))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

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

    // MARK: - Computed Properties

    private var filteredDownloads: [Download] {
        guard !searchText.isEmpty else { return downloadManager.downloads }
        return downloadManager.downloads.filter {
            $0.destinationFilename.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var activeDownloads: [Download] {
        filteredDownloads.filter { $0.state.isActive || $0.state == .paused }
    }

    private var hasCompletedDownloads: Bool {
        downloadManager.downloads.contains { $0.state == .completed }
    }

    private var completedDownloadGroups: [DownloadGroup] {
        let completed = filteredDownloads.filter {
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
            guard let downloads = groups[title], !downloads.isEmpty else { return nil }
            return DownloadGroup(title: title, downloads: downloads)
        }
    }

    private func dateGroupKey(for date: Date, calendar: Calendar, now: Date) -> String {
        if calendar.isDateInToday(date) {
            "Today"
        } else if calendar.isDateInYesterday(date) {
            "Yesterday"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            "This Week"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            "This Month"
        } else {
            "Older"
        }
    }

    // MARK: - Actions

    private func clearCompleted() {
        for download in downloadManager.downloads where download.state == .completed {
            downloadManager.remove(download.id)
        }
    }

    // MARK: - Formatting

    private func formatFileSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        "\(ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file))/s"
    }

    private func formatTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "< 1 min left"
        } else if seconds < 3_600 {
            let minutes = Int(seconds / 60)
            return "~\(minutes) min left"
        } else {
            let hours = Int(seconds / 3_600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3_600)) / 60)
            if minutes > 0 {
                return "~\(hours)h \(minutes)m left"
            } else {
                return "~\(hours)h left"
            }
        }
    }
}

// MARK: - Download Group

private struct DownloadGroup {
    let title: String
    let downloads: [Download]
}
