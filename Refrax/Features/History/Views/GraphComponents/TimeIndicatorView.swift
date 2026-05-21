import SwiftUI

/// Two-part timeline: static axis labels + interactive scrubber with visible portion indicator.
///
/// The scrubber shows which portion of the day is currently visible and could be
/// extended to support dragging for navigation.
struct TimeIndicatorView: View {
    let coordinates: GraphCoordinates
    let layout: HistoryGraphLayout?
    let visibleTimeRange: ClosedRange<Date>?

    var body: some View {
        VStack(spacing: 0) {
            // Interactive scrubber with visible portion indicator
            timelineScrubber
                .frame(height: 20)

            // Static axis labels (non-interactive)
            staticTimeAxis
                .frame(height: 20)
        }
        .background(.background.secondary)
    }

    // MARK: - Timeline Scrubber

    /// Interactive scrubber showing visible portion as draggable capsule.
    private var timelineScrubber: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width

            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(Color.secondary.opacity(0.1))

                // Visible portion capsule (if we have visible range and layout)
                if let visibleRange = visibleTimeRange,
                   let layout {
                    let startX = (coordinates.x(for: visibleRange.lowerBound) / layout.bounds.width) * totalWidth
                    let endX = (coordinates.x(for: visibleRange.upperBound) / layout.bounds.width) * totalWidth
                    let capsuleWidth = max(endX - startX, 30) // Minimum 30pt width

                    Capsule()
                        .fill(Color.appAccentColor.opacity(0.3))
                        .stroke(Color.appAccentColor, lineWidth: 1.5)
                        .frame(width: capsuleWidth)
                        .offset(x: startX)
                }
            }
        }
    }

    // MARK: - Static Time Axis

    /// Static time axis with hour markers (non-interactive).
    private var staticTimeAxis: some View {
        let markers = timeMarkers(for: coordinates.timeRange)
        let fullWidth = coordinates.x(for: coordinates.timeRange.upperBound)

        return GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                // Background
                Rectangle()
                    .fill(Color.clear)

                // Hour markers and labels
                ForEach(Array(markers.enumerated()), id: \.offset) { _, marker in
                    let x = coordinates.x(for: marker)
                    let screenX = (x / fullWidth) * geometry.size.width

                    VStack(spacing: 2) {
                        Rectangle()
                            .fill(Color.secondary)
                            .frame(width: 1, height: 6)

                        Text(formatTime(marker))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .offset(x: screenX - 20) // Center the label (approx 40pt width / 2)
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func formatTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    private func timeMarkers(for range: ClosedRange<Date>) -> [Date] {
        var markers: [Date] = []
        let calendar = Calendar.current

        // Round start to nearest hour
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: range.lowerBound)
        components.minute = 0
        components.second = 0

        guard var current = calendar.date(from: components) else { return [] }

        // Generate hourly markers
        while current <= range.upperBound {
            if current >= range.lowerBound {
                markers.append(current)
            }
            guard let next = calendar.date(byAdding: .hour, value: 1, to: current) else { break }
            current = next
        }

        return markers
    }
}
