import SwiftUI

/// Behavior settings section for site settings edit sheet.
///
/// Contains page leave alerts, scroll behavior, video controls,
/// and playback speed override settings.
struct SiteSettingsBehaviorSection: View {
    @Binding var beforeUnloadAlertOverride: BeforeUnloadAlertOverride
    @Binding var scrollHijackingOverride: ScrollHijackingOverride
    @Binding var videoControlsOverride: VideoControlsOverride
    @Binding var videoSpeedOverride: Double?
    @Binding var calmPage: Bool

    var body: some View {
        Section("Behavior") {
            Toggle("Calm This Page", isOn: $calmPage)
                .help("Freeze CSS and SVG animations on this site to save energy")

            Picker("Page Leave Alerts", selection: $beforeUnloadAlertOverride) {
                ForEach(BeforeUnloadAlertOverride.allCases, id: \.self) { override in
                    Text(override.displayName).tag(override)
                }
            }
            .help("Control 'Are you sure you want to leave?' alerts on this site")

            Picker("Scroll Behavior", selection: $scrollHijackingOverride) {
                ForEach(ScrollHijackingOverride.allCases, id: \.self) { override in
                    Text(override.displayName).tag(override)
                }
            }
            .help("Control custom scroll behaviors on this site")

            Picker("Video Controls", selection: $videoControlsOverride) {
                ForEach(VideoControlsOverride.allCases, id: \.self) { override in
                    Text(override.displayName).tag(override)
                }
            }
            .help("Control whether native video controls are shown on this site")

            if videoControlsOverride == .forceNative {
                Picker("Playback Speed", selection: videoSpeedOverrideBinding) {
                    Text("Use Default").tag(VideoSpeedOption.useDefault)
                    Text("0.5\u{00D7}").tag(VideoSpeedOption.speed(0.5))
                    Text("0.75\u{00D7}").tag(VideoSpeedOption.speed(0.75))
                    Text("1.0\u{00D7}").tag(VideoSpeedOption.speed(1.0))
                    Text("1.25\u{00D7}").tag(VideoSpeedOption.speed(1.25))
                    Text("1.5\u{00D7}").tag(VideoSpeedOption.speed(1.5))
                    Text("2.0\u{00D7}").tag(VideoSpeedOption.speed(2.0))
                }
            }
        }
    }

    /// Binding adapter for optional video speed override.
    private var videoSpeedOverrideBinding: Binding<VideoSpeedOption> {
        Binding(
            get: {
                if let speed = videoSpeedOverride {
                    .speed(speed)
                } else {
                    .useDefault
                }
            },
            set: { newValue in
                videoSpeedOverride = switch newValue {
                case .useDefault: nil
                case let .speed(value): value
                }
            },
        )
    }
}

/// Option for per-site video speed override.
enum VideoSpeedOption: Hashable {
    case useDefault
    case speed(Double)
}
