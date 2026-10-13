import AppKit
import SwiftUI
import WebKit

// MARK: - Tab Status Indicators

/// Displays status indicators for a tab showing media, capture, and process state.
///
/// Display order (left to right):
/// Media, Fullscreen, Reflected, Health, Archive, Unread, Unsaved Form
///
/// Audio indicator: Click to mute/unmute, Option+Click to pause playback.
struct TabStatusIndicators: View {
    @Environment(SidebarCellEnvironment.self) private var env

    /// The tab to display indicators for.
    let tab: Tab

    /// Consolidated media/process state computed from web pages.
    ///
    /// Computed directly in the view body so SwiftUI's observation system
    /// tracks changes to the underlying `@Observable` WebPage properties.
    private var mediaState: TabMediaState {
        control.state
    }

    private var control: TabMediaControl {
        TabMediaControl(tab: tab, pagePool: env.pagePool, mediaControls: env.mediaControlsManager)
    }

    private enum Constants {
        static let iconSize: CGFloat = 10
        static let buttonSize: CGFloat = 16
        static let spacing: CGFloat = 2
    }

    /// Web pages for button actions (fullscreen, reflected windows).
    private var webPages: [WebPage] {
        control.pages
    }

    /// Helper to get (pageID, WebPage) pairs for MediaControlsManager calls.
    private var pagesWithIDs: [(TabPage.ID, WebPage)] {
        tab.pages.compactMap { tabPage in
            guard let webPage = env.pagePool.existingPage(for: tabPage) else { return nil }
            return (tabPage.id, webPage)
        }
    }

    // MARK: - Computed Visibility

    private var isOptionPressed: Bool {
        env.modifierKeysState.isOptionPressed
    }

    private var showCallIndicator: Bool {
        mediaState.isInCall
    }

    private var showAudioIndicator: Bool {
        !showCallIndicator && mediaState.isPlayingAudio
    }

    private var showFullscreenIndicator: Bool {
        mediaState.isInFullscreen
    }

    private var showSuspendedIndicator: Bool {
        mediaState.isMediaSuspended
    }

    private var showCameraIndicator: Bool {
        !showCallIndicator && (mediaState.isCameraActive || mediaState.isCameraMuted)
    }

    private var showMicrophoneIndicator: Bool {
        !showCallIndicator && (mediaState.isMicrophoneActive || mediaState.isMicrophoneMuted)
    }

    /// Whether to show the suspended/unloaded indicator.
    ///
    /// Guards prevent false positives during WebView creation:
    /// needs reload, not loading, and tab existed for >500ms.
    private var showUnloadedIndicator: Bool {
        mediaState.isSuspended(createdAt: tab.createdAt)
    }

    private var showUnresponsiveIndicator: Bool {
        mediaState.isUnresponsive
    }

    private var showCrashedIndicator: Bool {
        mediaState.recentlyCrashed
    }

    private var showReflectedIndicator: Bool {
        mediaState.hasReflectedWindows
    }

    // MARK: - Tab State Indicators

    private var showUnreadIndicator: Bool {
        tab.isUnread
    }

    /// Archive warning (pinned and live favorite tabs are exempt).
    private var showArchiveWarningIndicator: Bool {
        !tab.isPinned && !tab.isLiveFavorite && env.autoArchiveManager.isAtArchiveThreshold(tab)
    }

    private var showUnsavedFormIndicator: Bool {
        env.settings.showUnsavedFormIndicator && webPages.contains { $0.hasUnsavedFormData }
    }

