import SwiftUI

/// Inspector panel for displaying detailed information about a history entry.
///
/// Shows when an entry is selected in the history table/list.
///
/// ## Visual Layout
///
/// ```
/// ┌────────────────────────┐
/// │ Page Title           ✕ │
/// │ example.com            │
/// ├────────────────────────┤
/// │ DETAILS                │
/// │ Visited   Jan 15, 2026 │
/// │ Closed    Jan 15, 2026 │
/// │ Duration  15m 32s      │
/// ├────────────────────────┤
/// │ NAVIGATION             │
/// │ From      Parent Page  │
/// │ Opened    3 pages      │
/// ├────────────────────────┤
/// │ DOMAIN                 │
/// │ Time Today 1h 23m      │
/// │ Space     Personal     │
/// ├────────────────────────┤
/// │ [Open] [Copy URL]      │
/// └────────────────────────┘
/// ```
struct HistoryInspectorView: View {
    let entry: HistoryEntry?
    let onOpen: (HistoryEntry) -> Void
    let onDelete: (HistoryEntry) -> Void
    var domainTimeToday: TimeInterval?
    var spaceName: String?
    var spaceColor: Color?

    var body: some View {
        if let entry {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection(entry)

                    InspectorDivider()

                    detailsSection(entry)

                    InspectorDivider()

                    navigationSection(entry)

                    if domainTimeToday != nil || spaceName != nil {
                        InspectorDivider()
                        contextSection(entry)
                    }
                }
                .padding(.vertical, 12)
            }
            .safeAreaInset(edge: .bottom) {
                actionBar(entry)
                    .background(.bar)
            }
        } else {
            InspectorEmptyState(
                systemImage: "clock",
                title: "No Selection",
                message: "Select a history entry to see details",
            )
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func headerSection(_ entry: HistoryEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                faviconView(entry)
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title ?? "Untitled")
                        .font(.headline)
                        .lineLimit(2)

                    Text(entry.domain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if entry.failedToLoad {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .help(failedStatusDescription(for: entry))
                }
            }
            .padding(.horizontal, 16)

            if entry.failedToLoad {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                    Text(failedStatusDescription(for: entry))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func faviconView(_ entry: HistoryEntry) -> some View {
        if entry.failedToLoad {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.red.opacity(0.1))
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            }
        } else if let faviconURL = entry.faviconURL {
            AsyncImage(url: faviconURL) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } placeholder: {
                LetterFallbackView(url: entry.url)
            }
        } else {
            LetterFallbackView(url: entry.url)
        }
    }

    // MARK: - Details Section

    @ViewBuilder
    private func detailsSection(_ entry: HistoryEntry) -> some View {
        InspectorSection(title: "Details") {
            VStack(alignment: .leading, spacing: 6) {
                InspectorDateRow(label: "Visited", date: entry.visitedAt)

                if let closedAt = entry.closedAt {
                    InspectorDateRow(label: "Closed", date: closedAt)
                } else if !entry.failedToLoad {
                    InspectorRow(label: "Status") {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                            Text("Still Open")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                InspectorDurationRow(label: "Duration", duration: entry.timeSpent)

                InspectorRow(label: "URL") {
                    Text(entry.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(3)
                }
            }
        }
    }

    // MARK: - Navigation Section

    @ViewBuilder
    private func navigationSection(_ entry: HistoryEntry) -> some View {
        let hasParent = entry.parent != nil
        let hasChildren = !entry.children.isEmpty

        if hasParent || hasChildren {
            InspectorSection(title: "Navigation") {
                VStack(alignment: .leading, spacing: 6) {
                    if let parent = entry.parent {
                        InspectorRow(label: "From") {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(parent.title ?? "Untitled")
                                    .lineLimit(1)
                                Text(parent.domain)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if !entry.children.isEmpty {
                        InspectorRow(label: "Opened") {
                            Text("\(entry.children.count) page\(entry.children.count == 1 ? "" : "s")")
                        }
                    }
                }
            }
        } else {
            InspectorSection(title: "Navigation") {
                Text("Direct navigation")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Context Section

    @ViewBuilder
    private func contextSection(_: HistoryEntry) -> some View {
        InspectorSection(title: "Context") {
            VStack(alignment: .leading, spacing: 6) {
                if let domainTime = domainTimeToday {
                    InspectorRow(label: "Domain Today") {
                        Text(formatDomainTime(domainTime))
                    }
                }

                if let spaceName, let spaceColor {
                    InspectorRow(label: "Space") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(spaceColor)
                                .frame(width: 8, height: 8)
                            Text(spaceName)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Action Bar

    @ViewBuilder
    private func actionBar(_ entry: HistoryEntry) -> some View {
        HStack(spacing: 8) {
            Button {
                onOpen(entry)
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.borderedProminent)

            Button {
                copyURL(entry)
            } label: {
                Label("Copy URL", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button(role: .destructive) {
                onDelete(entry)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Helpers

    private func copyURL(_ entry: HistoryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.url.absoluteString, forType: .string)
    }

    private func failedStatusDescription(for entry: HistoryEntry) -> String {
        guard let code = entry.httpStatusCode else {
            return "Failed to load"
        }
        switch code {
        case 0: return "Network unreachable"
        case 404: return "Page not found"
        case 408: return "Connection timed out"
        case 495: return "SSL certificate error"
        case 503: return "Service unavailable"
        default: return "Error \(code)"
        }
    }

    private func formatDomainTime(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "< 1 min"
        } else if seconds < 3_600 {
            return "\(Int(seconds / 60)) min"
        } else {
            let hours = Int(seconds / 3_600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3_600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
}

// MARK: - Preview

#Preview("With Entry") {
    HistoryInspectorView(
        entry: HistoryEntry(
            url: URL.staticRequired("https://developer.apple.com/documentation/swiftui"),
            title: "SwiftUI Documentation",
        ),
        onOpen: { _ in },
        onDelete: { _ in },
        domainTimeToday: 3_723,
        spaceName: "Work",
        spaceColor: .blue,
    )
    .frame(width: 280, height: 500)
}

#Preview("Empty") {
    HistoryInspectorView(
        entry: nil,
        onOpen: { _ in },
        onDelete: { _ in },
    )
    .frame(width: 280, height: 500)
}
