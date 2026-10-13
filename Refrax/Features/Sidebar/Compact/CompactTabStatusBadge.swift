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
        let state = control.state

        // Priority order
        if state.recentlyCrashed {
            return .crashed
        }
        if state.isUnresponsive {
            return .unresponsive
        }
        if state.isPlayingAudio {
            return state.isAudioMuted ? .audioMuted : .playingAudio
        }
        if state.isCameraActive {
            return .cameraActive
        }
        if state.isMicrophoneActive {
            return .micActive
        }
        if state.isSuspended(createdAt: tab.createdAt) {
            return .suspended
        }
        if state.isInFullscreen {
            return .fullscreen
        }
        return nil
    }

    private var control: TabMediaControl {
        TabMediaControl(tab: tab, pagePool: pagePool)
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
            control.reload()

        case .playingAudio:
            control.setMuted(true)

        case .audioMuted:
            control.setMuted(false)

        case .cameraActive:
            control.setCameraMuted(true)

        case .micActive:
            control.setMicrophoneMuted(true)

        case .fullscreen:
            let webPages = control.pages
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