    var body: some View {
        HStack(spacing: Constants.spacing) {
            // Media indicators (leftmost)
            if showCallIndicator {
                callIndicator
            }

            if showAudioIndicator {
                audioIndicator
            }

            if showSuspendedIndicator {
                suspendedIndicator
            }

            if showCameraIndicator {
                cameraIndicator
            }

            if showMicrophoneIndicator {
                microphoneIndicator
            }

            // Fullscreen/PiP
            if showFullscreenIndicator {
                fullscreenIndicator
            }

            // Reflected windows
            if showReflectedIndicator {
                reflectedIndicator
            }

            // Health indicators (crashed, unresponsive, suspended)
            if showCrashedIndicator {
                crashedIndicator
            }

            if showUnresponsiveIndicator {
                unresponsiveIndicator
            }

            if showUnloadedIndicator {
                unloadedIndicator
            }

            // Archive warning
            if showArchiveWarningIndicator {
                archiveWarningIndicator
            }

            // Unread indicator
            if showUnreadIndicator {
                unreadIndicator
            }

            // Unsaved form indicator
            if showUnsavedFormIndicator {
                unsavedFormIndicator
            }
        }
        .padding(.leading, Refrax.Constants.Spacing.xSmall)
    }

    // MARK: - Unread Indicator

    private var unreadIndicator: some View {
        Button {
            tab.isUnread = false
            tab.unreadFromBadge = false
        } label: {
            Image(systemName: "circlebadge.fill")
                .font(.system(size: Constants.iconSize, weight: .medium))
                .foregroundStyle(Color.appAccentColor)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Unread Tab\nClick to mark as read")
        .accessibilityLabel("Unread Tab")
        .accessibilityHint("Click to mark as read")
    }

    // MARK: - Archive Warning Indicator

    private var archiveWarningIndicator: some View {
        Button {
            // Activate the tab to reset its lastAccessed timestamp
            if let windowState = env.windowManager.activeWindowController?.windowState {
                env.tabManager.setActiveTab(tab, in: windowState)
            }
        } label: {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: Constants.iconSize, weight: .medium))
                .foregroundStyle(.orange)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Archive Warning\nThis tab will be archived soon")
        .accessibilityLabel("Archive Warning")
        .accessibilityHint("This tab will be archived soon. Click to keep it active.")
    }

    // MARK: - Unsaved Form Indicator

