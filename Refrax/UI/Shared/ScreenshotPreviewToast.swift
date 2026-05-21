import SwiftUI

/// Screenshot preview thumbnail displayed after capture.
///
/// Appears in the bottom-right corner like the macOS system screenshot preview.
/// Provides quick actions to copy, open in Finder, or dismiss.
/// Auto-dismisses after 5 seconds if not interacted with.
struct ScreenshotPreviewToast: View {
    let preview: ScreenshotCoordinator.ScreenshotPreview
    let onCopy: () -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void
    let onDismiss: () -> Void
    let onHoverChanged: (Bool) -> Void

    @State private var isHovering = false

    private enum Layout {
        static let maxWidth: CGFloat = 200
        static let maxHeight: CGFloat = 160
        static let cornerRadius: CGFloat = 8
        static let shadowRadius: CGFloat = 12
        static let padding: CGFloat = 8
    }

    private var imageSize: CGSize {
        let imageWidth = preview.image.size.width
        let imageHeight = preview.image.size.height
        guard imageWidth > 0, imageHeight > 0 else {
            return CGSize(width: Layout.maxWidth, height: Layout.maxHeight)
        }
        let aspect = imageWidth / imageHeight
        let width = min(Layout.maxWidth, Layout.maxHeight * aspect)
        let height = width / aspect
        return CGSize(width: width, height: height)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            // Preview image — sized to actual screenshot aspect ratio, draggable as image
            ScreenshotDragSource(
                image: preview.image,
                imageData: preview.data,
                savedURL: preview.savedURL,
                onDragStarted: { onHoverChanged(true) },
                onDragEnded: { dropped in
                    if dropped {
                        onDismiss()
                    } else {
                        onHoverChanged(false)
                    }
                },
            ) {
                Image(nsImage: preview.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: imageSize.width, height: imageSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: Layout.cornerRadius)
                            .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                    }
            }

            // Action buttons (visible on hover)
            if isHovering {
                HStack(spacing: 4) {
                    PreviewActionButton(
                        icon: "doc.on.doc",
                        label: "Copy",
                        action: onCopy,
                    )

                    if preview.savedURL != nil {
                        PreviewActionButton(
                            icon: "folder",
                            label: "Open",
                            action: onOpen,
                        )
                    }

                    PreviewActionButton(
                        icon: "trash",
                        label: "Delete",
                        tint: .red,
                        action: onDelete,
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(Layout.padding)
        .glassEffect(in: RoundedRectangle(cornerRadius: Layout.cornerRadius + 4))
        .shadow(color: .black.opacity(0.3), radius: Layout.shadowRadius, y: 4)
        .onHover { hovering in
            isHovering = hovering
            onHoverChanged(hovering)
        }
        .animation(.spring(duration: 0.2), value: isHovering)
        .onTapGesture {
            if let url = preview.savedURL {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            onDismiss()
        }
    }

}

// MARK: - Preview Action Button

private struct PreviewActionButton: View {
    let icon: String
    let label: String
    var tint: Color?
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHovering ? (tint ?? .primary) : .secondary)
                .frame(width: 24, height: 24)
                .background(isHovering ? (tint ?? Color.appAccentColor).opacity(0.15) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(label)
        .onHover { isHovering = $0 }
    }
}
