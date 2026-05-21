import SwiftData
import SwiftUI

// MARK: - History Tray View

/// History panel for the detail tray.
///
/// Displays browsing history with Apple Maps-style design:
/// - Large "History" title with close button
/// - Search field for filtering history
/// - Recent visits grouped by date (Today, Yesterday, etc.)
/// - Bottom toolbar with Clear History action
struct HistoryTrayView: View {
    @Environment(WindowState.self) private var windowState
    @Environment(HistoryManager.self) private var historyManager
    @Environment(TabManager.self) private var tabManager
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var isSelectionMode = false
    @State private var selectedEntries: Set<UUID> = []
    @State private var showClearConfirmation = false
    @State private var scrollOffset: CGFloat = 0
    @State private var initialScrollOffset: CGFloat?

    // Async search state
    @State private var searchResults: [HistoryEntryData] = []
    @State private var isSearchLoading = false
    private let searchDebouncer = AdaptiveDebouncer()

    @Query(
        sort: \HistoryEntry.visitedAt,
        order: .reverse,
    )
    private var allEntries: [HistoryEntry]

    private enum Constants {
        static let iconSize: CGFloat = 28
        static let rowVerticalPadding: CGFloat = 10
        static let maxRecentEntries = 200
    }

    var body: some View {
        ZStack {
            if isSearching {
                if searchResults.isEmpty, isSearchLoading {
                    // Only show spinner on initial search when no results exist yet.
                    // On subsequent keystrokes, keep showing old results to avoid
                    // structural view changes that steal focus from the search field.
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if searchResults.isEmpty {
                    emptyState
                } else {
                    searchResultsList
                }
            } else {
                if recentEntries.isEmpty {
                    emptyState
                } else {
                    historyList
                }
            }
        }
        .safeAreaBar(edge: .top) { header }
        .safeAreaBar(edge: .bottom) { footer }
        .confirmationDialog(
            "Clear All History?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible,
        ) {
            Button("Clear All", role: .destructive) {
                historyManager.clearAllHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove all browsing history. This action cannot be undone.")
        }
        .onChange(of: searchText) { _, newText in
            guard isSearching else {
                searchDebouncer.cancel()
                searchResults = []
                isSearchLoading = false
                return
            }

            // Only show the loading spinner when no previous results exist.
            // This avoids structural view changes (results → spinner → results)
            // on every keystroke, which would steal focus from the search field.
            if searchResults.isEmpty {
                isSearchLoading = true
            }
            searchDebouncer.debounce(for: newText) { [historyManager] in
                let results = await historyManager.search(query: newText, limit: Constants.maxRecentEntries)
                searchResults = results
                isSearchLoading = false
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            DetailTrayHeader(
                title: isSelectionMode ? "Select History" : "History",
                currentMode: .history,
                onExpand: isSelectionMode ? nil : { openFullHistoryView() },
                onClose: {
                    if isSelectionMode {
                        isSelectionMode = false
                        selectedEntries.removeAll()
                    } else {
                        windowState.hideDetailTray()
                    }
                },
            )

            // Search field (stays visible during selection mode to preserve item positions)
            DetailTraySearchField(text: $searchText, placeholder: "Search History")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        DetailTrayEmptyState(
            icon: "clock",
            title: isSearching ? "No Results" : "No History",
            message: isSearching
                ? "No history matches your search"
                : "Pages you visit will appear here",
        )
    }

    // MARK: - History List

    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                ForEach(Array(groupedEntries.enumerated()), id: \.element.title) { _, group in
                    Section {
                        ForEach(group.entries) { entry in
                            historyRow(entry)
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
            .animation(.easeInOut(duration: 0.25), value: recentEntries.map(\.id))
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

    // MARK: - Search Results List

    private var searchResultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResults) { entry in
                    searchResultRow(entry)
                }
            }
            .padding(.bottom, 8)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    private func searchResultRow(_ entry: HistoryEntryData) -> some View {
        HStack(spacing: 12) {
            // Domain icon
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(domainColor(for: entry.domain).opacity(0.15))

                Text(String(entry.domain.prefix(1)).uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(domainColor(for: entry.domain))
            }
            .frame(width: Constants.iconSize, height: Constants.iconSize)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title ?? entry.domain)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(entry.domain)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(formatTime(entry.visitedAt))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, Constants.rowVerticalPadding)
        .contentShape(Rectangle())
        .onTapGesture {
            openSearchResult(entry)
        }
        .contextMenu {
            Button("Open") {
                openSearchResult(entry)
            }

            Button("Open in New Tab") {
                tabManager.createTab(url: entry.url, makeActive: false)
            }

            Divider()

            Button("Copy URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.url.absoluteString, forType: .string)
            }

            Divider()

            Button("Delete", role: .destructive) {
                historyManager.deleteEntry(entry.id)
            }
        }
    }

    // MARK: - History Row

    private func historyRow(_ entry: HistoryEntry) -> some View {
        Button {
            if isSelectionMode {
                toggleSelection(entry.id)
            } else {
                openHistoryEntry(entry)
            }
        } label: {
            HStack(spacing: 12) {
                if isSelectionMode {
                    selectionIndicator(isSelected: selectedEntries.contains(entry.id))
                }

                domainIcon(for: entry)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title ?? entry.domain)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(entry.domain)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(formatTime(entry.visitedAt))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, Constants.rowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            historyContextMenu(entry)
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

    // MARK: - Domain Icon

    private func domainIcon(for entry: HistoryEntry) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(domainColor(for: entry.domain).opacity(0.15))

            Text(String(entry.domain.prefix(1)).uppercased())
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(domainColor(for: entry.domain))
        }
        .frame(width: Constants.iconSize, height: Constants.iconSize)
    }

    private func domainColor(for domain: String) -> Color {
        // Generate consistent color from domain hash
        let hash = domain.hashValue
        let colors: [Color] = [.blue, .purple, .pink, .red, .orange, .yellow, .green, .teal, .cyan, .indigo]
        return colors[abs(hash) % colors.count]
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func historyContextMenu(_ entry: HistoryEntry) -> some View {
        Button("Open") {
            openHistoryEntry(entry)
        }

        Button("Open in New Tab") {
            tabManager.createTab(url: entry.url, makeActive: false)
        }

        Divider()

        Button("Copy URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(entry.url.absoluteString, forType: .string)
        }

        Divider()

        Button("Delete", role: .destructive) {
            historyManager.deleteEntry(entry.id)
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        if isSelectionMode {
            DetailTraySelectionFooter(
                deleteAction: deleteSelectedEntries,
                doneAction: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSelectionMode = false
                    }
                    selectedEntries.removeAll()
                },
                hasSelection: !selectedEntries.isEmpty,
            )
            .transition(.opacity)
        } else {
            DetailTrayFooter {
                DetailTrayToolbar {
                    DetailTrayToolbarButton(
                        icon: "trash",
                        action: { showClearConfirmation = true },
                        isDestructive: true,
                        isDisabled: allEntries.isEmpty,
                        help: "Clear All History",
                    )

                    DetailTrayToolbarButton(
                        icon: "circle.grid.2x2.topleft.checkmark.filled",
                        action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSelectionMode = true
                            }
                        },
                        isDisabled: recentEntries.isEmpty,
                        help: "Select History Items",
                    )
                }
            }
            .transition(.opacity)
        }
    }

    // MARK: - Computed Properties

    private var isSearching: Bool {
        !searchText.isEmpty
    }

    /// Recent entries from @Query for non-search display.
    private var recentEntries: [HistoryEntry] {
        Array(allEntries.prefix(Constants.maxRecentEntries))
    }

    private var groupedEntries: [HistoryGroup] {
        let entries = recentEntries
        let calendar = Calendar.current
        let now = Date()

        var groups: [String: [HistoryEntry]] = [:]

        for entry in entries {
            let key: String = if calendar.isDateInToday(entry.visitedAt) {
                "Today"
            } else if calendar.isDateInYesterday(entry.visitedAt) {
                "Yesterday"
            } else if calendar.isDate(entry.visitedAt, equalTo: now, toGranularity: .weekOfYear) {
                "This Week"
            } else if calendar.isDate(entry.visitedAt, equalTo: now, toGranularity: .month) {
                "This Month"
            } else {
                entry.visitedAt.formatted(.dateTime.month(.wide).year())
            }

            groups[key, default: []].append(entry)
        }

        // Sort groups in chronological order
        let orderedKeys = ["Today", "Yesterday", "This Week", "This Month"]
        var result: [HistoryGroup] = []

        for key in orderedKeys {
            if let entries = groups[key], !entries.isEmpty {
                result.append(HistoryGroup(title: key, entries: entries))
                groups.removeValue(forKey: key)
            }
        }

        // Add remaining month groups sorted by date
        let remainingGroups = groups.sorted { first, second in
            guard let firstDate = first.value.first?.visitedAt,
                  let secondDate = second.value.first?.visitedAt else { return false }
            return firstDate > secondDate
        }

        for (key, entries) in remainingGroups {
            result.append(HistoryGroup(title: key, entries: entries))
        }

        return result
    }

    // MARK: - Actions

    private func openFullHistoryView() {
        NSApp.typedDelegate.historyWindowController.showWindow()
        windowState.hideDetailTray()
    }

    private func openHistoryEntry(_ entry: HistoryEntry) {
        if let pageID = windowState.activePageID,
           let page = tabManager.state.webPage(for: pageID) {
            page.load(entry.url)
        } else {
            tabManager.createTab(url: entry.url, makeActive: true)
        }
        windowState.hideDetailTray()
    }

    private func openSearchResult(_ entry: HistoryEntryData) {
        if let pageID = windowState.activePageID,
           let page = tabManager.state.webPage(for: pageID) {
            page.load(entry.url)
        } else {
            tabManager.createTab(url: entry.url, makeActive: true)
        }
        windowState.hideDetailTray()
    }

    private func toggleSelection(_ id: UUID) {
        if selectedEntries.remove(id) == nil {
            selectedEntries.insert(id)
        }
    }

    private func deleteSelectedEntries() {
        for id in selectedEntries {
            historyManager.deleteEntry(id)
        }
        selectedEntries.removeAll()
        isSelectionMode = false
    }

    private func formatTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - History Group

private struct HistoryGroup {
    let title: String
    let entries: [HistoryEntry]
}
