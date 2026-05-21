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
    private var mediaState: MediaState {
        let pages = tab.pages.compactMap { env.pagePool.existingPage(for: $0) }
        return MediaState(pages: pages)
    }

    private enum Constants {
        static let iconSize: CGFloat = 10
        static let buttonSize: CGFloat = 16
        static let spacing: CGFloat = 2
    }

    // MARK: - Call Page State

    /// Per-page call state for call indicator grouping.
    ///
    /// Triggers only when a single page has audio + (mic OR camera) simultaneously.
    struct CallPageState {
        let pageIndex: Int
        let hasAudio: Bool
        let isAudioMuted: Bool
        let hasMic: Bool
        let isMicMuted: Bool
        let hasCamera: Bool
        let isCameraMuted: Bool
    }

    // MARK: - Media State

    /// Consolidated media state computed in a single pass over all pages.
    ///
    /// Multi-page consolidation: OR for activity flags, AND for muted states.
    private struct MediaState {
        let isPlayingAudio: Bool
        let isAudioMuted: Bool
        let isInFullscreen: Bool
        let isMediaSuspended: Bool
        let isCameraActive: Bool
        let isCameraMuted: Bool
        let isMicrophoneActive: Bool
        let isMicrophoneMuted: Bool
        let needsReload: Bool
        let isUnresponsive: Bool
        let recentlyCrashed: Bool
        let hasReflectedWindows: Bool
        let isLoading: Bool

        /// Per-page call state for call indicator grouping.
        let callPageStates: [CallPageState]

        init(pages: [WebPage]) {
            guard !pages.isEmpty else {
                self.isPlayingAudio = false
                self.isAudioMuted = false
                self.isInFullscreen = false
                self.isMediaSuspended = false
                self.isCameraActive = false
                self.isCameraMuted = false
                self.isMicrophoneActive = false
                self.isMicrophoneMuted = false
                self.needsReload = false
                self.isUnresponsive = false
                self.recentlyCrashed = false
                self.hasReflectedWindows = false
                self.isLoading = false
                self.callPageStates = []
                return
            }

            var playingAudio = false
            var allMuted = true // Special: allSatisfy logic
            var inFullscreen = false
            var mediaSuspended = false
            var cameraActive = false
            var cameraMuted = false
            var micActive = false
            var micMuted = false
            var unloaded = false
            var unresponsive = false
            var crashed = false
            var reflected = false
            var loading = false
            var callStates: [CallPageState] = []

            for (index, page) in pages.enumerated() {
                let pageHasAudio = page.audioState.isPlayingAudio
                let pageAudioMuted = page.audioState.isMuted
                let pageHasMic = page.isMicrophoneActive || page.isMicrophoneMuted
                let pageMicMuted = page.isMicrophoneMuted
                let pageHasCamera = page.isCameraActive || page.isCameraMuted
                let pageCameraMuted = page.isCameraMuted

                playingAudio = playingAudio || pageHasAudio
                allMuted = allMuted && pageAudioMuted
                inFullscreen = inFullscreen || page.isInFullscreen
                mediaSuspended = mediaSuspended || page.isMediaSuspended
                cameraActive = cameraActive || page.isCameraActive
                cameraMuted = cameraMuted || page.isCameraMuted
                micActive = micActive || page.isMicrophoneActive
                micMuted = micMuted || page.isMicrophoneMuted
                unloaded = unloaded || page.needsReload
                unresponsive = unresponsive || page.isUnresponsive
                crashed = crashed || page.recentlyCrashed
                reflected = reflected || page.hasReflectedWindows
                loading = loading || page.isLoading

                // Check for call state: audio + (mic OR camera) on same page
                if pageHasAudio, pageHasMic || pageHasCamera {
                    callStates.append(
                        CallPageState(
                            pageIndex: index,
                            hasAudio: pageHasAudio,
                            isAudioMuted: pageAudioMuted,
                            hasMic: pageHasMic,
                            isMicMuted: pageMicMuted,
                            hasCamera: pageHasCamera,
                            isCameraMuted: pageCameraMuted,
                        ),
                    )
                }
            }

            self.isPlayingAudio = playingAudio
            self.isAudioMuted = allMuted
            self.isInFullscreen = inFullscreen
            self.isMediaSuspended = mediaSuspended
            self.isCameraActive = cameraActive
            // Camera is "muted" only if not active but was muted
            self.isCameraMuted = !cameraActive && cameraMuted
            self.isMicrophoneActive = micActive
            // Mic is "muted" only if not active but was muted
            self.isMicrophoneMuted = !micActive && micMuted
            self.needsReload = unloaded
            self.isUnresponsive = unresponsive
            self.recentlyCrashed = crashed
            self.hasReflectedWindows = reflected
            self.isLoading = loading
            self.callPageStates = callStates
        }
    }

    /// Web pages for button actions (mute, pause, etc.).
    private var webPages: [WebPage] {
        tab.pages.compactMap { env.pagePool.existingPage(for: $0) }
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
        !mediaState.callPageStates.isEmpty
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
        mediaState.needsReload &&
            !mediaState.isLoading &&
            tab.createdAt.timeIntervalSinceNow < -0.5
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
                // Option+Click: Pause all media (record pause to keep in panel)
                Task {
                    for (pageID, webPage) in pagesWithIDs {
                        env.mediaControlsManager.recordManualPause(for: pageID)
                        await webPage.pauseAllMediaPlayback()
                        // Refresh playback state so media panel updates immediately
                        await webPage.refreshPlaybackState()
                    }
                }
            } else {
                // Click: Toggle mute (stays in panel, still playing)
                let shouldMute = !state.isAudioMuted
                for webPage in webPages {
                    webPage.setAudioMuted(shouldMute)
                }
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

    private func audioIndicatorIcon(_ state: MediaState) -> String {
        if isOptionPressed { return "pause.fill" }
        if state.isAudioMuted { return "speaker.slash.fill" }
        return "speaker.wave.2.fill"
    }

    private func audioIndicatorColor(_ state: MediaState) -> Color {
        state.isAudioMuted ? .primary : .secondary
    }

    private func audioIndicatorHelp(_ state: MediaState) -> String {
        if isOptionPressed { return "Pause Media\nOption+Click to pause playback" }
        if state.isAudioMuted { return "Audio Muted\nClick to unmute" }
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
            Task {
                let shouldMute = state.isCameraActive
                await withTaskGroup(of: Void.self) { group in
                    for webPage in webPages {
                        group.addTask { await webPage.setCameraMuted(shouldMute) }
                    }
                }
            }
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
            Task {
                let shouldMute = state.isMicrophoneActive
                await withTaskGroup(of: Void.self) { group in
                    for webPage in webPages {
                        group.addTask { await webPage.setMicrophoneMuted(shouldMute) }
                    }
                }
            }
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
            for webPage in webPages {
                webPage.backingWebView.reload()
            }
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
            for webPage in webPages {
                webPage.backingWebView.reload()
            }
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
            for webPage in webPages where webPage.needsReload {
                webPage.backingWebView.reload()
            }
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
            callStates: mediaState.callPageStates,
            webPages: webPages,
            pagesWithIDs: pagesWithIDs,
        )
    }
}
