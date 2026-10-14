import SwiftData
import SwiftUI

/// A row of the History window's sidebar: a date range of visits, or the archived tabs.
enum HistorySidebarItem: Hashable {
    case visits(HistoryDateCategory)
    case archived
}

/// Sidebar for the History window: date categories, then the archived tabs.
///
/// Supports multi-select via Cmd+click to combine date ranges.
///
/// ## Visual Layout
///
/// ```
/// ┌─────────────────────┐
/// │ History           🔍│
/// ├─────────────────────┤
/// │ ▸ Today         (5) │
/// │   Yesterday     (3) │
/// │   This Week    (12) │
/// │   This Month    (8) │
/// ├─────────────────────┤
/// │   November 2025(20) │
/// │   October 2025 (15) │
/// ├─────────────────────┤
/// │   Archived      (4) │
/// └─────────────────────┘
/// ```
struct HistorySidebarView: View {
    @Binding var selection: Set<HistorySidebarItem>
    @Environment(TabManager.self) private var tabManager
    @Query(sort: \HistoryEntry.visitedAt, order: .reverse)
    private var allEntries: [HistoryEntry]

    @State private var monthCategories: [HistoryDateCategory] = []
    @State private var categoryCounts: [HistoryDateCategory: Int] = [:]

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(HistoryDateCategory.predefined, id: \.id) { category in
                    categoryRow(category)
                        .tag(HistorySidebarItem.visits(category))
                }
            }

            if !monthCategories.isEmpty {
                Section("Earlier") {
                    ForEach(monthCategories, id: \.id) { category in
                        categoryRow(category)
                            .tag(HistorySidebarItem.visits(category))
                    }
                }
            }

            Section("Tabs") {
                row(title: "Archived", icon: "archivebox", count: archivedTabCount)
                    .tag(HistorySidebarItem.archived)
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180)
        .onChange(of: allEntries) { _, entries in
            updateDerivedState(from: entries)
        }
        .task {
            updateDerivedState(from: allEntries)
        }
    }

    // MARK: - Category Row

    /// Archived tabs in every space.
    private var archivedTabCount: Int {
        _ = tabManager.state.tabListVersion
        return tabManager.state.spaces.reduce(0) { $0 + $1.tabs.count(where: \.isArchived) }
    }

    private func categoryRow(_ category: HistoryDateCategory) -> some View {
        row(title: category.title, icon: category.icon, count: categoryCounts[category, default: 0])
    }

    private func row(title: String, icon: String, count: Int) -> some View {
        HStack {
            Label(title, systemImage: icon)

            Spacer()

            if count > 0 {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    private func updateDerivedState(from entries: [HistoryEntry]) {
        let dates = entries.map(\.visitedAt)
        monthCategories = HistoryDateCategory.monthCategories(from: dates)

        let allCategories = HistoryDateCategory.predefined + monthCategories
        let ranges = allCategories.map { ($0, $0.dateRange) }

        var counts: [HistoryDateCategory: Int] = [:]
        for (category, _) in ranges {
            counts[category] = 0
        }

        for entry in entries {
            let date = entry.visitedAt
            for (category, range) in ranges where range.contains(date) {
                counts[category, default: 0] += 1
            }
        }

        categoryCounts = counts
    }
}

// MARK: - Preview

#Preview(traits: .modifier(RefraxPreviewModifier())) {
    @Previewable @State var selection: Set<HistorySidebarItem> = [.visits(.today)]

    HistorySidebarView(selection: $selection)
        .frame(width: 220, height: 400)
}
