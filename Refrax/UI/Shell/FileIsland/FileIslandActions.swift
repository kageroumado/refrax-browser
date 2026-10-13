import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// What clicking, Option-clicking, and the menus on the File Island's items do.
struct FileIslandActions {
    let downloads: DownloadManager
    let shelf: ShelfManager
    let tabs: TabManager
    let windowState: WindowState

    /// Option is down as the item is clicked: the macOS way to ask for Show in Finder.
    static var optionIsHeld: Bool {
        NSEvent.modifierFlags.contains(.option)
    }

    // MARK: - Downloads

    /// A finished download opens, or shows in Finder with ⌥; a failed one retries; one in progress
    /// opens the full list, where it can be paused or cancelled.
    func activate(_ download: Download, revealing: Bool = Self.optionIsHeld) {
        switch download.state {
        case .completed:
            if revealing {
                downloads.revealInFinder(download.id)
            } else {
                downloads.openFile(download.id)
            }
        case .failed:
            retry(download)
        case .pending, .downloading, .paused:
            windowState.fileIsland.showAll()
        }
    }

    func retry(_ download: Download) {
        let id = download.id
        Task(name: "Retry download") { try? await downloads.retry(id) }
    }

    func pause(_ download: Download) {
        let id = download.id
        Task(name: "Pause download") { await downloads.pause(id) }
    }

    func resume(_ download: Download) {
        let id = download.id
        Task(name: "Resume download") { try? await downloads.resume(id) }
    }

    func copyFile(of download: Download) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([download.finalFileURL as NSURL])
    }

    /// An item provider for dragging a finished download out as its file.
    func dragProvider(for download: Download) -> NSItemProvider {
        guard download.state == .completed, let provider = NSItemProvider(contentsOf: download.finalFileURL) else {
            return NSItemProvider()
        }
        windowState.fileIsland.outgoingDragStarted = Date()
        return provider
    }

    // MARK: - Shelf

    /// Text copies, a link opens in a new tab, and a file opens; with ⌥, a file shows in Finder.
    func activate(_ item: ShelfItem, revealing: Bool = Self.optionIsHeld) {
        switch item.type {
        case .text:
            copy(item)
        case .link:
            if let url = item.url {
                Self.openLink(url, tabs: tabs, in: windowState)
            }
        case .image, .file, .alias:
            if revealing {
                shelf.revealInFinder(item)
            } else {
                shelf.open(item)
            }
        }
    }

    func copy(_ item: ShelfItem) {
        Task(name: "Copy shelf item") {
            await shelf.copy(item)
            windowState.showToast(item.type == .link ? "Address copied" : (item.type == .text ? "Text copied" : "Copied"))
        }
    }

    func remove(_ item: ShelfItem) {
        shelf.deleteItem(item)
    }

    func dragProvider(for item: ShelfItem) -> NSItemProvider {
        windowState.fileIsland.outgoingDragStarted = Date()
        return shelf.dragProvider(for: item)
    }

    // MARK: - Links

    /// Opens a web address as a new tab in the window's space and brings it to the front: in
    /// the floating layout, the page it replaces takes a place of its own.
    static func openLink(_ url: URL, tabs: TabManager, in windowState: WindowState) {
        guard let space = windowState.activeSpace else { return }
        let tab = tabs.createTab(url: url, in: space, makeActive: false, loadImmediately: true)
        tabs.setActiveTab(tab, in: windowState)
    }
}

/// The icon a download shows: its file's icon once finished, its type's icon until then.
struct FileIslandDownloadIcon: View {
    let download: Download
    let size: CGFloat

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }

    private var icon: NSImage {
        if download.state == .completed {
            return NSWorkspace.shared.icon(forFile: download.finalFileURL.path)
        }
        return NSWorkspace.shared.icon(for: download.contentType ?? UTType(filenameExtension: download.finalFileURL.pathExtension) ?? .data)
    }
}

/// A ring that fills with a download's progress, or spins while its size is unknown.
struct FileIslandProgressRing: View {
    let progress: Double?
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: FileIslandLayout.ringLineWidth)
            if let progress {
                Circle()
                    .trim(from: 0, to: max(0.02, min(1, progress)))
                    .stroke(Color.appAccentColor, style: StrokeStyle(lineWidth: FileIslandLayout.ringLineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A shelf item's picture: a thumbnail for an image, the first words for text, the site's
/// icon for a link, and the file's icon for a file.
struct FileIslandShelfThumbnail: View {
    let item: ShelfItem
    let size: CGFloat

    @Environment(ShelfManager.self) private var shelf
    @Environment(BrowserState.self) private var browserState
    @State private var thumbnail: NSImage?
    @State private var text: String?
    @State private var favicon: Data?

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(.rect(cornerRadius: FileIslandLayout.thumbnailCornerRadius * size / FileIslandLayout.thumbnailSize))
            .task(id: item.id) { await load() }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch item.type {
        case .image:
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                fileIcon
            }
        case .text:
            VStack(alignment: .leading, spacing: 1) {
                Image(systemName: item.type.systemImage)
                    .font(.system(size: size * 0.28))
                    .foregroundStyle(.secondary)
                Text(firstWords)
                    .font(.system(size: max(6, size * 0.2)))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
            }
            .padding(size * 0.1)
            .frame(width: size, height: size, alignment: .topLeading)
            .background(.background.secondary)
        case .link:
            FaviconView(data: favicon, url: item.url, size: size * 0.66)
                .frame(width: size, height: size)
        case .file, .alias:
            fileIcon
        }
    }

    private var fileIcon: some View {
        // An alias's stored file ends in .alias; its display name carries the real extension.
        let name = item.isAlias ? item.displayName : item.fileName
        return Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: URL(fileURLWithPath: name).pathExtension) ?? .data))
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    /// The first two words of a text item, which is how the eye recognizes it.
    private var firstWords: String {
        (text ?? item.displayName).split(whereSeparator: \.isWhitespace).prefix(2).joined(separator: " ")
    }

    private func load() async {
        switch item.type {
        case .image:
            let path = shelf.storagePath(for: item)
            let pixels = size * 2
            thumbnail = await Task.detached(priority: .utility) { Self.thumbnail(at: path, maxPixels: pixels) }.value
        case .text:
            text = await shelf.text(of: item)
        case .link:
            if let url = item.url {
                favicon = await browserState.faviconCache.faviconData(for: url, size: .small)
            }
        case .file, .alias:
            break
        }
    }

    private nonisolated static func thumbnail(at url: URL, maxPixels: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }
}
