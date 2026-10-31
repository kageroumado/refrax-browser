import SwiftUI

/// The archive in the library drawer: tabs closed into it, by space, newest first. A click
/// restores a tab and opens it; its menu restores it in the background, copies its address,
/// or deletes it; the footer empties the archive.
struct ArchiveTrayView: View {
    @Environment(WindowState.self) private var windowState
    @Environment(TabManager.self) private var tabManager
    @Environment(BrowserSettings.self) private var settings

    @State private var query = ""
    @State private var showsEmptyConfirmation = false

    private var actions: ArchiveActions {
        ArchiveActions(tabs: tabManager, windowState: windowState)
    }

    /// The shelf, read again whenever the tab list changes: archiving, restoring, and deleting
    /// all change it.
    private var shelf: ArchiveShelf {
        _ = tabManager.state.tabListVersion
        return actions.shelf(query: query)
    }

    var body: some View {
        let shelf = shelf
        Group {
            if shelf.isEmpty {
                emptyState
            } else {
                list(shelf)
            }
        }
        .safeAreaBar(edge: .top) {
            VStack(spacing: 0) {
                DetailTrayHeader(title: "Archive", currentMode: .archive, onClose: { windowState.hideDetailTray() })
                DetailTraySearchField(text: $query, placeholder: "Search Archive")
            }
        }
        .safeAreaBar(edge: .bottom) {
            if !shelf.isEmpty || !query.isEmpty {
                HStack {
                    Text("^[\(shelf.count) tab](inflect: true)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Empty Archive", systemImage: "trash", role: .destructive) {
                        showsEmptyConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(tabManager.browsableArchivedTabs.isEmpty)
                }
                .padding(12)
            }
        }
        .alert("Empty Archive", isPresented: $showsEmptyConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Empty Archive", role: .destructive) { actions.emptyArchive() }
        } message: {
            Text("Every archived tab listed here is deleted. Locked and private spaces keep theirs. This cannot be undone.")
        }
        .accessibilityIdentifier("ArchiveDrawer")
    }

    private func list(_ shelf: ArchiveShelf) -> some View {
        List {
            ForEach(shelf.sections) { section in
                Section(shelf.sections.count > 1 ? section.title : "") {
                    ForEach(section.entries) { entry in
                        ArchiveRow(entry: entry, actions: actions)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var emptyState: some View {
        if !query.isEmpty {
            DetailTrayEmptyState(icon: "magnifyingglass", title: "No Results", message: "No archived tab matches “\(query)”.")
        } else if settings.archiveEnabled {
            DetailTrayEmptyState(icon: "archivebox", title: "Archive Is Empty", message: "Tabs you close stay here until they expire.")
        } else {
            DetailTrayEmptyState(icon: "archivebox", title: "Archive Is Off", message: "Turn on the archive in Settings › Tabs to keep closed tabs here.")
        }
    }
}

/// One archived tab: its favicon, title, and when it was archived; a click restores and
/// opens it.
private struct ArchiveRow: View {
    let entry: ArchiveShelf.Entry
    let actions: ArchiveActions

    @Environment(TabManager.self) private var tabManager
    @Environment(WindowState.self) private var windowState

    private enum Layout {
        static let faviconSize: CGFloat = 16
    }

    var body: some View {
        let tab = tabManager.state.tab(for: entry.id)
        Button {
            actions.restore(entry.id, open: true)
            windowState.hideDetailTray()
        } label: {
            HStack(spacing: 10) {
                FaviconView(data: tab?.activePage.faviconData, url: tab?.activePage.url ?? .blank, size: Layout.faviconSize)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                        .lineLimit(1)
                    Text(entry.archivedAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(entry.address)
        .contextMenu {
            Button("Restore and Open") {
                actions.restore(entry.id, open: true)
                windowState.hideDetailTray()
            }
            Button("Restore") { actions.restore(entry.id, open: false) }
            Button("Copy Address") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(tab?.activePage.url.absoluteString ?? entry.address, forType: .string)
            }
            Divider()
            Button("Delete", role: .destructive) { actions.delete([entry.id]) }
        }
        .accessibilityLabel(entry.title)
        .accessibilityHint("Restores the tab and opens it")
        .accessibilityAction(named: "Restore in Background") { actions.restore(entry.id, open: false) }
        .accessibilityAction(named: "Delete") { actions.delete([entry.id]) }
    }
}
