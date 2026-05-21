import SwiftUI

/// Priority-based status badge for compact tab buttons.
///
/// Isolated observation view: declares its own `WebPagePool` environment
/// so page state changes (audio, crash, etc.) only invalidate this badge,
/// not the parent `CompactTabButton` or tab list.
struct CompactTabStatusBadge: View {
    @Environment(WebPagePool.self) private var pagePool

    let tab: Tab

    private typealias Layout = CompactSidebarLayout.Badge

    // MARK: - Badge State

    private enum BadgeState {
        case crashed
        case unresponsive
        case playingAudio
        case audioMuted
        case cameraActive
        case micActive
        case suspended
        case fullscreen

        var icon: String {
            switch self {
            case .crashed: "exclamationmark.triangle.fill"
            case .unresponsive: "hourglass"
            case .playingAudio: "speaker.wave.2.fill"
            case .audioMuted: "speaker.slash.fill"
            case .cameraActive: "video.fill"
            case .micActive: "mic.fill"
            case .suspended: "moon.zzz.fill"
            case .fullscreen: "rectangle.on.rectangle"
            }
        }

        var circleColor: Color {
            switch self {
            case .crashed: .yellow
            case .unresponsive: .orange
            case .playingAudio, .audioMuted, .fullscreen: .secondary.opacity(0.9)
            case .cameraActive: .green
            case .micActive: .orange
            case .suspended: .secondary.opacity(0.7)
            }
        }
    }

    /// Compute highest-priority badge state from web pages.
    private var badgeState: BadgeState? {
        let pages = tab.pages.compactMap { pagePool.existingPage(for: $0) }
        guard !pages.isEmpty else { return nil }

        var crashed = false
        var unresponsive = false
        var playingAudio = false
        var allMuted = true
        var cameraActive = false
        var micActive = false
        var suspended = false
        var fullscreen = false
        var needsReload = false
        var isLoading = false

        for page in pages {
            crashed = crashed || page.recentlyCrashed
            unresponsive = unresponsive || page.isUnresponsive
            playingAudio = playingAudio || page.audioState.isPlayingAudio
            allMuted = allMuted && page.audioState.isMuted
            cameraActive = cameraActive || page.isCameraActive
            micActive = micActive || page.isMicrophoneActive
            suspended = suspended || page.isMediaSuspended
            fullscreen = fullscreen || page.isInFullscreen
            needsReload = needsReload || page.needsReload
            isLoading = isLoading || page.isLoading
        }

        // Priority order
        if crashed { return .crashed }
        if unresponsive { return .unresponsive }
        if playingAudio { return allMuted ? .audioMuted : .playingAudio }
        if cameraActive { return .cameraActive }
        if micActive { return .micActive }
        if needsReload, !isLoading, tab.createdAt.timeIntervalSinceNow < -0.5 {
            return .suspended
        }
        if fullscreen { return .fullscreen }
        return nil
    }

    private var webPages: [WebPage] {
        tab.pages.compactMap { pagePool.existingPage(for: $0) }
    }

    // MARK: - Body

    var body: some View {
        if let state = badgeState {
            Button {
                performAction(for: state)
            } label: {
                Image(systemName: state.icon)
                    .font(.system(size: Layout.iconSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: Layout.size, height: Layout.size)
                    .background {
                        Circle()
                            .fill(state.circleColor)
                    }
            }
            .buttonStyle(.plain)
            .transition(.scale.combined(with: .opacity))
        }
    }

    // MARK: - Actions

    private func performAction(for state: BadgeState) {
        switch state {
        case .crashed, .unresponsive, .suspended:
            for webPage in webPages {
                webPage.backingWebView.reload()
            }

        case .playingAudio:
            for webPage in webPages {
                webPage.setAudioMuted(true)
            }

        case .audioMuted:
            for webPage in webPages {
                webPage.setAudioMuted(false)
            }

        case .cameraActive:
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for webPage in webPages {
                        group.addTask { await webPage.setCameraMuted(true) }
                    }
                }
            }

        case .micActive:
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for webPage in webPages {
                        group.addTask { await webPage.setMicrophoneMuted(true) }
                    }
                }
            }

        case .fullscreen:
            Task {
                await withTaskGroup(of: Void.self) { group in
                    for webPage in webPages {
                        group.addTask { await webPage.closeAllMediaPresentations() }
                    }
                }
            }
        }
    }
}
