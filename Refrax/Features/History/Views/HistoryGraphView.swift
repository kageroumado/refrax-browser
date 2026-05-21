import Foundation
import SwiftData
import SwiftUI

/// Timeline-based graph visualization for browsing history.
///
/// Displays a day's browsing history as an interactive Canvas-based graph with
/// nodes (pages) positioned on discrete levels and arrows showing navigation flow.
///
/// ## Visual Layout
///
/// ```
/// +---------------------------------------------------------------------+
/// |  [List] [Graph*]              Search    Nov 15    Clear             | <- Toolbar
/// +---------------------------------------------------------------------+
/// |  21:00  22:00  23:00  00:00  01:00  02:00  03:00  <- Global Timeline|
/// |  --+-----+-----+-----+-----+-----+-----+--                          |
/// |    ^                                                                |
/// |  Currently visible: 21:30 - 23:45                                   |
/// +---------------------------------------------------------------------+
/// |                                                                     |
/// |  +-----------------+                    * 2h 15m *                  |
/// |  | news.ycombinator|                                                |
/// |  | News            |--+                                             |
/// |  +-----------------+  |                                             |
/// |                       |                                             |
/// |                       +---> +------------------+                    |
/// |                       |     | github.com       |                    |
/// |                       |     | SwiftUI Docs     |                    |
/// |                       |     +------------------+                    |
/// |                       |                                             |
/// |                       +---> +------------------+                    |
/// |                             | developer.apple  |                    |
/// |                             | WebKit API       |--+                 |
/// |                             +------------------+  |                 |
/// |                                                   |                 |
/// |  +-----------------+                              +-> o             |
/// |  | claude.ai       |                                  (5s visit)   |
/// |  | Personal        |                                               |
/// |  +-----------------+                                               |
/// |                                                                     |
/// |  +--..............--+  <- Dotted border = Still open               |
/// |  : stackoverflow    :                                               |
/// |  : Swift Question   :                                               |
/// |  +--..............--+                                               |
/// |                                                                     |
/// |  <                                                             >   | <- Day nav
/// +---------------------------------------------------------------------+
/// |  Visible: 21:30 - 23:45                          [-]  30min  [+]  | <- Bottom bar
/// +---------------------------------------------------------------------+
/// ```
///
/// ## Architecture
///
/// Uses Canvas with symbols-based rendering for optimal performance:
/// - **Symbols**: Pre-rendered text views (titles, times) cached once
/// - **Drawing**: Pure geometric paths drawn in single pass
/// - **Interaction**: Invisible SwiftUI overlays for tap/hover
/// - **Performance**: 60fps with 500+ nodes
///
/// ## User Interactions
///
/// - **Zoom**: Pinch gesture or +/- buttons (5 discrete levels)
/// - **Scroll**: Free horizontal/vertical panning
/// - **Click node**: Shows detail popover with page info
/// - **Hover node**: Changes cursor, shows tooltip
/// - **Day navigation**: Chevrons at scroll edges, date picker
///
/// ## Edge Cases Handled
///
/// - Still-open pages (dotted border, extends to +15min)
/// - Very short visits (<5s shows as dot)
/// - Time gaps >30min (compressed with indicator)
/// - Midnight crossing (spans across day boundary)
/// - Deleted spaces (fallback color)
struct HistoryGraphView: View {
    @Environment(HistoryManager.self) private var historyManager
    @Environment(TabManager.self) private var tabManager
    @Environment(WindowState.self) private var windowState

    // State
    @State private var selectedDate: Date = .init()
    @State private var zoomLevel: GraphCoordinates.ZoomLevel = .standard
    @State private var layout: HistoryGraphLayout?
    @State private var isLoading = false
    @State private var scrollPosition: CGPoint = .zero
    @State private var viewportSize: CGSize = .zero
    @State private var currentMagnification: CGFloat = 1.0
    @State private var accumulatedMagnification: CGFloat = 1.0
    @State private var visibleTimeRange: ClosedRange<Date>?
    @State private var selectedNode: GraphNode?
    @State private var showDetailPopover = false
    @State private var errorMessage: String?
    @State private var navigationDirection: NavigationDirection?

    enum NavigationDirection {
        case forward
        case backward
    }

    private let layoutEngine = HistoryGraphLayoutEngine()

    private var coordinates: GraphCoordinates {
        GraphCoordinates(zoomLevel: zoomLevel, date: selectedDate)
    }

