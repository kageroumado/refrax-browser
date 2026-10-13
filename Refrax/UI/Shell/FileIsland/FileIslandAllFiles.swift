import SwiftUI

/// The File Island's full lists, from its overflow row or View › Show Downloads: every download
/// in progress and the recent finished ones, then everything on the shelf.
struct FileIslandAllFiles: View {
    let actions: FileIslandActions

    @Environment(DownloadManager.self) private var downloadManager
    @Environment(ShelfManager.self) private var shelf

    private enum Layout {
        static let iconSize: CGFloat = 26
        static let rowSpacing: CGFloat = 10
        static let horizontalPadding: CGFloat = 14
        /// Finished downloads listed here; the Downloads window keeps the rest.
        static let finishedLimit = 30
    }

    private var downloads: [Download] {
        let all = downloadManager.downloads
        let inProgress = all.filter { $0.state.isActive || $0.state == .paused }
        let finished = all.filter { $0.state == .completed || $0.state == .failed }
            .sorted { ($0.completedAt ?? $0.modifiedAt) > ($1.completedAt ?? $1.modifiedAt) }
            .prefix(Layout.finishedLimit)
        return inProgress + finished
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header("Downloads") {
                    Button("Show All") {
                        NSApp.typedDelegate.downloadsWindowController.showWindow()
                        actions.windowState.fileIsland.showsAll = false
                    }
                    .help("Open the Downloads window")
                }
                if downloads.isEmpty {
                    placeholder("Files you download appear here")
                } else {
                    ForEach(downloads) { download in
                        downloadRow(download)
                    }
                }
                Divider()
                    .padding(.vertical, 6)
                header("Shelf") {
                    if shelf.hasItems {
                        Button("Clear") { shelf.clearAll() }
                            .help("Remove everything from the shelf")
                    }
                }
                if shelf.hasItems {
                    ForEach(shelf.items) { item in
                        shelfRow(item)
                    }
                } else {
                    placeholder("Drop files, images, text, or links on the File Island to keep them here")
                }
            }
            .padding(.vertical, 10)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: FileIslandLayout.overflowPopoverWidth)
        .frame(maxHeight: FileIslandLayout.overflowPopoverMaxHeight)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityLabel("All files")
    }

    private func header(_ title: String, @ViewBuilder accessory: () -> some View) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            accessory()
                .buttonStyle(.borderless)
                .font(.system(size: 11))
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, 4)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.vertical, 6)
    }

    private func downloadRow(_ download: Download) -> some View {
        HStack(spacing: Layout.rowSpacing) {
            ZStack {
                if download.state.isActive || download.state == .paused {
                    FileIslandProgressRing(progress: download.progress, size: Layout.iconSize)
                    FileIslandDownloadIcon(download: download, size: Layout.iconSize - 10)
                } else {
                    FileIslandDownloadIcon(download: download, size: Layout.iconSize)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(download.destinationFilename)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(FileIslandDownloadMenu.status(of: download))
                    .font(.caption)
                    .foregroundStyle(download.state == .failed ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { actions.activate(download) }
        .if(download.state == .completed) { row in
            row.onDrag { actions.dragProvider(for: download) }
        }
        .contextMenu { FileIslandDownloadMenu(download: download, actions: actions) }
        .help(FileIslandDownloadMenu.tooltip(for: download))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Show in Finder") { actions.activate(download, revealing: true) }
    }

    private func shelfRow(_ item: ShelfItem) -> some View {
        HStack(spacing: Layout.rowSpacing) {
            FileIslandShelfThumbnail(item: item, size: Layout.iconSize)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(FileIslandShelfMenu.kind(of: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { actions.activate(item) }
        .onDrag { actions.dragProvider(for: item) }
        .contextMenu { FileIslandShelfMenu(item: item, actions: actions) }
        .help(FileIslandShelfMenu.tooltip(for: item))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Remove") { actions.remove(item) }
    }
}
