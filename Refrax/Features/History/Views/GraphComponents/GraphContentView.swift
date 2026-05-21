import SwiftUI

/// Canvas-based graph rendering with pre-rendered text symbols and invisible tap targets.
///
/// Uses the Canvas symbols pattern for optimal performance:
/// - Text views are pre-rendered once in the `symbols` closure
/// - Drawing logic references symbols by ID via `context.resolveSymbol`
/// - Invisible SwiftUI overlays provide tap/hover interaction
struct GraphContentView: View {
    let layout: HistoryGraphLayout
    let coordinates: GraphCoordinates
    let selectedDate: Date
    let selectedNode: GraphNode?
    let showDetailPopover: Binding<Bool>
    let navigationDirection: Binding<HistoryGraphView.NavigationDirection?>
    let scrollPosition: Binding<CGPoint>
    let viewportSize: CGSize

    @Environment(TabManager.self) private var tabManager

    var onNodeSelected: (GraphNode) -> Void
    var onClearSelection: () -> Void
    var onOpenInNewTab: (URL) -> Void
    var onScrollPositionChanged: (CGPoint) -> Void
    var onScrollToInitialPosition: (ScrollViewProxy) -> Void
    var onScrollAfterNavigation: (ScrollViewProxy, HistoryGraphLayout, HistoryGraphView.NavigationDirection) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                ZStack {
                    canvas
                        .frame(width: layout.bounds.width, height: layout.bounds.height)
                        .id("canvas")

                    // Overlay invisible tap targets for nodes
                    ForEach(layout.nodes) { node in
                        nodeTapTarget(for: node)
                    }
                }
                .background(scrollPositionTracker)
            }
            .coordinateSpace(name: "scrollView")
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                let newPosition = CGPoint(x: -offset.x, y: -offset.y)
                scrollPosition.wrappedValue = newPosition
                onScrollPositionChanged(newPosition)
            }
            .onAppear {
                onScrollToInitialPosition(proxy)
            }
            .onChange(of: layout) { _, newLayout in
                if let direction = navigationDirection.wrappedValue {
                    onScrollAfterNavigation(proxy, newLayout, direction)
                    navigationDirection.wrappedValue = nil
                }
            }
            .if(showDetailPopover.wrappedValue) { view in
                view.popover(isPresented: showDetailPopover) {
                    if let node = selectedNode {
                        PageDetailPopover(
                            node: node,
                            onOpenInNewTab: {
                                onOpenInNewTab(node.entry.url)
                            },
                            onDismiss: {
                                onClearSelection()
                            },
                        )
                    }
                }
            }
        }
    }

    // MARK: - Canvas

    private var canvas: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: false) { context, size in
            GraphDrawingHelpers.drawGraph(
                context: context,
                layout: layout,
                size: size,
                coordinates: coordinates,
                selectedDate: selectedDate,
            )
        } symbols: {
            nodeSymbols
            gapSymbols
        }
    }

    // MARK: - Pre-rendered Symbols

    @ViewBuilder
    private var nodeSymbols: some View {
        ForEach(layout.nodes) { node in
            // Page title/URL - properly truncated with fixed width
            Group {
                let title = node.entry.title ?? node.entry.displayURL
                let maxWidth = max(node.frame.width - 16, 50) // Account for padding
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: maxWidth)
                    .foregroundStyle(node.entry.failedToLoad ? .secondary : .primary)
            }
            .tag("title-\(node.id)")

            // Space name (if available) - also properly sized
            if let spaceID = node.entry.spaceID,
               let space = tabManager.state.space(for: spaceID) {
                let maxWidth = max(node.frame.width - 16, 50)
                Text(space.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: maxWidth)
                    .tag("space-\(node.id)")
            }

            // Failed load indicator icon
            if node.entry.failedToLoad {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .tag("failed-\(node.id)")
            }
        }
    }

    @ViewBuilder
    private var gapSymbols: some View {
        ForEach(layout.gaps) { gap in
            Text("\u{26A1} \(gap.durationDescription)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .tag("gap-\(gap.id)")
        }
    }

    // MARK: - Tap Targets

    private func nodeTapTarget(for node: GraphNode) -> some View {
        Color.clear
            .frame(width: node.frame.width, height: node.frame.height)
            .position(
                x: node.frame.midX,
                y: node.frame.midY,
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onNodeSelected(node)
            }
            .onHover { isHovering in
                if isHovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            .help(node.entry.title ?? node.entry.displayURL)
    }

    // MARK: - Scroll Position Tracking

    private var scrollPositionTracker: some View {
        GeometryReader { scrollGeometry in
            Color.clear.preference(
                key: ScrollOffsetPreferenceKey.self,
                value: scrollGeometry.frame(in: .named("scrollView")).origin,
            )
        }
    }
}

// MARK: - Scroll Offset Preference Key

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero

    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        value = nextValue()
    }
}
