import SwiftUI

// MARK: - Screenshot Preview Overlay

/// Isolated overlay for screenshot previews.
///
/// Extracted to isolate observation of `ScreenshotCoordinator.currentPreview`
/// from the parent container. Screenshot state changes only rebuild this view.
struct ScreenshotPreviewOverlay: View {
    @Environment(ScreenshotCoordinator.self) private var screenshotCoordinator
    @Environment(WindowState.self) private var windowState

    var body: some View {
        Group {
            if let preview = screenshotCoordinator.currentPreview {
                ScreenshotPreviewToast(
                    preview: preview,
                    onCopy: { screenshotCoordinator.copyPreviewToClipboard() },
                    onOpen: { screenshotCoordinator.openPreview() },
                    onDelete: { screenshotCoordinator.deleteScreenshot() },
                    onDismiss: { screenshotCoordinator.dismissPreview() },
                    onHoverChanged: { hovering in
                        windowState.webViewsShouldIgnoreAllEvents = hovering
                        if hovering {
                            screenshotCoordinator.pauseAutoDismiss()
                        } else {
                            screenshotCoordinator.resumeAutoDismiss()
                        }
                    },
                )
                .padding(.bottom, 20)
                .padding(.trailing, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: screenshotCoordinator.currentPreview?.id)
    }
}
