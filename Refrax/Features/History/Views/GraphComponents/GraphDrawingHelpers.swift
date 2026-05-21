import SwiftUI

/// Pure drawing functions for HistoryGraphView Canvas rendering.
///
/// All methods are static to enable efficient Canvas drawing without capturing state.
/// Text symbols are pre-rendered by the caller and resolved via `GraphicsContext.resolveSymbol`.
enum GraphDrawingHelpers {
    // MARK: - Main Drawing Entry Point

    /// Draw the complete graph in layer order: time indicator, gaps, connections, nodes.
    static func drawGraph(
        context: GraphicsContext,
        layout: HistoryGraphLayout,
        size: CGSize,
        coordinates: GraphCoordinates,
        selectedDate: Date,
    ) {
        // Draw current time indicator if viewing today
        if Calendar.current.isDateInToday(selectedDate) {
            drawCurrentTimeIndicator(context: context, coordinates: coordinates, canvasHeight: size.height)
        }

        // Draw time gaps
        for gap in layout.gaps {
            drawTimeGap(context: context, gap: gap, coordinates: coordinates, canvasHeight: size.height)
        }

        // Draw connections (arrows) first, so nodes appear above
        for connection in layout.connections {
            drawConnection(context: context, connection: connection)
        }

        // Draw nodes
        for node in layout.nodes {
            drawNode(context: context, node: node)
        }
    }

    // MARK: - Time Indicators

    /// Draw vertical dashed line at current time (for today's view).
    static func drawCurrentTimeIndicator(
        context: GraphicsContext,
        coordinates: GraphCoordinates,
        canvasHeight: CGFloat,
    ) {
        let now = Date()
        let x = coordinates.x(for: now)

        var path = Path()
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: canvasHeight))

        context.stroke(
            path,
            with: .color(.red),
            style: StrokeStyle(lineWidth: 2, dash: [5, 5]),
        )
    }

    /// Draw compressed time gap region with label.
    static func drawTimeGap(
        context: GraphicsContext,
        gap: TimeGap,
        coordinates: GraphCoordinates,
        canvasHeight: CGFloat,
    ) {
        let startX = coordinates.x(for: gap.startDate)
        let centerX = startX + GraphCoordinates.compressedGapWidth / 2

        // Draw background
        let rect = CGRect(
            x: startX,
            y: 0,
            width: GraphCoordinates.compressedGapWidth,
            height: canvasHeight,
        )

        context.fill(
            Path(rect),
            with: .color(.secondary.opacity(0.1)),
        )

        // Draw label using pre-rendered symbol
        if let label = context.resolveSymbol(id: "gap-\(gap.id)") {
            context.draw(label, at: CGPoint(x: centerX, y: 20))
        }
    }

    // MARK: - Connections

    /// Draw connection arrow between nodes.
    static func drawConnection(context: GraphicsContext, connection: GraphConnection) {
        context.stroke(
            connection.path,
            with: .color(.secondary),
            lineWidth: GraphCoordinates.arrowLineWidth,
        )
    }

    // MARK: - Nodes

    /// Draw node based on whether it's a dot (short visit) or rectangle (normal visit).
    static func drawNode(context: GraphicsContext, node: GraphNode) {
        if node.isDot {
            drawDotNode(context: context, node: node)
        } else {
            drawRectNode(context: context, node: node)
        }
    }

    /// Draw very short visit as a small dot that scales with zoom.
    static func drawDotNode(context: GraphicsContext, node: GraphNode) {
        let center = CGPoint(
            x: node.frame.midX,
            y: node.frame.midY,
        )

        // Use the width from the frame (which is already scaled)
        let dotSize = node.frame.width

        let circle = Path(
            ellipseIn: CGRect(
                x: center.x - dotSize / 2,
                y: center.y - dotSize / 2,
                width: dotSize,
                height: dotSize,
            ),
        )

        // Use red for failed loads, otherwise space color
        let fillColor = node.entry.failedToLoad ? Color.red : (node.spaceColor ?? .appAccentColor)
        context.fill(circle, with: .color(fillColor))

        if node.isOpen {
            context.stroke(
                circle,
                with: .color(fillColor),
                style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]),
            )
        }
    }

    /// Draw normal page as a rectangle with title and optional space name.
    ///
    /// Visual appearance:
    /// - Background: Space color (faded), or red for failed loads
    /// - Border: Domain color (solid), red for failed, or dotted if still open
    /// - Text: Title centered, space name at bottom
    static func drawRectNode(context: GraphicsContext, node: GraphNode) {
        let rect = node.frame.insetBy(
            dx: GraphCoordinates.pageRectPadding,
            dy: GraphCoordinates.pageRectPadding,
        )

        let roundedRect = Path(roundedRect: rect, cornerRadius: 6)

        // Background fill - red tint for failed loads, otherwise space color
        let fillColor = node.entry.failedToLoad ? Color.red : (node.spaceColor ?? .appAccentColor)
        context.fill(
            roundedRect,
            with: .color(fillColor.opacity(0.2)),
        )

        // Border
        if node.entry.failedToLoad {
            // Red border for failed loads
            context.stroke(
                roundedRect,
                with: .color(.red),
                lineWidth: 2,
            )
        } else if node.isOpen {
            // Dotted border for still-open pages
            context.stroke(
                roundedRect,
                with: .color(fillColor),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]),
            )
        } else {
            // Solid border with domain color
            let domainColor = domainColor(for: node.entry.domain)
            context.stroke(
                roundedRect,
                with: .color(domainColor),
                lineWidth: 2,
            )
        }

        // Draw title using pre-rendered symbol - positioned higher to make room for space name
        if let title = context.resolveSymbol(id: "title-\(node.id)") {
            let titleY = node.entry.spaceID != nil ? rect.midY - 6 : rect.midY
            context.draw(
                title,
                at: CGPoint(x: rect.midX, y: titleY),
                anchor: .center,
            )
        }

        // Draw space name using pre-rendered symbol (if available) - more padding from bottom
        if node.entry.spaceID != nil {
            if let spaceName = context.resolveSymbol(id: "space-\(node.id)") {
                context.draw(
                    spaceName,
                    at: CGPoint(x: rect.midX, y: rect.maxY - 10),
                    anchor: .center,
                )
            }
        }

        // Draw failed indicator icon for rectangle nodes
        if node.entry.failedToLoad {
            if let failedIcon = context.resolveSymbol(id: "failed-\(node.id)") {
                context.draw(
                    failedIcon,
                    at: CGPoint(x: rect.maxX - 12, y: rect.minY + 12),
                    anchor: .center,
                )
            }
        }
    }

    // MARK: - Color Helpers

    /// Generate consistent color for domain using hash.
    static func domainColor(for domain: String) -> Color {
        let hash = abs(domain.hashValue)
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.6, brightness: 0.8)
    }
}
