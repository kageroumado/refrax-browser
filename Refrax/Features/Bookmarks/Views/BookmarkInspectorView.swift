import SwiftUI

/// Inspector panel for displaying detailed information about a bookmark.
///
/// Shows when a bookmark is selected in the grid/table view.
///
/// ## Visual Layout
///
/// ```
/// ┌────────────────────────┐
/// │ [Favicon]              │
/// │ Bookmark Title       ✕ │
/// │ example.com            │
/// ├────────────────────────┤
/// │ DETAILS                │
/// │ URL       https://...  │
/// │ Created   Jan 15, 2026 │
/// │ Modified  Jan 20, 2026 │
/// ├────────────────────────┤
/// │ ACTIVITY               │
/// │ Visited   Jan 25, 2026 │
/// │ Visits    42           │
/// ├────────────────────────┤
/// │ ORGANIZATION           │
/// │ Folder    Programming  │
/// │ Tags      swift, ios   │
/// │ Favorite  ☆            │
/// ├────────────────────────┤
/// │ OFFLINE                │
/// │ Status    Available    │
/// │ Size      1.2 MB       │
/// │ Saved     Jan 20, 2026 │
/// ├────────────────────────┤
/// │ [Open] [Edit] [Delete] │
/// └────────────────────────┘
/// ```
struct BookmarkInspectorView: View {
    let bookmark: Bookmark?
    let onOpen: (Bookmark) -> Void
    let onEdit: (Bookmark) -> Void
    let onDelete: (Bookmark) -> Void
    let onToggleFavorite: (Bookmark) -> Void
    let onSaveOffline: (Bookmark) -> Void
    let onRemoveOffline: (Bookmark) -> Void
    var folderPath: String?

