import SwiftData
import SwiftUI

// MARK: - Snapshot Browser View

/// Root view for browsing tab snapshots in the detail tray.
///
/// Displays snapshots organized by date as expandable folders. Users can:
/// - Browse snapshots grouped by date (Today, Yesterday, etc.)
/// - Expand a date to see individual snapshots with their tabs
/// - Restore a snapshot (replaces current tabs) or add tabs from it
/// - Click individual tab items to navigate directly
struct SnapshotBrowserView: View {
    @Environment(WindowState.self) private var windowState
    @Environment(TabManager.self) private var tabManager
    @Environment(\.modelContext) private var modelContext

    @State private var selectedDate: DateComponents?
    @State private var scrollOffset: CGFloat = 0
    @State private var initialScrollOffset: CGFloat?
    @State private var showRestoreConfirmation = false
    @State private var snapshotToRestore: TabSnapshot?

    @Query(
        sort: \TabSnapshot.createdAt,
        order: .reverse,
    )
    private var allSnapshots: [TabSnapshot]

    private enum Constants {
        static let maxSnapshots = 500
    }

    /// The tabs in the current space.
    private var currentTabs: [Tab] {
        windowState.activeSpace?.tabs ?? []
    }

    var body: some View {
        Group {
            if allSnapshots.isEmpty {
                emptyState
            } else if let selectedDate {
                snapshotDetailView(for: selectedDate)
            } else {
                folderListView
            }
        }
        .safeAreaBar(edge: .top) { header }
        .confirmationDialog(
            "Restore Snapshot?",
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible,
        ) {
            Button("Restore", role: .destructive) {
                if let snapshot = snapshotToRestore {
                    restoreSnapshot(snapshot)
                }
            }
            Button("Cancel", role: .cancel) {
                snapshotToRestore = nil
            }
        } message: {
            if let snapshot = snapshotToRestore {
                let currentCount = currentTabs.count
                Text("This will close your current \(currentCount) tabs and restore \(snapshot.tabCount) tabs from the snapshot.\n\nCurrent tabs will be recoverable from \"Recently Closed\" if needed.")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        DetailTrayHeader(
            title: selectedDate != nil ? formatDateForHeader(selectedDate!) : "Tab Snapshots",
            currentMode: .tabSnapshots,
            onBack: selectedDate != nil ? { selectedDate = nil } : nil,
            onClose: { windowState.hideDetailTray() },
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        DetailTrayEmptyState(
            icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
            title: "No Snapshots",
            message: "Tab snapshots are saved automatically every 15 minutes",
        )
    }

    // MARK: - Folder List View

    private var folderListView: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(groupedByDate, id: \.date) { group in
                    SnapshotFolderRow(
                        dateComponents: group.date,
                        snapshotCount: group.snapshots.count,
                        action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedDate = group.date
                            }
                        },
                    )
                }
            }
            .padding(.bottom, 8)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    // MARK: - Snapshot Detail View

    private func snapshotDetailView(for dateComponents: DateComponents) -> some View {
        let snapshots = snapshotsForDate(dateComponents)

        return ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(snapshots) { snapshot in
                    SnapshotCardView(
                        snapshot: snapshot,
                        spaceName: spaceName(for: snapshot.spaceID),
                        onRestore: {
                            snapshotToRestore = snapshot
                            showRestoreConfirmation = true
                        },
                        onAddTabs: {
                            addTabsFromSnapshot(snapshot)
                        },
                        onTabClick: { item in
                            navigateToURL(item.url)
                        },
                        onTabCmdClick: { item in
                            openInNewTab(item.url)
                        },
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    // MARK: - Computed Properties

    private var groupedByDate: [SnapshotDateGroup] {
        let calendar = Calendar.current
        var groups: [DateComponents: [TabSnapshot]] = [:]

        for snapshot in allSnapshots.prefix(Constants.maxSnapshots) {
            let components = calendar.dateComponents([.year, .month, .day], from: snapshot.createdAt)
            groups[components, default: []].append(snapshot)
        }

        return groups.map { SnapshotDateGroup(date: $0.key, snapshots: $0.value) }
            .sorted { lhs, rhs in
                guard let lhsDate = calendar.date(from: lhs.date),
                      let rhsDate = calendar.date(from: rhs.date) else { return false }
                return lhsDate > rhsDate
            }
    }

    private func snapshotsForDate(_ dateComponents: DateComponents) -> [TabSnapshot] {
        let calendar = Calendar.current
        return allSnapshots.filter { snapshot in
            let components = calendar.dateComponents([.year, .month, .day], from: snapshot.createdAt)
            return components == dateComponents
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    private func spaceName(for spaceID: UUID?) -> String? {
        guard let spaceID else { return nil }
        return tabManager.state.spaces.first(where: { $0.id == spaceID })?.name
    }

    // MARK: - Actions

    private func restoreSnapshot(_ snapshot: TabSnapshot) {
        guard let space = windowState.activeSpace else { return }

        // Close all current tabs
        for tab in currentTabs {
            tabManager.closeTab(tab)
        }

        // Create tabs from snapshot items in order
        for item in snapshot.items.sorted(by: { $0.position < $1.position }) {
            tabManager.createTab(url: item.url, in: space, makeActive: false)
        }

        windowState.hideDetailTray()
        Logger.info("Restored \(snapshot.tabCount) tabs from snapshot", category: Logger.data)
    }

    private func addTabsFromSnapshot(_ snapshot: TabSnapshot) {
        guard let space = windowState.activeSpace else { return }
        let currentURLs = Set(currentTabs.compactMap { normalizedURL($0.activePage.url) })
        var added = 0
        var skipped = 0

        for item in snapshot.items.sorted(by: { $0.position < $1.position }) {
            let normalized = normalizedURL(item.url)
            if currentURLs.contains(normalized) {
                skipped += 1
            } else {
                tabManager.createTab(url: item.url, in: space, makeActive: false)
                added += 1
            }
        }

        windowState.hideDetailTray()
        Logger.info("Added \(added) tabs from snapshot (\(skipped) already open)", category: Logger.data)
    }

    private func navigateToURL(_ url: URL) {
        if let pageID = windowState.activePageID,
           let page = tabManager.state.webPage(for: pageID) {
            page.load(url)
        } else {
            tabManager.createTab(url: url, makeActive: true)
        }
        windowState.hideDetailTray()
    }

    private func openInNewTab(_ url: URL) {
        tabManager.createTab(url: url, makeActive: false)
    }

    // MARK: - URL Normalization

    private func normalizedURL(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)

        // Remove query parameters
        components?.queryItems = nil

        // Remove fragment
        components?.fragment = nil

        // Lowercase host (use local variable to avoid overlapping access)
        if let host = components?.host?.lowercased() {
            components?.host = host
        }

        // Remove trailing slash from path
        if let path = components?.path, path.hasSuffix("/"), path != "/" {
            components?.path = String(path.dropLast())
        }

        return components?.string ?? url.absoluteString
    }

    // MARK: - Date Formatting

    private func formatDateForHeader(_ dateComponents: DateComponents) -> String {
        guard let date = Calendar.current.date(from: dateComponents) else {
            return "Snapshots"
        }
        return SnapshotDateFormatter.formatDate(date, style: .header)
    }
}

// MARK: - Supporting Types

private struct SnapshotDateGroup {
    let date: DateComponents
    let snapshots: [TabSnapshot]
}
