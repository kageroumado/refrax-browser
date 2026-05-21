import SwiftUI

/// Reader mode overlay that slides in from the bottom, Safari-style.
///
/// This view overlays the web content when reader mode is active,
/// presenting the extracted article in a clean, focused format.
/// The transition animates from bottom to top, matching Safari's behavior.
struct ReaderOverlayView: View {
    let article: ExtractedArticle
    let tabID: UUID

    @Environment(ReaderModeManager.self) private var readerManager
    @Environment(\.colorScheme) private var colorScheme

    private enum Layout {
        static let cornerRadius: CGFloat = 12
        static let shadowRadius: CGFloat = 16
        static let horizontalPadding: CGFloat = 0
    }

    private var preferences: ReaderPreferences {
        readerManager.preferences
    }

    var body: some View {
        VStack(spacing: 0) {
            // Rounded top corners with subtle shadow
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .fill(preferences.theme.backgroundColor(for: colorScheme))
                .shadow(
                    color: .black.opacity(0.15),
                    radius: Layout.shadowRadius,
                    y: -4,
                )
                .overlay(alignment: .top) {
                    // Drag indicator at top
                    dragIndicator
                        .padding(.top, 8)
                }
                .overlay {
                    readerContent
                        .clipShape(
                            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous),
                        )
                }
        }
        .padding(.horizontal, Layout.horizontalPadding)
    }

    // MARK: - Drag Indicator

    private var dragIndicator: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 36, height: 5)
    }

    // MARK: - Reader Content

    private var readerContent: some View {
        ReaderView(article: article, tabID: tabID)
    }
}

// MARK: - Animated Overlay Container

/// Container that manages the reader overlay with slide animation.
///
/// Use this in WebViewContainer to show/hide the reader mode overlay
/// with a smooth slide-from-bottom transition.
struct ReaderOverlayContainer: View {
    let tabID: UUID

    @Environment(ReaderModeManager.self) private var readerManager

    private var isActive: Bool {
        readerManager.isReaderActive(for: tabID)
    }

    private var article: ExtractedArticle? {
        readerManager.activeArticle(for: tabID)
    }

    var body: some View {
        ZStack {
            if let article, isActive {
                ReaderOverlayView(article: article, tabID: tabID)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.15), value: isActive)
    }
}
