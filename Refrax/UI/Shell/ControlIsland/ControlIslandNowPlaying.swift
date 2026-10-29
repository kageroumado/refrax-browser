import SwiftUI

/// The Now Playing popover from the island: one section per tab with sound or a call, each
/// with play or pause, mute, volume, Go to Tab and Picture in Picture.
struct ControlIslandNowPlaying: View {
    @Binding var isPresented: Bool
    @Environment(MediaControlsManager.self) private var mediaControls

    enum Layout {
        static let width: CGFloat = 300
        static let maximumHeight: CGFloat = 360
        static let padding: CGFloat = 12
        static let spacing: CGFloat = 10
    }

    /// The rail's symbol: speaker waves while anything plays, a slashed speaker while every
    /// playing tab is muted, a still speaker while only paused media remains.
    static func symbol(for sections: [MediaSection]) -> String {
        let playing = sections.filter(\.isPlaying)
        if playing.isEmpty {
            return "speaker"
        }
        return playing.allSatisfy(\.effectivelyMuted) ? "speaker.slash" : "speaker.wave.2"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.spacing) {
            Text("Now Playing")
                .font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: Layout.spacing) {
                    ForEach(mediaControls.activeSections) { section in
                        MediaSectionView(section: section, showsDetails: true) { isPresented = false }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(Layout.padding)
        .frame(width: Layout.width)
        .frame(maxHeight: Layout.maximumHeight)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: mediaControls.hasActiveMedia) { _, hasMedia in
            if !hasMedia {
                isPresented = false
            }
        }
    }
}