    private var unsavedFormIndicator: some View {
        Image(systemName: "pencil.circle.fill")
            .font(.system(size: Constants.iconSize, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: Constants.buttonSize, height: Constants.buttonSize)
            .help("Unsaved Form Data\nThis tab won't be auto-archived")
            .accessibilityLabel("Unsaved Form Data")
    }

    // MARK: - Audio Indicator

    private var audioIndicator: some View {
        let state = mediaState
        return Button {
            if NSEvent.modifierFlags.contains(.option) {
                control.pauseMedia()
            } else {
                control.setMuted(!state.isAudioMuted)
            }
        } label: {
            Image(systemName: audioIndicatorIcon(state))
                .font(.system(size: Constants.iconSize, weight: .medium))
                .foregroundStyle(audioIndicatorColor(state))
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(audioIndicatorHelp(state))
        .accessibilityLabel(audioIndicatorHelp(state))
    }

    private func audioIndicatorIcon(_ state: TabMediaState) -> String {
        if isOptionPressed {
            return "pause.fill"
        }
        if state.isAudioMuted {
            return "speaker.slash.fill"
        }
        return "speaker.wave.2.fill"
    }

    private func audioIndicatorColor(_ state: TabMediaState) -> Color {
        state.isAudioMuted ? .primary : .secondary
    }

    private func audioIndicatorHelp(_ state: TabMediaState) -> String {
        if isOptionPressed {
            return "Pause Media\nOption+Click to pause playback"
        }
        if state.isAudioMuted {
            return "Audio Muted\nClick to unmute"
        }
        return "Playing Audio\nClick to mute"
    }

    // MARK: - Fullscreen Indicator

    private var fullscreenIndicator: some View {
        Button {
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for webPage in webPages {
                        group.addTask { await webPage.closeAllMediaPresentations() }
                    }
                }
            }
        } label: {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: Constants.iconSize, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("In Fullscreen\nClick to exit")
        .accessibilityLabel("In Fullscreen")
        .accessibilityHint("Click to exit")
    }

    // MARK: - Suspended Indicator

    private var suspendedIndicator: some View {
        Button {
            Task {
                for (pageID, webPage) in pagesWithIDs {
                    // Clear the manual pause record before resuming
                    env.mediaControlsManager.clearManualPause(for: pageID)
                    await webPage.setMediaSuspended(false)
                }
            }
        } label: {
            Image(systemName: "pause.fill")
                .font(.system(size: Constants.iconSize, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Media Paused\nClick to resume")
        .accessibilityLabel("Media Paused")
        .accessibilityHint("Click to resume")
    }

    // MARK: - Camera Indicator

    private var cameraIndicator: some View {
        let state = mediaState
        return Button {
            control.setCameraMuted(state.isCameraActive)
        } label: {
            Image(systemName: state.isCameraMuted ? "video.slash.fill" : "video.fill")
                .font(.system(size: Constants.iconSize, weight: .medium))
                .foregroundColor(state.isCameraMuted ? .red : .green)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(
            state.isCameraMuted ? "Camera Disabled\nClick to enable" : "Camera Active\nClick to disable",
        )
        .accessibilityLabel(state.isCameraMuted ? "Camera Disabled" : "Camera Active")
        .accessibilityHint(state.isCameraMuted ? "Click to enable" : "Click to disable")
    }

    // MARK: - Microphone Indicator

    private var microphoneIndicator: some View {
        let state = mediaState
        return Button {
            control.setMicrophoneMuted(state.isMicrophoneActive)
        } label: {
            Image(systemName: state.isMicrophoneMuted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: Constants.iconSize, weight: .medium))
                .foregroundColor(state.isMicrophoneMuted ? .red : .orange)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(
            state.isMicrophoneMuted
                ? "Microphone Muted\nClick to unmute" : "Microphone Active\nClick to mute",
        )
        .accessibilityLabel(state.isMicrophoneMuted ? "Microphone Muted" : "Microphone Active")
        .accessibilityHint(state.isMicrophoneMuted ? "Click to unmute" : "Click to mute")
    }

    // MARK: - Process State Indicators

    private var crashedIndicator: some View {
        Button {
            control.reload()
        } label: {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: Constants.iconSize, weight: .medium))
                .foregroundStyle(.yellow)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Page Crashed\nClick to reload")
        .accessibilityLabel("Page Crashed")
        .accessibilityHint("Click to reload")
    }

    private var unresponsiveIndicator: some View {
        Button {
            control.reload()
        } label: {
            Image(systemName: "hourglass")
                .font(.system(size: Constants.iconSize, weight: .medium))
                .foregroundStyle(.orange)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Page Unresponsive\nClick to reload")
        .accessibilityLabel("Page Unresponsive")
        .accessibilityHint("Click to reload")
    }

    private var unloadedIndicator: some View {
        Button {
            control.wake()
        } label: {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: Constants.iconSize, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Tab Suspended\nClick to wake")
        .accessibilityLabel("Tab Suspended")
        .accessibilityHint("Click to wake")
    }

    // MARK: - Reflected Window Indicator

    private var reflectedIndicator: some View {
        Button {
            for webPage in webPages {
                webPage.bringReflectedWindowsToFront()
            }
        } label: {
            Image(systemName: "rectangle.inset.filled.on.rectangle")
                .font(.system(size: Constants.iconSize, weight: .medium))
                .foregroundStyle(.blue)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Reflected Window\nClick to bring to front")
        .accessibilityLabel("Reflected Window")
        .accessibilityHint("Click to bring to front")
    }

    // MARK: - Call Indicator

    private var callIndicator: some View {
        CallIndicatorView(
            callStates: mediaState.callPages,
            webPages: webPages,
            pagesWithIDs: pagesWithIDs,
        )
    }
}
