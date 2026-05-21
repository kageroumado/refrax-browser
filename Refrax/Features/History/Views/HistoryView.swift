import SwiftData
import SwiftUI

/// Main history view with sidebar navigation, table/graph content, and inspector panel.
///
/// Follows SF Symbols app design: full-height sidebar, toolbar controls, inspector for details.
///
/// ## Visual Layout
///
/// ```
/// ┌──────────────┬────────────────────────────────┬──────────────────┐
/// │   Sidebar    │         Content Area           │    Inspector     │
/// │              │                                │                  │
/// │ ▸ Today      │ ┌──[List][Graph]──[Search]──┐  │ Page Details     │
/// │   Yesterday  │ │                            │  │                  │
/// │   This Week  │ │  Table content              │  │ Visited: ...     │
/// │   Nov 2025   │ │                            │  │ Duration: ...    │
/// │   Oct 2025   │ └────────────────────────────┘  │ Parent: ...      │
/// └──────────────┴────────────────────────────────┴──────────────────┘
/// ```
///
/// ## Features
///
/// - **Sidebar**: Date categories with multi-select (Cmd+click)
/// - **View Modes**: List and Graph toggle in toolbar
/// - **Search**: Full-text search across entries
/// - **Inspector**: Detailed entry information, persisted visibility
/// - **Reactive**: Uses @Query for automatic updates
struct HistoryView: View {
    @Environment(HistoryManager.self) private var historyManager
    @Environment(TabManager.self) private var tabManager
    @Environment(\.modelContext) private var modelContext

    // MARK: - Data

    @Query(sort: \HistoryEntry.visitedAt, order: .reverse)
    private var allEntries: [HistoryEntry]

    // MARK: - State

    @State private var selectedCategories: Set<HistoryDateCategory> = [.today]
    @State private var selectedEntry: HistoryEntry?
    @State private var viewMode: ViewMode = .list
    @State private var searchText = ""
    @State private var selection = Set<HistoryEntry.ID>()
    @State private var sortOrder = [KeyPathComparator(\HistoryEntry.visitedAt, order: .reverse)]
    @State private var showDeleteAllAlert = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @AppStorage("historyInspectorVisible") private var showInspector = true

    // Cached filtered entries — updated via .onChange instead of recomputing every body evaluation
    @State private var cachedFilteredEntries: [HistoryEntry] = []

    // Async-loaded domain time
    @State private var domainTimeToday: TimeInterval?
    @State private var timeSpentTask: Task<Void, Never>?

    enum ViewMode {
        case list
        case graph
    }

