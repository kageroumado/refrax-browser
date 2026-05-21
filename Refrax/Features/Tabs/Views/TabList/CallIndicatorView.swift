import SwiftUI

// MARK: - Call Indicator View

/// Expandable call indicator showing the most privacy-sensitive active device.
///
/// This view provides a compact representation of call state that expands on hover
/// to reveal individual media controls.
///
/// ## Call Detection
///
/// Call grouping triggers only when a **single WebPage** has audio + (mic OR camera)
/// simultaneously. Cross-page combinations do NOT trigger call grouping.
///
/// ## Collapsed State - Priority-Based Icon
///
/// Follows Apple's privacy-first approach, showing the most privacy-sensitive
/// active device:
///
/// 1. **Camera active** → green `video.fill`
/// 2. **Camera muted** → gray `video.slash.fill`
/// 3. **Mic active** → orange `mic.fill`
/// 4. **Mic muted** → gray `mic.slash.fill`
/// 5. **Audio only** → `headphones` or `headphones.slash`
///
/// ## Expanded State (on hover)
///
/// - Expands immediately when mouse enters the indicator area
/// - Shows individual icons: headphones, mic, camera
/// - Each icon is independently clickable
/// - Collapses after 1 second delay when mouse leaves
///
/// ## Accessibility
///
/// - Reduced motion: Shows expanded state always, skips animation
/// - VoiceOver: Collapsed state announces active devices
/// - Each expanded control has individual accessibility labels
struct CallIndicatorView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isExpanded = false
    @State private var collapseTask: Task<Void, Never>?

    let callStates: [TabStatusIndicators.CallPageState]
    let webPages: [WebPage]
    let pagesWithIDs: [(TabPage.ID, WebPage)]

    private enum Constants {
        static let iconSize: CGFloat = 10
        static let buttonSize: CGFloat = 16
        static let spacing: CGFloat = 2
        static let collapseDelay: Duration = .seconds(1)
    }

    /// Aggregated state across all call pages.
    private var aggregatedState: CallState {
        var hasAudio = false
        var audioMuted = true
        var hasMic = false
        var micMuted = true
        var hasCamera = false
        var cameraMuted = true

        for state in callStates {
            if state.hasAudio {
                hasAudio = true
                audioMuted = audioMuted && state.isAudioMuted
            }
            if state.hasMic {
                hasMic = true
                micMuted = micMuted && state.isMicMuted
            }
            if state.hasCamera {
                hasCamera = true
                cameraMuted = cameraMuted && state.isCameraMuted
            }
        }

        return CallState(
            hasAudio: hasAudio,
            audioMuted: audioMuted,
            hasMic: hasMic,
            micMuted: micMuted,
            hasCamera: hasCamera,
            cameraMuted: cameraMuted,
        )
    }

    var body: some View {
        let state = aggregatedState
        let shouldExpand = isExpanded || reduceMotion

        HStack(spacing: Constants.spacing) {
            if shouldExpand {
                expandedView(state)
            } else {
                collapsedView(state)
            }
        }
        .onHover { hovering in
            guard !reduceMotion else { return }

            if hovering {
                collapseTask?.cancel()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded = true
                }
            } else {
                collapseTask = Task {
                    try? await Task.sleep(for: Constants.collapseDelay)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isExpanded = false
                        }
                    }
                }
            }
        }
    }

    // MARK: - Collapsed View

    /// Single icon based on privacy priority: camera > mic > headphones
    private func collapsedView(_ state: CallState) -> some View {
        let (icon, color) = collapsedIconAndColor(state)

        return Button {
            // Expand on click as well
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded = true
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: Constants.iconSize, weight: .medium))
                .foregroundStyle(color)
                .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Active Call\nClick to expand controls")
        .accessibilityLabel("Active call with \(accessibilityDeviceList(state))")
        .accessibilityHint("Click to expand controls")
    }

    /// Determines the icon and color for collapsed state based on privacy priority.
    ///
    /// Uses red for muted states (common pattern in video call apps).
    private func collapsedIconAndColor(_ state: CallState) -> (String, Color) {
        // Priority: Camera (most privacy-sensitive) > Mic > Audio
        if state.hasCamera {
            if state.cameraMuted {
                return ("video.slash.fill", .red)
            } else {
                return ("video.fill", .green)
            }
        }

        if state.hasMic {
            if state.micMuted {
                return ("mic.slash.fill", .red)
            } else {
                return ("mic.fill", .orange)
            }
        }

        // Audio only (edge case - shouldn't be a "call" without input)
        if state.audioMuted {
            return ("headphones.slash", .red)
        }
        return ("headphones", .primary)
    }

    // MARK: - Expanded View

    @ViewBuilder
    private func expandedView(_ state: CallState) -> some View {
        // Audio button (always headphones in call context)
        if state.hasAudio {
            Button {
                let shouldMute = !state.audioMuted
                for webPage in webPages {
                    webPage.setAudioMuted(shouldMute)
                }
            } label: {
                Image(systemName: state.audioMuted ? "headphones.slash" : "headphones")
                    .font(.system(size: Constants.iconSize, weight: .medium))
                    .foregroundStyle(state.audioMuted ? .red : .primary)
                    .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(state.audioMuted ? "Audio Muted\nClick to unmute" : "In Call\nClick to mute audio")
            .accessibilityLabel(state.audioMuted ? "Audio Muted" : "In Call")
            .accessibilityHint(state.audioMuted ? "Click to unmute" : "Click to mute audio")
        }

        // Microphone button
        if state.hasMic {
            Button {
                Task {
                    let shouldMute = !state.micMuted
                    for webPage in webPages {
                        await webPage.setMicrophoneMuted(shouldMute)
                    }
                }
            } label: {
                Image(systemName: state.micMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.system(size: Constants.iconSize, weight: .medium))
                    .foregroundColor(state.micMuted ? .red : .orange)
                    .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(state.micMuted ? "Microphone Muted\nClick to unmute" : "Microphone Active\nClick to mute")
            .accessibilityLabel(state.micMuted ? "Microphone Muted" : "Microphone Active")
            .accessibilityHint(state.micMuted ? "Click to unmute" : "Click to mute")
        }

        // Camera button
        if state.hasCamera {
            Button {
                Task {
                    let shouldMute = !state.cameraMuted
                    for webPage in webPages {
                        await webPage.setCameraMuted(shouldMute)
                    }
                }
            } label: {
                Image(systemName: state.cameraMuted ? "video.slash.fill" : "video.fill")
                    .font(.system(size: Constants.iconSize, weight: .medium))
                    .foregroundColor(state.cameraMuted ? .red : .green)
                    .frame(width: Constants.buttonSize, height: Constants.buttonSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(
                state.cameraMuted ? "Camera Disabled\nClick to enable" : "Camera Active\nClick to disable",
            )
            .accessibilityLabel(state.cameraMuted ? "Camera Disabled" : "Camera Active")
            .accessibilityHint(state.cameraMuted ? "Click to enable" : "Click to disable")
        }
    }

    // MARK: - Helpers

    private func accessibilityDeviceList(_ state: CallState) -> String {
        var devices: [String] = []
        if state.hasCamera { devices.append("camera") }
        if state.hasMic { devices.append("microphone") }
        if state.hasAudio { devices.append("audio") }

        if devices.count == 1 {
            return devices[0]
        } else if devices.count == 2 {
            return "\(devices[0]) and \(devices[1])"
        } else if devices.count == 3 {
            return "\(devices[0]), \(devices[1]), and \(devices[2])"
        }
        return "devices"
    }
}

// MARK: - Call State

/// Aggregated call state for the indicator.
private struct CallState {
    let hasAudio: Bool
    let audioMuted: Bool
    let hasMic: Bool
    let micMuted: Bool
    let hasCamera: Bool
    let cameraMuted: Bool
}
