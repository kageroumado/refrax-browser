import SwiftUI

/// A pulsing recording indicator shown when tab recording is active.
///
/// Displays a red dot with optional duration label. The dot pulses to indicate
/// active recording.
struct RecordingIndicator: View {
    /// Whether to show the duration alongside the indicator.
    var showDuration: Bool = true

    /// The recording start time for duration calculation.
    var startTime: Date?

    @State private var isPulsing = false

    private enum Layout {
        static let dotSize: CGFloat = 8
        static let fontSize: CGFloat = 11
    }

    var body: some View {
        HStack(spacing: 4) {
            // Pulsing red dot
            Circle()
                .fill(Color.red)
                .frame(width: Layout.dotSize, height: Layout.dotSize)
                .opacity(isPulsing ? 0.5 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)

            // Duration label
            if showDuration {
                DurationLabel(startTime: startTime)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.red.opacity(0.15), in: Capsule())
        .onAppear {
            isPulsing = true
        }
    }
}

// MARK: - Duration Label

/// Live-updating duration label using TimelineView.
private struct DurationLabel: View {
    let startTime: Date?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(formattedDuration(at: context.date))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.red)
        }
    }

    private func formattedDuration(at currentDate: Date) -> String {
        guard let startTime else { return "0:00" }

        let elapsed = currentDate.timeIntervalSince(startTime)
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60

        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Compact Variant

/// A minimal recording indicator for tight spaces (just the pulsing dot).
struct RecordingIndicatorCompact: View {
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(Color.red)
            .frame(width: 6, height: 6)
            .opacity(isPulsing ? 0.5 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear {
                isPulsing = true
            }
    }
}
