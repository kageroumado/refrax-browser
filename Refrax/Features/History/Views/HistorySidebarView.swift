import SwiftData
import SwiftUI

/// Sidebar for the History window showing date categories.
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
/// └─────────────────────┘
/// ```
struct HistorySidebarView: View {
    @Binding var selectedCategories: Set<HistoryDateCategory>
    @Query(sort: \HistoryEntry.visitedAt, order: .reverse)
    private var allEntries: [HistoryEntry]

    @State private var monthCategories: [HistoryDateCategory] = []
    @State private var categoryCounts: [HistoryDateCategory: Int] = [:]

    var body: some View {
        List(selection: $selectedCategories) {
            Section {
                ForEach(HistoryDateCategory.predefined, id: \.id) { category in
                    categoryRow(category)
                        .tag(category)
                }
            }

            if !monthCategories.isEmpty {
                Section("Earlier") {
                    ForEach(monthCategories, id: \.id) { category in
                        categoryRow(category)
                            .tag(category)
                    }
                }
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

    @ViewBuilder
    private func categoryRow(_ category: HistoryDateCategory) -> some View {
        let count = categoryCounts[category, default: 0]

        HStack {
            Label(category.title, systemImage: category.icon)

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
    @Previewable @State var selection: Set<HistoryDateCategory> = [.today]

    HistorySidebarView(selectedCategories: $selection)
        .frame(width: 220, height: 400)
}