    private var spacesMap: [UUID: Space] {
        Dictionary(uniqueKeysWithValues: tabManager.state.spaces.map { ($0.id, $0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar
            HistoryGraphToolbar(
                selectedDate: $selectedDate,
                zoomLevel: zoomLevel,
                onZoomIn: zoomIn,
                onZoomOut: zoomOut,
                onNavigateToToday: navigateToToday,
            )

            Divider()

            // Global time indicator
            TimeIndicatorView(
                coordinates: coordinates,
                layout: layout,
                visibleTimeRange: visibleTimeRange,
            )

            Divider()

            // Main graph area
            GeometryReader { geometry in
                ZStack {
                    if isLoading {
                        ProgressView("Loading history graph...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let errorMessage {
                        ContentUnavailableView {
                            Label("Error Loading History", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(errorMessage)
                        }
                    } else if let layout, !layout.nodes.isEmpty {
                        graphContentWithGestures(layout: layout)
                    } else {
                        emptyState
                    }
                }
                .onAppear {
                    viewportSize = geometry.size
                }
                .onChange(of: geometry.size) { _, newSize in
                    viewportSize = newSize
                }
            }

            Divider()

            // Bottom controls
            bottomControls
        }
        .task {
            await loadHistoryGraph()
        }
        .onChange(of: selectedDate) { _, _ in
            Task {
                await loadHistoryGraph()
            }
        }
    }

    // MARK: - Graph Content with Gestures

    private func graphContentWithGestures(layout: HistoryGraphLayout) -> some View {
        GraphContentView(
            layout: layout,
            coordinates: coordinates,
            selectedDate: selectedDate,
            selectedNode: selectedNode,
            showDetailPopover: $showDetailPopover,
            navigationDirection: $navigationDirection,
            scrollPosition: $scrollPosition,
            viewportSize: viewportSize,
            onNodeSelected: selectNode,
            onClearSelection: clearSelection,
            onOpenInNewTab: openInNewTab,
            onScrollPositionChanged: { newPosition in
                updateVisibleRange(scrollOffset: newPosition, viewportSize: viewportSize)
            },
            onScrollToInitialPosition: { proxy in
                scrollToInitialPosition(proxy: proxy, layout: layout)
            },
            onScrollAfterNavigation: scrollAfterNavigation,
        )
        .gesture(magnifyGesture)
        .overlay(alignment: .leading) {
            NavigationChevrons(
                layout: self.layout,
                coordinates: coordinates,
                scrollPosition: scrollPosition,
                viewportSize: viewportSize,
                onPreviousDay: navigateToPreviousDay,
                onNextDay: navigateToNextDay,
            )
        }
    }

    // MARK: - Magnify Gesture

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                currentMagnification = value.magnification
            }
            .onEnded { value in
                // Accumulate zoom
                accumulatedMagnification *= value.magnification
                currentMagnification = 1.0

                // Snap to nearest zoom level
                snapToNearestZoomLevel()
            }
    }

    /// Snap accumulated magnification to nearest discrete zoom level.
    private func snapToNearestZoomLevel() {
        let levels = GraphCoordinates.ZoomLevel.allCases
        let currentIndex = levels.firstIndex(of: zoomLevel) ?? 2

        // Determine direction based on accumulated magnification
        let targetIndex: Int = if accumulatedMagnification > 1.3 {
            // Zoom in
            max(0, currentIndex - 1)
        } else if accumulatedMagnification < 0.7 {
            // Zoom out
            min(levels.count - 1, currentIndex + 1)
        } else {
            // Stay at current level
            currentIndex
        }

        // Reset accumulation
        accumulatedMagnification = 1.0

        // Apply zoom with animation
        if targetIndex != currentIndex {
            _ = withAnimation(.easeOut(duration: 0.2)) {
                Task {
                    await setZoomLevel(levels[targetIndex])
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No History", systemImage: "clock")
        } description: {
            Text("No browsing history for this date")
        }
    }

    // MARK: - Bottom Controls

    private var bottomControls: some View {
        HStack {
            if let range = visibleTimeRange {
                Text("Visible: \(formatTimeRange(range))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.background.secondary)
    }

    // MARK: - Data Loading

    private func loadHistoryGraph() async {
        isLoading = true
        errorMessage = nil

        // Get entries for the extended time range
        // Note: Uses sync method because GraphNode needs full HistoryEntry with parent relationships
        // for arrow drawing. A future improvement could add parentID to HistoryEntryData.
        let coords = coordinates
        let entries = historyManager.entriesSync(
            from: coords.timeRange.lowerBound,
            to: coords.timeRange.upperBound,
        )

        // Compute layout
        let computedLayout = layoutEngine.computeLayout(
            entries: entries,
            coordinates: coords,
            spaces: spacesMap,
        )

        layout = computedLayout

        isLoading = false
    }

    // MARK: - Navigation

    private func navigateToPreviousDay() async {
        guard let previousDay = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) else {
            return
        }
        navigationDirection = .backward
        selectedDate = previousDay
        await loadHistoryGraph()
    }

    private func navigateToNextDay() async {
        guard let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) else {
            return
        }
        navigationDirection = .forward
        selectedDate = nextDay
        await loadHistoryGraph()
    }

    private func navigateToToday() async {
        selectedDate = Date()
        await loadHistoryGraph()
    }

    // MARK: - Scroll Management

    private func scrollToInitialPosition(proxy: ScrollViewProxy, layout: HistoryGraphLayout) {
        guard !layout.nodes.isEmpty else { return }

        // Find first node with data
        if let firstNode = layout.nodes.min(by: { $0.entry.visitedAt < $1.entry.visitedAt }) {
            let coords = coordinates
            let targetX = coords.x(for: firstNode.entry.visitedAt) - 50 // Small offset

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                proxy.scrollTo("canvas", anchor: .init(x: targetX / layout.bounds.width, y: 0))
            }
        }
    }

    private func scrollAfterNavigation(proxy: ScrollViewProxy, layout: HistoryGraphLayout, direction: NavigationDirection) {
        guard !layout.nodes.isEmpty else { return }

        let coords = coordinates
        let targetX: CGFloat = switch direction {
        case .backward:
            // Going back - scroll to end of day
            if let lastNode = layout.nodes.max(by: { $0.entry.visitedAt < $1.entry.visitedAt }) {
                coords.x(for: lastNode.entry.visitedAt)
            } else {
                layout.bounds.width - viewportSize.width
            }
        case .forward:
            // Going forward - scroll to beginning of day
            if let firstNode = layout.nodes.min(by: { $0.entry.visitedAt < $1.entry.visitedAt }) {
                coords.x(for: firstNode.entry.visitedAt) - 50
            } else {
                0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            proxy.scrollTo("canvas", anchor: .init(x: max(0, min(1, targetX / layout.bounds.width)), y: 0))
        }
    }

    // MARK: - Zoom

    private func setZoomLevel(_ level: GraphCoordinates.ZoomLevel) async {
        zoomLevel = level
        await loadHistoryGraph()
    }

    private func zoomIn() async {
        let levels = GraphCoordinates.ZoomLevel.allCases
        guard let currentIndex = levels.firstIndex(of: zoomLevel),
              currentIndex > 0 else {
            return
        }
        await setZoomLevel(levels[currentIndex - 1])
    }

    private func zoomOut() async {
        let levels = GraphCoordinates.ZoomLevel.allCases
        guard let currentIndex = levels.firstIndex(of: zoomLevel),
              currentIndex < levels.count - 1 else {
            return
        }
        await setZoomLevel(levels[currentIndex + 1])
    }

    // MARK: - Node Selection

    private func selectNode(_ node: GraphNode) {
        selectedNode = node
        showDetailPopover = true
    }

    private func clearSelection() {
        selectedNode = nil
        showDetailPopover = false
    }

    private func openInNewTab(url: URL) {
        tabManager.createTab(url: url, makeActive: true)
        clearSelection()
    }

    // MARK: - Visible Range

    private func updateVisibleRange(scrollOffset: CGPoint, viewportSize: CGSize) {
        let coords = coordinates

        let startDate = coords.date(for: scrollOffset.x)
        let endDate = coords.date(for: scrollOffset.x + viewportSize.width)

        visibleTimeRange = startDate ... endDate
    }

    // MARK: - Formatting

    private func formatTimeRange(_ range: ClosedRange<Date>) -> String {
        "\(range.lowerBound.formatted(date: .omitted, time: .shortened)) - \(range.upperBound.formatted(date: .omitted, time: .shortened))"
    }
}

// MARK: - Preview

#Preview(traits: .modifier(RefraxPreviewModifier())) {
    HistoryGraphView()
        .frame(width: 1_200, height: 800)
}
