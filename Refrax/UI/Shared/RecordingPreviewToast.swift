import SwiftUI

/// Recording preview thumbnail displayed after capture completes.
///
/// Appears in the bottom-right corner like the macOS system screenshot preview.
/// Shows video thumbnail with duration badge. Provides quick actions to open
/// or dismiss. Auto-dismisses after 8 seconds if not interacted with.
struct RecordingPreviewToast: View {
    let preview: RecordingCoordinator.RecordingPreview
    let onOpen: () -> Void
    let onReveal: () -> Void
    let onDismiss: () -> Void

    @State private var isHovering = false
    @State private var isDragging = false
    @State private var dragOffset: CGSize = .zero

    private enum Layout {
        static let imageSize: CGFloat = 140
        static let cornerRadius: CGFloat = 8
        static let shadowRadius: CGFloat = 12
        static let padding: CGFloat = 8
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            // Preview image with video badge
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: preview.thumbnailImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: Layout.imageSize, maxHeight: Layout.imageSize)
                    .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: Layout.cornerRadius)
                            .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                    }

                // Duration badge
                durationBadge
            }

            // Action buttons (visible on hover)
            if isHovering {
                HStack(spacing: 4) {
                    RecordingPreviewActionButton(
                        icon: "play.fill",
                        label: "Play",
                        action: onOpen,
                    )

                    RecordingPreviewActionButton(
                        icon: "folder",
                        label: "Reveal in Finder",
                        action: onReveal,
                    )

                    RecordingPreviewActionButton(
                        icon: "xmark",
                        label: "Close",
                        action: onDismiss,
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .padding(Layout.padding)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Layout.cornerRadius + 4))
        .shadow(color: .black.opacity(0.3), radius: Layout.shadowRadius, y: 4)
        .offset(dragOffset)
        .gesture(dragGesture)
        .onHover { isHovering = $0 }
        .animation(.spring(duration: 0.2), value: isHovering)
        .animation(.spring(duration: 0.3), value: dragOffset)
        .onTapGesture {
            onOpen()
        }
    }

    /// Duration badge showing video length.
    private var durationBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "video.fill")
                .font(.system(size: 9, weight: .semibold))

            Text(preview.formattedDuration)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 4))
        .padding(6)
    }

    /// Drag gesture to swipe away the preview.
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                isDragging = true
                // Only allow dragging right (to dismiss off-screen)
                if value.translation.width > 0 {
                    dragOffset = CGSize(width: value.translation.width, height: 0)
                }
            }
            .onEnded { value in
                isDragging = false
                // Dismiss if dragged far enough
                if value.translation.width > 80 {
                    withAnimation(.easeOut(duration: 0.2)) {
                        dragOffset = CGSize(width: 300, height: 0)
                    } completion: {
                        onDismiss()
                    }
                } else {
                    dragOffset = .zero
                }
            }
    }
}

// MARK: - Recording Preview Action Button

private struct RecordingPreviewActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isHovering ? .primary : .secondary)
                .frame(width: 24, height: 24)
                .background(isHovering ? Color.appAccentColor.opacity(0.15) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(label)
        .onHover { isHovering = $0 }
    }
}
