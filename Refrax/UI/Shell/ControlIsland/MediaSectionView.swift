import SwiftUI

// MARK: - Media Section

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
    @Environment(MediaControlsManager.self) private var mediaControlsManager
    @Environment(WindowState.self) private var windowState
    @Environment(SpaceManager.self) private var spaceManager
    @Environment(TabManager.self) private var tabManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let section: MediaSection
    /// Go to Tab and Picture in Picture stay open instead of waiting for a click on the row.
    var showsDetails = false
    /// Runs after Go to Tab, so a popover can close.
    var onNavigate: () -> Void = {}

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
            toggleDetails()
        }
        .onTapGesture {
            toggleDetails()
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
        if isExpanded || showsDetails {
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

    @ViewBuilder
    private var artworkView: some View {
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
            Button {
                section.webPage.setAudioMuted(!section.effectivelyMuted)
            } label: {
                Image(systemName: section.effectivelyMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(section.effectivelyMuted ? "Unmute" : "Mute")
            .accessibilityLabel(section.effectivelyMuted ? "Unmute" : "Mute")

            // Volume slider (compact)
            Slider(
                value: Binding(
                    get: { section.volume },
                    set: { newVolume in
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
            .accessibilityLabel(section.isPlaying ? "Pause" : "Play")
        }
    }

    /// Call controls - only show mic/camera if they're active or user-muted.
    /// Uses red for muted states (common pattern in Zoom/Meet/Teams).
    private var callControls: some View {
        HStack(spacing: 2) {
            // Headphones (audio mute) - always shown for calls
            Button {
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
                    navigateToTab()
                } label: {
                    Label("Go to Tab", systemImage: "arrow.right.circle")
                        .font(.system(size: 10))
                }

                if section.type.isMedia {
                    Button {
                        let page = section.webPage
                        Task { await page.togglePiP() }
                    } label: {
                        Label("Picture in Picture", systemImage: "pip.enter")
                            .font(.system(size: 10))
                    }
                    .disabled(!section.webPage.canTogglePiP)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Actions

    private func toggleDetails() {
        guard !showsDetails else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            isExpanded.toggle()
        }
    }

    private func navigateToTab() {
        defer { onNavigate() }
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
