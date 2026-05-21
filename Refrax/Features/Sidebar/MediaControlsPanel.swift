import SwiftUI

// MARK: - Media Controls Button

/// Unified trigger button for the media controls panel in the sidebar bottom bar.
///
/// Shows a single button with priority-based icon selection following Apple's
/// privacy-first approach:
///
/// ## Icon Priority (Call Active)
///
/// 1. **Camera active** → green `video.fill`
/// 2. **Camera muted** → gray `video.slash.fill`
/// 3. **Mic active** → orange `mic.fill`
/// 4. **Mic muted** → gray `mic.slash.fill`
/// 5. **Audio only** → gray `speaker.wave.2.fill`
///
/// ## Icon (Media Only, No Call)
///
/// - `speaker.wave.2.fill` in gray
///
/// The button color indicates the active capture device (green for camera,
/// orange for mic) to unify the visual language with tab indicators.
struct MediaControlsButton: View {
    @Environment(Sidebar.MediaControlsManager.self) private var mediaControlsManager
    @Environment(WebPagePool.self) private var pagePool

    /// Aggregated call state across all active sections.
    private var callState: (hasCamera: Bool, cameraMuted: Bool, hasMic: Bool, micMuted: Bool) {
        var hasCamera = false
        var cameraMuted = true
        var hasMic = false
        var micMuted = true

        for section in mediaControlsManager.activeSections where section.type.isCall {
            if section.webPage.isCameraActive || section.webPage.isCameraMuted {
                hasCamera = true
                if section.webPage.isCameraActive {
                    cameraMuted = false
                }
            }
            if section.webPage.isMicrophoneActive || section.webPage.isMicrophoneMuted {
                hasMic = true
                if section.webPage.isMicrophoneActive {
                    micMuted = false
                }
            }
        }

        return (hasCamera, cameraMuted, hasMic, micMuted)
    }

    var body: some View {
        let (icon, color) = buttonIconAndColor()

        Button {
            mediaControlsManager.togglePanel()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(color)
                .frame(width: Layout.buttonSize, height: Layout.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .adaptiveBackground(.subtle, in: RoundedRectangle(cornerRadius: Layout.buttonCornerRadius))
        .accessibilityIdentifier("sidebar-media-controls")
        .accessibilityLabel(accessibilityLabel)
        .help(helpText)
    }

    /// Determines the icon and color based on priority.
    ///
    /// Uses semantic colors: green for camera, orange for mic, red for muted.
    private func buttonIconAndColor() -> (String, Color) {
        // Check for active calls first (priority-based)
        if mediaControlsManager.hasActiveCalls {
            let state = callState

            // Camera has highest priority
            if state.hasCamera {
                if state.cameraMuted {
                    return ("video.slash.fill", .red)
                } else {
                    return ("video.fill", .green)
                }
            }

            // Mic has second priority
            if state.hasMic {
                if state.micMuted {
                    return ("mic.slash.fill", .red)
                } else {
                    return ("mic.fill", .orange)
                }
            }
        }

        // Media only (no active calls) - speaker icon
        return ("speaker.wave.2.fill", .secondary)
    }

    private var accessibilityLabel: String {
        if mediaControlsManager.hasActiveCalls {
            return "Call Controls"
        }
        return "Media Controls"
    }

    private var helpText: String {
        if mediaControlsManager.hasActiveCalls {
            let state = callState
            if state.hasCamera, !state.cameraMuted {
                return "Camera is active"
            }
            if state.hasMic, !state.micMuted {
                return "Microphone is active"
            }
            return "Call in progress"
        }
        return "Media playing"
    }
}

// MARK: - Media Controls Panel

/// Expandable panel showing media and call controls for all active tabs.
///
/// Appears in the sidebar's bottom bar, expanding upward when triggered.
/// Shows sections for each tab with media activity (audio, video, or calls).
struct MediaControlsPanel: View {
    @Environment(Sidebar.MediaControlsManager.self) private var mediaControlsManager
    @Environment(WindowState.self) private var windowState

    /// Tracks whether the user is hovering over the panel.
    @State private var isHovering = false

    var body: some View {
        Group {
            if mediaControlsManager.isExpanded {
                expandedPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onHover { hovering in
                        isHovering = hovering
                        if hovering {
                            mediaControlsManager.resetCollapseTimer()
                        }
                    }
            }
        }
        // These observers must be outside the `if` to fire when panel is closed
        .onChange(of: mediaControlsManager.activeSections.isEmpty) { _, isEmpty in
            if isEmpty {
                mediaControlsManager.closeIfNoActiveMedia()
            }
        }
        .onChange(of: mediaControlsManager.hasActiveMedia) { _, hasMedia in
            if hasMedia {
                mediaControlsManager.expandIfPinnedAndHasMedia()
            }
        }
    }

    private var expandedPanel: some View {
        // Sections - dynamic height, capped at max
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(mediaControlsManager.activeSections) { section in
                    MediaSectionView(section: section)
                }
            }
            .padding(8)
        }
        .frame(maxHeight: Layout.maxPanelHeight)
        .fixedSize(horizontal: false, vertical: true)
        .adaptiveBackground(.subtle, in: RoundedRectangle(cornerRadius: 10))
        // Floating pin button (like notification close button)
        .overlay(alignment: .topLeading) {
            floatingPinButton
        }
        .padding(.bottom, 4)
    }

