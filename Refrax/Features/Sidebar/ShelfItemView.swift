import SwiftUI

/// Individual shelf item view displaying thumbnail/icon with hover actions.
///
/// Shows:
/// - Thumbnail for images, icon for text/files
/// - Display name (truncated)
/// - Delete (×) button on hover
///
/// Uses AppKit drag source for proper filename handling in drag-out operations.
struct ShelfItemView: View {
    @Environment(ShelfManager.self) private var shelfManager
    let item: ShelfItem

    @State private var isHovering = false
    @State private var thumbnail: NSImage?
    @State private var textContent: String?

    var body: some View {
        ShelfDragSource(item: item, storagePath: shelfManager.storagePath(for: item)) {
            itemContent
        }
        .task {
            await loadThumbnail()
            await loadTextContent()
        }
    }

    /// The visual content of the shelf item.
    private var itemContent: some View {
        VStack(spacing: 4) {
            // Thumbnail/icon area
            ZStack(alignment: .topTrailing) {
                thumbnailView
                    .frame(width: Layout.thumbnailSize, height: Layout.thumbnailSize)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(.quaternary, lineWidth: 0.5)
                    }

                // Delete button (visible on hover)
                if isHovering {
                    Button {
                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                            shelfManager.deleteItem(item)
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .offset(x: 4, y: -4)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }

            // Display name
            Text(item.displayName)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: Layout.thumbnailSize)
        }
        .padding(4)
        .background(.primary.opacity(isHovering ? 0.06 : 0.02), in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    // MARK: - Thumbnail View

    @ViewBuilder
    private var thumbnailView: some View {
        switch item.type {
        case .image:
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                iconView
            }

        case .text:
            textPreview

        case .file, .alias:
            iconView
        }
    }

    /// Icon fallback view.
    private var iconView: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)

            Image(systemName: item.type.systemImage)
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
        }
    }

    /// Text preview showing first few characters.
    /// Note: Text content is loaded asynchronously to avoid disk I/O in view body.
    private var textPreview: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)

            if let text = textContent {
                Text(text)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .padding(4)
            } else {
                Image(systemName: "doc.text")
                    .font(.system(size: 24))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Data Loading

    /// Loads thumbnail for image items.
    private func loadThumbnail() async {
        guard item.type == .image else { return }

        let path = shelfManager.storagePath(for: item)
        let targetSize = Layout.thumbnailSize * 2 // Retina

        let loadedImage = await Task.detached(priority: .utility) {
            guard let image = NSImage(contentsOf: path) else { return nil as NSImage? }

            let aspect = image.size.width / image.size.height
            let size = aspect > 1
                ? NSSize(width: targetSize, height: targetSize / aspect)
                : NSSize(width: targetSize * aspect, height: targetSize)

            let thumbnail = NSImage(size: size)
            thumbnail.lockFocus()
            image.draw(
                in: NSRect(origin: .zero, size: size),
                from: NSRect(origin: .zero, size: image.size),
                operation: .copy,
                fraction: 1.0,
            )
            thumbnail.unlockFocus()
            return thumbnail
        }.value

        if let loadedImage {
            thumbnail = loadedImage
        }
    }

    /// Loads text content from a .textClipping file asynchronously.
    private func loadTextContent() async {
        guard item.type == .text else { return }

        let path = shelfManager.storagePath(for: item)

        // Perform disk I/O on background thread
        let content = await Task.detached(priority: .utility) {
            guard let data = try? Data(contentsOf: path),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let text = plist["public.utf8-plain-text"] as? String else {
                return nil as String?
            }
            return text
        }.value

        if let content {
            textContent = content
        }
    }
}

// MARK: - Layout Constants

private enum Layout {
    static let thumbnailSize: CGFloat = 56
}
