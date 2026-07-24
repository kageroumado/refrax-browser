import SwiftUI

/// Dynamic footer buttons for the compact sidebar.
///
/// Shows media, downloads, and update buttons in a vertical stack,
/// each visible only when its associated state is active.
struct CompactFooterControls: View {
    @Environment(Sidebar.MediaControlsManager.self) private var mediaControlsManager
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(AppUpdateManager.self) private var appUpdateManager
    @Environment(PageReminderManager.self) private var reminderManager

    @State private var showMediaPopover = false
    @State private var showDownloadsPopover = false
    @State private var showRemindersPopover = false
    @State private var showUpdateSheet = false

    private typealias Layout = CompactSidebarLayout.Footer

    private var hasAnyButton: Bool {
        mediaControlsManager.hasActiveMedia
            || downloadManager.hasActiveDownloads
            || reminderManager.hasPendingReminders
            || isUpdatePhaseVisible
    }

    private var isUpdatePhaseVisible: Bool {
        switch appUpdateManager.phase {
        case .downloading, .readyToInstall, .failed: true
        default: false
        }
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

                updateButton
            }
            .sheet(isPresented: $showUpdateSheet) {
                UpdateAvailableView()
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

    // MARK: - Update Button

    @ViewBuilder
    private var updateButton: some View {
        switch appUpdateManager.phase {
        case .downloading(let progress):
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: Layout.buttonSize, height: Layout.buttonSize)
                .overlay {
                    ProgressView(value: progress)
                        .progressViewStyle(.circular)
                        .scaleEffect(0.4)
                }

        case .readyToInstall:
            Button {
                showUpdateSheet = true
            } label: {
                Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.green)
                    .frame(width: Layout.buttonSize, height: Layout.buttonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Restart to update")

        case .failed:
            Button {
                appUpdateManager.showFailedPanel = true
            } label: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.yellow)
                    .frame(width: Layout.buttonSize, height: Layout.buttonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Update failed")

        default:
            EmptyView()
        }
    }
}