    /// Floating pin button positioned outside the panel (like notification close).
    private var floatingPinButton: some View {
        Button {
            mediaControlsManager.togglePinned()
        } label: {
            Image(systemName: mediaControlsManager.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(mediaControlsManager.isPinned ? Color.appAccentColor : .primary)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .adaptiveBackground(.subtle, in: Circle())
        .opacity(isHovering || mediaControlsManager.isPinned ? 1.0 : 0.0)
        .transaction { transaction in
            transaction.animation = .easeInOut(duration: 0.15)
        }
        .offset(x: -6, y: -6)
        .help(mediaControlsManager.isPinned ? "Auto-reopen Off" : "Auto-reopen On")
    }
}

// MARK: - Media Section View

/// Individual section for a tab's media/call controls.
///
/// Compact layout with artwork spanning both rows:
/// ```
/// ┌────┐  Title (larger)
/// │Art │  domain · [controls]
/// └────┘
/// ```
///
/// ## Media Mode
/// Volume slider + play/pause (no headphones icon for regular media).
///
/// ## Call Mode
/// Headphones + mic + camera grouped together.
struct MediaSectionView: View {
    @Environment(Sidebar.MediaControlsManager.self) private var mediaControlsManager
    @Environment(WindowState.self) private var windowState
    @Environment(SpaceManager.self) private var spaceManager
    @Environment(TabManager.self) private var tabManager
    let section: MediaSection

    @State private var isExpanded = false

    private enum Constants {
        static let artworkSize: CGFloat = 40
        static let faviconSize: CGFloat = 32 // Larger favicon to fill the space better
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            artworkView

            VStack(alignment: .leading, spacing: 0) {
                Text(section.displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    subtitleView

                    Spacer(minLength: 4)

                    controlsRow
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityAction(.default) {
            mediaControlsManager.resetCollapseTimer()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
        .onTapGesture {
            mediaControlsManager.resetCollapseTimer()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
        .opacity(section.isFromCurrentSpace ? 1.0 : 0.7)
        .task {
            // Delay fetches to not block panel animation
            try? await Task.sleep(for: .milliseconds(200))
            // Refresh actual playback state (for accurate play/pause icon)
            await section.webPage.refreshPlaybackState()
            await section.webPage.refreshMediaSessionMetadata()
        }

        // Expanded details
        if isExpanded {
            expandedDetails
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Subtitle

    private var subtitleView: some View {
        Group {
            if let subtitle = section.displaySubtitle {
                Text(subtitle)
                    .foregroundStyle(.secondary)
            } else if section.type.isCall, mediaControlsManager.isSystemOutputMuted {
                Label("Can't hear", systemImage: "speaker.slash.fill")
                    .foregroundStyle(.orange)
            } else if !section.isFromCurrentSpace {
                Text("Other space")
                    .foregroundStyle(.tertiary)
            } else {
                Text(section.domain)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 10))
        .lineLimit(1)
    }

    // MARK: - Artwork

    private var artworkView: some View {
        Group {
            if let artworkURL = section.artworkURL {
                AsyncImage(url: artworkURL) { phase in
                    if case let .success(image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: Constants.artworkSize, height: Constants.artworkSize)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        faviconFallback
                    }
                }
            } else {
                faviconFallback
            }
        }
    }

    private var faviconFallback: some View {
        FaviconView(
            data: section.tab.activePage.faviconData,
            url: section.webPage.url,
            size: Constants.faviconSize,
        )
        .frame(width: Constants.artworkSize, height: Constants.artworkSize)
    }

    // MARK: - Controls

    /// Controls layout (call takes priority for `.both` type).
    private var controlsRow: some View {
        HStack(spacing: 2) {
            if section.type.isCall {
                callControls
            } else {
                mediaControls
            }
        }
    }

    private var mediaControls: some View {
        HStack(spacing: 2) {
            // Volume slider (compact)
            Slider(
                value: Binding(
                    get: { section.volume },
                    set: { newVolume in
                        mediaControlsManager.resetCollapseTimer()
                        mediaControlsManager.recordVolumeControl(for: section.id)
                        section.webPage.setVolume(newVolume)
                    },
                ),
                in: 0 ... 1,
            )
            .controlSize(.mini)
            .frame(width: 50)
            .tint(.secondary)

            // Play/Pause
            Button {
                mediaControlsManager.resetCollapseTimer()
                Task {
                    if section.isPlaying {
                        mediaControlsManager.recordManualPause(for: section.id)
                        // Use pauseAllMediaPlayback for reliable pausing (works even when
                        // media is muted from webpage controls)
                        await section.webPage.pauseAllMediaPlayback()
                    } else {
                        mediaControlsManager.clearManualPause(for: section.id)
                        _ = await section.webPage.playPredominantMedia()
                    }
                    // Refresh playback state to update the button icon immediately
                    await section.webPage.refreshPlaybackState()
                }
            } label: {
                Image(systemName: section.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(section.isPlaying ? "Pause" : "Play")
        }
    }

    /// Call controls - only show mic/camera if they're active or user-muted.
    /// Uses red for muted states (common pattern in Zoom/Meet/Teams).
    private var callControls: some View {
        HStack(spacing: 2) {
            // Headphones (audio mute) - always shown for calls
            Button {
                mediaControlsManager.resetCollapseTimer()
                section.webPage.setAudioMuted(!section.effectivelyMuted)
            } label: {
                Image(systemName: section.effectivelyMuted ? "headphones.slash" : "headphones")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(section.effectivelyMuted ? .red : .primary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(section.effectivelyMuted ? "Unmute Audio" : "Mute Audio")

            // Mic - only show if active or user-muted (not if never requested)
            if section.webPage.microphoneCaptureState != .none {
                Button {
                    mediaControlsManager.resetCollapseTimer()
                    Task {
                        await section.webPage.toggleMicrophoneMute()
                    }
                } label: {
                    Image(systemName: section.webPage.isMicrophoneActive ? "mic.fill" : "mic.slash.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(section.webPage.isMicrophoneActive ? .orange : .red)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(section.webPage.isMicrophoneActive ? "Mute Mic" : "Unmute Mic")
            }

            // Camera - only show if active or user-muted (not if never requested)
            if section.webPage.cameraCaptureState != .none {
                Button {
                    mediaControlsManager.resetCollapseTimer()
                    Task {
                        await section.webPage.toggleCameraMute()
                    }
                } label: {
                    Image(systemName: section.webPage.isCameraActive ? "video.fill" : "video.slash.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(section.webPage.isCameraActive ? .green : .red)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(section.webPage.isCameraActive ? "Turn Off Camera" : "Turn On Camera")
            }
        }
    }

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
                .padding(.horizontal, 6)

            // Page title
            if !section.webPage.title.isEmpty {
                Text(section.webPage.title)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.horizontal, 6)
            }

            // Quick actions
            HStack(spacing: 6) {
                Button {
                    mediaControlsManager.resetCollapseTimer()
                    navigateToTab()
                } label: {
                    Label("Go to Tab", systemImage: "arrow.right.circle")
                        .font(.system(size: 10))
                }

                if section.type.isMedia {
                    Button {
                        mediaControlsManager.resetCollapseTimer()
                        section.webPage.backingWebView._togglePictureInPicture()
                    } label: {
                        Label("PiP", systemImage: "pip.enter")
                            .font(.system(size: 10))
                    }
                    .disabled(!section.webPage.backingWebView._canTogglePictureInPicture)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Actions

    private func navigateToTab() {
        if !section.isFromCurrentSpace, let spaceID = section.tab.space?.id {
            Task {
                await spaceManager.switchToSpace(id: spaceID, for: windowState)
                tabManager.setActiveTab(section.tab, in: windowState)
            }
        } else {
            tabManager.setActiveTab(section.tab, in: windowState)
        }
    }
}

// MARK: - Layout Constants

private enum Layout {
    static let buttonSize: CGFloat = 32
    static let buttonCornerRadius: CGFloat = 16
    /// Maximum height for the panel content area.
    static let maxPanelHeight: CGFloat = 250
}
