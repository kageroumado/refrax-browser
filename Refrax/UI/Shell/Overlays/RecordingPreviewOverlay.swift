import SwiftUI

// MARK: - Recording Preview Overlay

/// Isolated overlay for recording previews.
///
/// Extracted to isolate observation of `RecordingCoordinator.currentPreview`
/// from the parent container. Recording state changes only rebuild this view.
struct RecordingPreviewOverlay: View {
    @Environment(RecordingCoordinator.self) private var recordingCoordinator

    var body: some View {
        Group {
            if let preview = recordingCoordinator.currentPreview {
                RecordingPreviewToast(
                    preview: preview,
                    onOpen: { recordingCoordinator.openPreview() },
                    onReveal: { recordingCoordinator.revealPreviewInFinder() },
                    onDismiss: { recordingCoordinator.dismissPreview() },
                )
                .padding(.bottom, 20)
                .padding(.trailing, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: recordingCoordinator.currentPreview?.id)
    }
}
