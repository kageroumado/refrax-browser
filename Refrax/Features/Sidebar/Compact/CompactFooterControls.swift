import SwiftUI

/// Dynamic footer buttons for the compact sidebar.
///
/// Shows media, downloads, and reminder buttons in a vertical stack,
/// each visible only when its associated state is active.
struct CompactFooterControls: View {
    @Environment(Sidebar.MediaControlsManager.self) private var mediaControlsManager
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(PageReminderManager.self) private var reminderManager

    @State private var showMediaPopover = false
    @State private var showDownloadsPopover = false
    @State private var showRemindersPopover = false

    private typealias Layout = CompactSidebarLayout.Footer

    private var hasAnyButton: Bool {
        mediaControlsManager.hasActiveMedia
            || downloadManager.hasActiveDownloads
            || reminderManager.hasPendingReminders
    }

    var body: some View {
        if hasAnyButton {
            VStack(spacing: Layout.spacing) {
                if mediaControlsManager.hasActiveMedia {
                    mediaButton
                }

                if downloadManager.hasActiveDownloads {
                    downloadsButton
                }

                if reminderManager.hasPendingReminders {
                    remindersButton
                }
            }
        }
    }

    // MARK: - Media Button

    private var mediaButton: some View {
        Button {
            showMediaPopover = true
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: Layout.buttonSize, height: Layout.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Media Controls")
        .hoverFillAction(
            isActive: $showMediaPopover,
            delay: CompactSidebarLayout.longHoverDelay,
            fillColor: .secondary.opacity(CompactSidebarLayout.Icon.backgroundOpacity),
            clipShape: SquircleShape(),
            size: Layout.buttonSize,
        ) {
            showMediaPopover = true
        }
        .arrowlessPopover(isPresented: $showMediaPopover, arrowEdge: .trailing) {
            MediaControlsPanel()
                .frame(width: 280)
        }
    }

    // MARK: - Downloads Button

    private var downloadsButton: some View {
        Button {
            showDownloadsPopover = true
        } label: {
            Image(systemName: "arrow.down.circle", variableValue: downloadManager.aggregateProgress >= 0 ? downloadManager.aggregateProgress : 0.5)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .symbolEffect(.pulse, options: .repeating, isActive: downloadManager.hasActiveDownloads)
                .frame(width: Layout.buttonSize, height: Layout.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Downloads")
        .arrowlessPopover(isPresented: $showDownloadsPopover, arrowEdge: .trailing) {
            DownloadsView()
                .frame(width: 280, height: 400)
        }
    }

    // MARK: - Reminders Button

    private var remindersButton: some View {
        Button {
            showRemindersPopover = true
        } label: {
            Image(systemName: "bell.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: Layout.buttonSize, height: Layout.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Page Reminders")
        .arrowlessPopover(isPresented: $showRemindersPopover, arrowEdge: .trailing) {
            RemindersWidgetPopover()
                .environment(reminderManager)
        }
    }
}
