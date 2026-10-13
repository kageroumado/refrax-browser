import SwiftUI

/// A download on the File Island: its icon inside a progress ring while it downloads, the
/// file's own icon once finished. Click opens it, ⌥-click shows it in Finder, and it drags
/// out as the file.
struct FileIslandDownloadCell: View {
    let download: Download
    let actions: FileIslandActions

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isInProgress: Bool {
        download.state.isActive || download.state == .paused
    }

    var body: some View {
        ZStack {
            if isInProgress {
                FileIslandProgressRing(progress: download.progress, size: FileIslandLayout.thumbnailSize)
                FileIslandDownloadIcon(download: download, size: FileIslandLayout.thumbnailSize - 12)
            } else {
                FileIslandDownloadIcon(download: download, size: FileIslandLayout.thumbnailSize)
            }
        }
        .overlay(alignment: .bottomTrailing) { badge }
        .frame(width: FileIslandLayout.cellSize, height: FileIslandLayout.cellSize)
        .contentShape(Rectangle())
        .onTapGesture { actions.activate(download) }
        .if(download.state == .completed) { cell in
            cell.onDrag { actions.dragProvider(for: download) }
        }
        .contextMenu { FileIslandDownloadMenu(download: download, actions: actions) }
        .animation(reduceMotion ? nil : .default, value: download.progress)
        .help(FileIslandDownloadMenu.tooltip(for: download))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(download.destinationFilename)
        .accessibilityValue(FileIslandDownloadMenu.status(of: download))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { actions.activate(download, revealing: false) }
        .accessibilityAction(named: "Show in Finder") { actions.activate(download, revealing: true) }
    }

    @ViewBuilder
    private var badge: some View {
        switch download.state {
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.white, .orange)
                .padding(2)
        case .paused:
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.white, .secondary)
                .padding(2)
        default:
            EmptyView()
        }
    }
}

/// The menu a download carries on the island and in the full list.
struct FileIslandDownloadMenu: View {
    let download: Download
    let actions: FileIslandActions

    var body: some View {
        if download.state == .completed {
            Button("Open", systemImage: "arrow.up.forward.app") { actions.activate(download, revealing: false) }
            Button("Show in Finder", systemImage: "folder") { actions.activate(download, revealing: true) }
            Button("Copy", systemImage: "doc.on.doc") { actions.copyFile(of: download) }
            Divider()
        }
        if download.state == .downloading {
            Button("Pause", systemImage: "pause") { actions.pause(download) }
        }
        if download.canResume {
            Button("Resume", systemImage: "play") { actions.resume(download) }
        }
        if download.canRetry {
            Button("Retry", systemImage: "arrow.clockwise") { actions.retry(download) }
        }
        if download.state.isActive {
            Button("Cancel Download", systemImage: "xmark", role: .destructive) { actions.downloads.cancel(download.id) }
        }
        Button("Remove from List", systemImage: "minus.circle") { actions.downloads.remove(download.id) }
    }

    /// Where a download stands, in words.
    static func status(of download: Download) -> String {
        switch download.state {
        case .downloading:
            download.progress.map { "\(Int($0 * 100))%" } ?? "Downloading"
        case .failed:
            download.errorMessage ?? "Failed"
        case .completed:
            download.bytesReceived.formatted(.byteCount(style: .file))
        case .pending, .paused:
            download.state.displayName
        }
    }

    /// The download's name and what a click does, then the key for the second action.
    static func tooltip(for download: Download) -> String {
        let name = download.destinationFilename
        return switch download.state {
        case .completed: "Open \(name) · ⌥ shows in Finder · drag to move it out"
        case .failed: "Retry \(name) · \(status(of: download))"
        case .pending, .downloading, .paused: "\(name) · \(status(of: download)) · click for all downloads"
        }
    }
}

/// A shelf item on the File Island. Click opens a file, copies text, or opens a link in a new
/// tab; ⌥-click shows a file in Finder; it drags out as what it holds.
struct FileIslandShelfCell: View {
    let item: ShelfItem
    let actions: FileIslandActions

    var body: some View {
        FileIslandShelfThumbnail(item: item, size: FileIslandLayout.thumbnailSize)
            .frame(width: FileIslandLayout.cellSize, height: FileIslandLayout.cellSize)
            .contentShape(Rectangle())
            .onTapGesture { actions.activate(item) }
            .onDrag { actions.dragProvider(for: item) }
            .contextMenu { FileIslandShelfMenu(item: item, actions: actions) }
            .help(FileIslandShelfMenu.tooltip(for: item))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.displayName)
            .accessibilityValue(FileIslandShelfMenu.kind(of: item))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { actions.activate(item, revealing: false) }
            .accessibilityAction(named: "Copy") { actions.copy(item) }
            .accessibilityAction(named: "Remove") { actions.remove(item) }
    }
}

/// The menu a shelf item carries on the island and in the full list.
struct FileIslandShelfMenu: View {
    let item: ShelfItem
    let actions: FileIslandActions

    var body: some View {
        switch item.type {
        case .link:
            Button("Open in New Tab", systemImage: "plus.square.on.square") { actions.activate(item, revealing: false) }
        case .image, .file, .alias:
            Button("Open", systemImage: "arrow.up.forward.app") { actions.activate(item, revealing: false) }
            Button("Show in Finder", systemImage: "folder") { actions.activate(item, revealing: true) }
        case .text:
            EmptyView()
        }
        Button("Copy", systemImage: "doc.on.doc") { actions.copy(item) }
        Divider()
        Button("Remove", systemImage: "minus.circle", role: .destructive) { actions.remove(item) }
    }

    static func kind(of item: ShelfItem) -> String {
        switch item.type {
        case .text: "Text"
        case .link: item.url?.safeDisplayDomain ?? "Link"
        case .image: "Image"
        case .file, .alias: "File"
        }
    }

    /// What a click does, then the key for the second action.
    static func tooltip(for item: ShelfItem) -> String {
        switch item.type {
        case .text: "Copy “\(item.displayName)” · drag to move it out"
        case .link: "Open \(kind(of: item)) in a new tab · drag to move it out"
        case .image, .file, .alias: "Open \(item.displayName) · ⌥ shows in Finder · drag to move it out"
        }
    }
}
