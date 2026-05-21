import SwiftUI

/// Downloads button for the sidebar bottom bar.
///
/// Shows download progress using a variable SF Symbol. Visible when:
/// - Downloads are in progress, or
/// - Within 15 seconds after all downloads completed
///
/// Clicking opens the downloads detail tray.
struct DownloadsButton: View {
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(WindowState.self) private var windowState

    /// Timer that fires 15 seconds after downloads complete.
    @State private var hideTimer: Timer?

    /// Whether the button should remain visible after downloads complete.
    @State private var showAfterCompletion = false

    /// Tracks the previous active download count to detect completion.
    @State private var previousActiveCount = 0

    private var shouldShow: Bool {
        downloadManager.hasActiveDownloads || showAfterCompletion
    }

    private var progress: Double {
        let aggregate = downloadManager.aggregateProgress
        // aggregateProgress is -1 when indeterminate, 0-1 when determinate
        if aggregate < 0 {
            return 0.5 // Indeterminate: show half-filled
        }
        return aggregate
    }

    private var isActive: Bool {
        windowState.detailTrayMode == .downloads
    }

    var body: some View {
        if shouldShow {
            Button {
                windowState.toggleDetailTray(.downloads)
            } label: {
                Image(systemName: "arrow.down.circle", variableValue: progress)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(isActive ? Color.appAccentColor : .primary)
                    .symbolEffect(.pulse, options: .repeating, isActive: downloadManager.hasActiveDownloads)
                    .frame(width: Layout.buttonSize, height: Layout.buttonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .adaptiveBackground(.subtle, in: RoundedRectangle(cornerRadius: Layout.buttonCornerRadius))
            .accessibilityIdentifier("sidebar-downloads")
            .accessibilityLabel(accessibilityLabel)
            .help("Downloads")
            .onChange(of: downloadManager.activeDownloadCount) { oldValue, newValue in
                handleDownloadCountChange(from: oldValue, to: newValue)
            }
            .onDisappear {
                hideTimer?.invalidate()
                hideTimer = nil
            }
        }
    }

    private var accessibilityLabel: String {
        let count = downloadManager.activeDownloadCount
        if count == 0 {
            return "Downloads"
        } else if count == 1 {
            return "1 download in progress"
        } else {
            return "\(count) downloads in progress"
        }
    }

    private func handleDownloadCountChange(from oldValue: Int, to newValue: Int) {
        // New download started - reset timer and ensure visible
        if newValue > oldValue {
            hideTimer?.invalidate()
            hideTimer = nil
            showAfterCompletion = true
        }

        // All downloads completed - start 15 second timer
        if oldValue > 0, newValue == 0 {
            showAfterCompletion = true
            hideTimer?.invalidate()
            hideTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { _ in
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showAfterCompletion = false
                    }
                }
            }
        }
    }
}

// MARK: - Layout Constants

private enum Layout {
    static let buttonSize: CGFloat = 32
    static let buttonCornerRadius: CGFloat = 16
}
