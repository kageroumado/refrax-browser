import SwiftUI

/// Day navigation chevrons that appear at scroll edges.
///
/// Shows previous/next day buttons when the user scrolls to the beginning
/// or end of the current day's data.
struct NavigationChevrons: View {
    let layout: HistoryGraphLayout?
    let coordinates: GraphCoordinates
    let scrollPosition: CGPoint
    let viewportSize: CGSize

    var onPreviousDay: () async -> Void
    var onNextDay: () async -> Void

    var body: some View {
        ZStack {
            // Leading chevron (previous day)
            chevronButton(direction: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Trailing chevron (next day)
            chevronButton(direction: .trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // MARK: - Chevron Button

    private func chevronButton(direction: HorizontalEdge) -> some View {
        Button(action: {
            Task {
                if direction == .leading {
                    await onPreviousDay()
                } else {
                    await onNextDay()
                }
            }
        }) {
            Image(systemName: direction == .leading ? "chevron.left" : "chevron.right")
                .font(.title2)
                .padding()
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .padding()
        .opacity(isAtEdge(direction) ? 1 : 0)
    }

    // MARK: - Edge Detection

    private func isAtEdge(_ edge: HorizontalEdge) -> Bool {
        guard let layout, !layout.nodes.isEmpty else { return false }

        let firstDataX = layout.nodes.min(by: { $0.entry.visitedAt < $1.entry.visitedAt })
            .map { coordinates.x(for: $0.entry.visitedAt) } ?? 0
        let lastDataX = layout.nodes.max(by: { $0.entry.visitedAt < $1.entry.visitedAt })
            .map { coordinates.x(for: $0.entry.visitedAt) } ?? layout.bounds.width

        switch edge {
        case .leading:
            return scrollPosition.x <= firstDataX + 100
        case .trailing:
            return scrollPosition.x + viewportSize.width >= lastDataX - 100
        }
    }
}