    // MARK: - Body

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            HistorySidebarView(selectedCategories: $selectedCategories)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } detail: {
            contentArea
        }
        .inspector(isPresented: $showInspector) {
            inspectorContent
                .inspectorColumnWidth(min: 250, ideal: 280, max: 350)
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search history")
        .toolbar { toolbarContent }
        .alert("Clear All History", isPresented: $showDeleteAllAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete All", role: .destructive) {
                deleteAllHistory()
            }
        } message: {
            Text("This will permanently delete all browsing history. This action cannot be undone.")
        }
        .onChange(of: selection) { _, newSelection in
            // Update selected entry for inspector when single selection
            if newSelection.count == 1, let id = newSelection.first {
                selectedEntry = filteredEntries.first { $0.id == id }
            } else {
                selectedEntry = nil
            }
        }
        .onChange(of: selectedEntry) { _, entry in
            timeSpentTask?.cancel()
            guard let entry else {
                domainTimeToday = nil
                return
            }
            timeSpentTask = Task {
                let time = await historyManager.timeSpent(on: entry.domain, for: Date())
                guard !Task.isCancelled else { return }
                domainTimeToday = time
            }
        }
        .task {
            recomputeFilteredEntries()
        }
        .onChange(of: allEntries) { _, _ in
            recomputeFilteredEntries()
        }
        .onChange(of: selectedCategories) { _, _ in
            recomputeFilteredEntries()
        }
        .onChange(of: searchText) { _, _ in
            recomputeFilteredEntries()
        }
        .onChange(of: sortOrder) { _, _ in
            recomputeFilteredEntries()
        }
    }

    // MARK: - Content Area

    private var contentArea: some View {
        Group {
            switch viewMode {
            case .list:
                listContent
            case .graph:
                HistoryGraphView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private var listContent: some View {
        if filteredEntries.isEmpty {
            emptyState
        } else {
            historyTable
        }
    }

    // MARK: - Table

    private var historyTable: some View {
        Table(filteredEntries, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Title", value: \HistoryEntry.displayURL) { entry in
                HStack(spacing: 12) {
                    faviconView(for: entry)
                        .frame(width: 20, height: 20)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(entry.title ?? entry.displayURL)
                                .lineLimit(1)
                                .foregroundStyle(entry.failedToLoad ? .secondary : .primary)

                            if entry.failedToLoad {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                    .help("Failed to load")
                            }
                        }

                        HStack(spacing: 4) {
                            Text(entry.displayURL)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            if entry.failedToLoad, let code = entry.httpStatusCode {
                                Text("(\(statusCodeDescription(code)))")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            .width(min: 200, ideal: 400)

            TableColumn("Visited", value: \HistoryEntry.visitedAt) { entry in
                Text(entry.visitedAt, format: .dateTime)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 150)

            TableColumn("Time Spent", value: \HistoryEntry.timeSpent) { entry in
                Text(formatTimeSpent(entry.timeSpent))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Space") { entry in
                if let spaceID = entry.spaceID,
                   let space = tabManager.state.space(for: spaceID) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(space.color)
                            .frame(width: 8, height: 8)

                        Text(space.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                }
            }
            .width(min: 80, ideal: 120)
        }
        .contextMenu(forSelectionType: HistoryEntry.ID.self) { items in
            contextMenuContent(for: items)
        }
    }

    @ViewBuilder
    private func contextMenuContent(for items: Set<HistoryEntry.ID>) -> some View {
        if items.count == 1, let id = items.first,
           let entry = filteredEntries.first(where: { $0.id == id }) {
            Button("Open in New Tab") {
                openInNewTab(entry.url)
            }

            Button("Copy URL") {
                copyURL(entry.url)
            }

            Divider()

            Button("Delete", role: .destructive) {
                deleteEntry(entry)
            }
        } else if items.count > 1 {
            Button("Open All in New Tabs") {
                let urls = items.compactMap { id in
                    filteredEntries.first(where: { $0.id == id })?.url
                }
                openAllInNewTabs(urls)
            }

            Divider()

            Button("Delete \(items.count) Items", role: .destructive) {
                deleteEntries(Array(items))
            }
        }
    }

    // MARK: - Inspector

    private var inspectorContent: some View {
        HistoryInspectorView(
            entry: selectedEntry,
            onOpen: { entry in
                openInNewTab(entry.url)
            },
            onDelete: { entry in
                deleteEntry(entry)
                selectedEntry = nil
            },
            domainTimeToday: domainTimeToday,
            spaceName: spaceName,
            spaceColor: spaceColor,
        )
    }

    private var spaceName: String? {
        guard let entry = selectedEntry,
              let spaceID = entry.spaceID,
              let space = tabManager.state.space(for: spaceID) else { return nil }
        return space.name
    }

    private var spaceColor: Color? {
        guard let entry = selectedEntry,
              let spaceID = entry.spaceID,
              let space = tabManager.state.space(for: spaceID) else { return nil }
        return space.color
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No History", systemImage: "clock")
        } description: {
            if searchText.isEmpty {
                Text("No browsing history for the selected period")
            } else {
                Text("No results for '\(searchText)'")
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            // View mode toggle
            Picker("View Mode", selection: $viewMode) {
                Label("List", systemImage: "list.bullet").tag(ViewMode.list)
                Label("Graph", systemImage: "chart.line.uptrend.xyaxis").tag(ViewMode.graph)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)

            // Inspector toggle
            Button {
                showInspector.toggle()
            } label: {
                Label("Inspector", systemImage: showInspector ? "sidebar.right" : "sidebar.right")
            }
            .help(showInspector ? "Hide Inspector" : "Show Inspector")

            // Clear all
            Button(role: .destructive) {
                showDeleteAllAlert = true
            } label: {
                Label("Clear All", systemImage: "trash")
            }
            .disabled(allEntries.isEmpty)
        }
    }

    // MARK: - Filtered Entries

    private var filteredEntries: [HistoryEntry] { cachedFilteredEntries }

    private func recomputeFilteredEntries() {
        var result = allEntries

        // Filter by selected categories (multi-select)
        if !selectedCategories.isEmpty {
            result = result.filter { entry in
                selectedCategories.contains { category in
                    category.contains(entry.visitedAt)
                }
            }
        }

        // Filter by search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { entry in
                entry.searchableText.contains(query)
            }
        }

        cachedFilteredEntries = result.sorted(using: sortOrder)
    }

    // MARK: - Actions

    private func deleteAllHistory() {
        historyManager.clearAllHistory()
        selection.removeAll()
        selectedEntry = nil
    }

    private func deleteEntry(_ entry: HistoryEntry) {
        historyManager.deleteEntry(entry.id)
        selection.remove(entry.id)
        if selectedEntry?.id == entry.id {
            selectedEntry = nil
        }
    }

    private func deleteEntries(_ ids: [HistoryEntry.ID]) {
        for id in ids {
            historyManager.deleteEntry(id)
        }
        selection.subtract(ids)
        selectedEntry = nil
    }

    private func openInNewTab(_ url: URL) {
        tabManager.createTab(url: url, makeActive: true)
    }

    private func openAllInNewTabs(_ urls: [URL]) {
        for url in urls {
            tabManager.createTab(url: url, makeActive: false, loadImmediately: true)
        }
    }

    private func copyURL(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }

    // MARK: - Helpers

    private func faviconView(for entry: HistoryEntry) -> some View {
        Group {
            if entry.failedToLoad {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            } else if let faviconURL = entry.faviconURL {
                AsyncImage(url: faviconURL) { image in
                    image
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .clipToSquircle()
                } placeholder: {
                    LetterFallbackView(url: entry.url)
                }
            } else {
                LetterFallbackView(url: entry.url)
            }
        }
    }

    private func statusCodeDescription(_ code: Int) -> String {
        switch code {
        case 0: "Network unreachable"
        case 404: "Not found"
        case 408: "Timeout"
        case 495: "SSL error"
        case 503: "Service unavailable"
        default: "Error \(code)"
        }
    }

    private func formatTimeSpent(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3_600 {
            return "\(Int(seconds / 60))m"
        } else {
            let hours = Int(seconds / 3_600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3_600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
}

// MARK: - Preview

#Preview(traits: .modifier(RefraxPreviewModifier())) {
    HistoryView()
        .frame(width: 1_200, height: 800)
}