    var body: some View {
        if let bookmark {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection(bookmark)

                    InspectorDivider()

                    detailsSection(bookmark)

                    InspectorDivider()

                    activitySection(bookmark)

                    InspectorDivider()

                    organizationSection(bookmark)

                    if bookmark.offlineStatus != .notSaved {
                        InspectorDivider()
                        offlineSection(bookmark)
                    }
                }
                .padding(.vertical, 12)
            }
            .safeAreaInset(edge: .bottom) {
                actionBar(bookmark)
                    .background(.bar)
            }
        } else {
            InspectorEmptyState(
                systemImage: "bookmark",
                title: "No Selection",
                message: "Select a bookmark to see details",
            )
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func headerSection(_ bookmark: Bookmark) -> some View {
        VStack(alignment: .center, spacing: 12) {
            // Large favicon
            faviconView(bookmark)
                .frame(width: 64, height: 64)

            VStack(spacing: 4) {
                Text(bookmark.title)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(bookmark.domain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Favorite indicator
            if bookmark.isFavorite {
                Label("Favorite", systemImage: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func faviconView(_ bookmark: Bookmark) -> some View {
        if let customIcon = bookmark.customIcon {
            customIcon.view(size: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            FaviconView(
                data: bookmark.largeFaviconData ?? bookmark.faviconData,
                url: bookmark.url,
                size: 64,
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
        }
    }

    // MARK: - Details Section

    @ViewBuilder
    private func detailsSection(_ bookmark: Bookmark) -> some View {
        InspectorSection(title: "Details") {
            VStack(alignment: .leading, spacing: 6) {
                InspectorRow(label: "URL") {
                    Text(bookmark.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(3)
                }

                InspectorDateRow(label: "Created", date: bookmark.createdAt)

                InspectorDateRow(label: "Modified", date: bookmark.lastModified)
            }
        }
    }

    // MARK: - Activity Section

    @ViewBuilder
    private func activitySection(_ bookmark: Bookmark) -> some View {
        InspectorSection(title: "Activity") {
            VStack(alignment: .leading, spacing: 6) {
                if let lastVisited = bookmark.lastVisited {
                    InspectorDateRow(label: "Last Visit", date: lastVisited)
                } else {
                    InspectorValueRow(label: "Last Visit", value: "Never")
                }

                InspectorValueRow(label: "Visits", value: "\(bookmark.visitCount)")
            }
        }
    }

    // MARK: - Organization Section

    @ViewBuilder
    private func organizationSection(_ bookmark: Bookmark) -> some View {
        InspectorSection(title: "Organization") {
            VStack(alignment: .leading, spacing: 6) {
                if let folderPath {
                    InspectorValueRow(label: "Folder", value: folderPath)
                } else if bookmark.folder != nil {
                    InspectorValueRow(label: "Folder", value: bookmark.folder?.name ?? "Unknown")
                } else {
                    InspectorValueRow(label: "Folder", value: "None")
                }

                if !bookmark.tags.isEmpty {
                    InspectorTagsRow(label: "Tags", tags: bookmark.tags)
                } else {
                    InspectorValueRow(label: "Tags", value: "None")
                }

                // Favorite toggle
                HStack {
                    Text("Favorite")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .leading)

                    Spacer()

                    Button {
                        onToggleFavorite(bookmark)
                    } label: {
                        Image(systemName: bookmark.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(bookmark.isFavorite ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Offline Section

    @ViewBuilder
    private func offlineSection(_ bookmark: Bookmark) -> some View {
        InspectorSection(title: "Offline") {
            VStack(alignment: .leading, spacing: 6) {
                InspectorRow(label: "Status") {
                    HStack(spacing: 4) {
                        statusIndicator(for: bookmark.offlineStatus)
                        Text(statusText(for: bookmark.offlineStatus))
                    }
                }

                if let fileSize = bookmark.offlineFileSize {
                    InspectorValueRow(
                        label: "Size",
                        value: ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file),
                    )
                }

                if let savedAt = bookmark.offlineSavedAt {
                    InspectorDateRow(label: "Saved", date: savedAt)
                }

                // Remove offline button
                if bookmark.isOfflineAvailable {
                    HStack {
                        Spacer()
                        Button("Remove Offline Copy", role: .destructive) {
                            onRemoveOffline(bookmark)
                        }
                        .font(.caption)
                        Spacer()
                    }
                    .padding(.top, 4)
                }
            }
        }
    }

    @ViewBuilder
    private func statusIndicator(for status: OfflineStatus) -> some View {
        switch status {
        case .notSaved, .failed:
            Circle()
                .fill(.gray)
                .frame(width: 6, height: 6)
        case .downloadingHTML, .downloadingReader:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 12, height: 12)
        case .availableHTML, .availableReader:
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)
        }
    }

    private func statusText(for status: OfflineStatus) -> String {
        switch status {
        case .notSaved: "Not Saved"
        case .downloadingHTML, .downloadingReader: "Downloading..."
        case .availableHTML: "Available (HTML)"
        case .availableReader: "Available (Reader)"
        case .failed: "Failed"
        }
    }

    // MARK: - Action Bar

    @ViewBuilder
    private func actionBar(_ bookmark: Bookmark) -> some View {
        HStack(spacing: 8) {
            Button {
                onOpen(bookmark)
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.borderedProminent)

            Button {
                onEdit(bookmark)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .buttonStyle(.bordered)

            Spacer()

            // Save offline or show status
            if !bookmark.isOfflineAvailable, !bookmark.isDownloadingOffline {
                Button {
                    onSaveOffline(bookmark)
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .help("Save Offline")
            }

            Button(role: .destructive) {
                onDelete(bookmark)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Preview

#Preview("With Bookmark") {
    BookmarkInspectorView(
        bookmark: Bookmark(
            url: URL.staticRequired("https://developer.apple.com/documentation/swiftui"),
            title: "SwiftUI Documentation",
        ),
        onOpen: { _ in },
        onEdit: { _ in },
        onDelete: { _ in },
        onToggleFavorite: { _ in },
        onSaveOffline: { _ in },
        onRemoveOffline: { _ in },
        folderPath: "Programming > Documentation",
    )
    .frame(width: 280, height: 600)
}

#Preview("Empty") {
    BookmarkInspectorView(
        bookmark: nil,
        onOpen: { _ in },
        onEdit: { _ in },
        onDelete: { _ in },
        onToggleFavorite: { _ in },
        onSaveOffline: { _ in },
        onRemoveOffline: { _ in },
    )
    .frame(width: 280, height: 600)
}
