import SwiftUI

/// The History window's Archived section: tabs closed into the archive, in every space.
///
/// Restore puts a tab back in its space; Delete removes it for good. The toolbar empties the
/// archive or copies the addresses of the selected tabs, or of every archived tab when none is
/// selected.
struct ArchivedTabsView: View {
    @Environment(TabManager.self) private var tabManager

    let searchText: String

    @State private var selection = Set<Tab.ID>()
    @State private var showsEmptyArchiveAlert = false

    /// Archived tabs, most recently archived first, narrowed by the search field.
    private var archivedTabs: [Tab] {
        _ = tabManager.state.tabListVersion
        return tabManager.browsableArchivedTabs
            .filter { searchText.isEmpty || matches($0) }
            .sorted { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
    }

    var body: some View {
        let tabs = archivedTabs
        Group {
            if tabs.isEmpty {
                emptyState
            } else {
                table(tabs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Copy Addresses", systemImage: "link") {
                    copyAddresses(of: selection.isEmpty ? tabs : tabs.filter { selection.contains($0.id) })
                }
                .help(selection.isEmpty ? "Copy the addresses of every archived tab" : "Copy the addresses of the selected tabs")
                .disabled(tabs.isEmpty)

                Button("Empty Archive", systemImage: "trash", role: .destructive) {
                    showsEmptyArchiveAlert = true
                }
                .disabled(tabs.isEmpty)
            }
        }
        .alert("Empty Archive", isPresented: $showsEmptyArchiveAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Empty Archive", role: .destructive) {
                actions.emptyArchive()
                selection.removeAll()
            }
        } message: {
            Text("The archived tabs listed here are deleted. Locked and private spaces keep theirs. This cannot be undone.")
        }
    }

    // MARK: - Table

    private func table(_ tabs: [Tab]) -> some View {
        Table(tabs, selection: $selection) {
            TableColumn("Title") { tab in
                HStack(spacing: 12) {
                    FaviconView(data: tab.activePage.faviconData, url: tab.activePage.url, size: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tab.customName ?? tab.displayTitle)
                            .lineLimit(1)
                        Text(tab.displayURL)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .width(min: 200, ideal: 400)

            TableColumn("Archived") { tab in
                if let archivedAt = tab.archivedAt {
                    Text(archivedAt, format: .dateTime)
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 80, ideal: 150)

            TableColumn("Space") { tab in
                if let space = tab.space {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(space.color)
                            .frame(width: 8, height: 8)
                        Text(space.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .width(min: 80, ideal: 120)
        }
        .contextMenu(forSelectionType: Tab.ID.self) { ids in
            let chosen = tabs.filter { ids.contains($0.id) }
            if !chosen.isEmpty {
                Button(chosen.count == 1 ? "Restore" : "Restore \(chosen.count) Tabs") {
                    restore(chosen)
                }
                Button(chosen.count == 1 ? "Copy Address" : "Copy Addresses") {
                    copyAddresses(of: chosen)
                }
                Divider()
                Button(chosen.count == 1 ? "Delete" : "Delete \(chosen.count) Tabs", role: .destructive) {
                    delete(chosen)
                }
            }
        } primaryAction: { ids in
            restore(tabs.filter { ids.contains($0.id) })
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Archived Tabs", systemImage: "archivebox")
        } description: {
            if searchText.isEmpty {
                Text("Tabs you close while the archive is on stay here until they expire.")
            } else {
                Text("No archived tabs match '\(searchText)'")
            }
        }
    }

    // MARK: - Actions

    /// The archive's verbs, shared with the library drawer.
    private var actions: ArchiveActions {
        ArchiveActions(tabs: tabManager, windowState: nil)
    }

    private func restore(_ tabs: [Tab]) {
        for tab in tabs {
            actions.restore(tab.id, open: false)
        }
        selection.subtract(tabs.map(\.id))
    }

    private func delete(_ tabs: [Tab]) {
        actions.delete(tabs.map(\.id))
        selection.subtract(tabs.map(\.id))
    }

    private func copyAddresses(of tabs: [Tab]) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tabs.map(\.activePage.url.absoluteString).joined(separator: "\n"), forType: .string)
    }

    private func matches(_ tab: Tab) -> Bool {
        tab.activePage.title.localizedCaseInsensitiveContains(searchText)
            || tab.displayURL.localizedCaseInsensitiveContains(searchText)
            || (tab.customName?.localizedCaseInsensitiveContains(searchText) ?? false)
    }
}
