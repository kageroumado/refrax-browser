import SwiftUI

// MARK: - Dividers

extension UnifiedContentView {
    /// Layer containing draggable dividers for resizing panes in multi-pane mode
    ///
    /// Uses a hybrid approach:
    /// - **Visual layer (SwiftUI)**: Thin 1pt separator lines using native macOS separator color
    /// - **Interaction layer (AppKit)**: DividerTrackingView handles cursor changes and drag gestures
    ///
    /// The AppKit layer is necessary because WKWebView continuously sets its cursor based on
    /// content, overriding SwiftUI's gesture-based cursor hints. By using NSTrackingArea with
    /// `.cursorUpdate`, we can forcefully set the resize cursor in the divider zones.
    @ViewBuilder
    var dividersLayer: some View {
        if let config = tab.layoutConfiguration {
            let hasVertical = needsVerticalDivider(config: config)
            let hasHorizontal = needsHorizontalDivider(config: config)
            let verticalSpan = verticalDividerSpan(config: config)
            let horizontalSpan = horizontalDividerSpan(config: config)

            ZStack {
                // Visual dividers (SwiftUI) - non-interactive
                if hasVertical {
                    verticalDividerVisual
                }
                if hasHorizontal {
                    horizontalDividerVisual
                }

                // Interaction layer (AppKit) - handles cursor and drag
                DividerTrackingView(
                    configuration: DividerConfiguration(
                        hasVerticalDivider: hasVertical,
                        hasHorizontalDivider: hasHorizontal,
                        verticalDividerRatio: horizontalDivider,
                        horizontalDividerRatio: verticalDivider,
                        verticalDividerSpan: verticalSpan,
                        horizontalDividerSpan: horizontalSpan,
                    ),
                    onDragBegan: { type in
                        if activeDivider != type {
                            dividerDragStartValue = type == .vertical ? horizontalDivider : verticalDivider
                        }
                        activeDivider = type
                    },
                    onDragChanged: { type, delta in
                        handleDividerDrag(type, delta: delta)
                    },
                    onDragEnded: { type in
                        finalizeDividerDrag(type)
                    },
                )
            }
        }
    }

    /// Visual-only vertical divider line (non-interactive)
    ///
    /// For triple layouts with horizontal expansions (one pane spans full width),
    /// the vertical divider only appears in the row that's split.
    /// Divider color matching macOS split view appearance
    ///
    /// `separatorColor` is semitransparent by design, which causes it to blend with
    /// colored backgrounds. `gridColor` provides an opaque alternative that matches
    /// the appearance of system split view dividers.
    private var dividerColor: Color {
        Color(nsColor: .gridColor)
    }

    private var verticalDividerVisual: some View {
        let x = contentSize.width * horizontalDivider
        let (dividerHeight, dividerY) = verticalDividerGeometry

        return Rectangle()
            .fill(dividerColor)
            .frame(width: Layout.dividerVisualThickness, height: dividerHeight)
            .position(x: x, y: dividerY)
            .allowsHitTesting(false)
    }

    /// Visual-only horizontal divider line (non-interactive)
    ///
    /// For triple layouts with vertical expansions (one pane spans full height),
    /// the horizontal divider only appears in the column that's split.
    private var horizontalDividerVisual: some View {
        let y = contentSize.height * verticalDivider
        let (dividerWidth, dividerX) = horizontalDividerGeometry

        return Rectangle()
            .fill(dividerColor)
            .frame(width: dividerWidth, height: Layout.dividerVisualThickness)
            .position(x: dividerX, y: y)
            .allowsHitTesting(false)
    }

    /// Calculates vertical divider height and Y position for triple layouts
    ///
    /// In triple layouts with a horizontal expansion (top or bottom row merged),
    /// the vertical divider should only span the row that's split.
    private var verticalDividerGeometry: (height: CGFloat, y: CGFloat) {
        guard let config = tab.layoutConfiguration else {
            return (contentSize.height, contentSize.height / 2)
        }

        let span = verticalDividerSpan(config: config)
        let topHeight = contentSize.height * verticalDivider
        let bottomHeight = contentSize.height - topHeight

        switch span {
        case .full:
            return (contentSize.height, contentSize.height / 2)
        case .firstHalf:
            // Top half only (bottom row merged)
            return (topHeight, topHeight / 2)
        case .secondHalf:
            // Bottom half only (top row merged)
            return (bottomHeight, topHeight + bottomHeight / 2)
        }
    }

    /// Calculates horizontal divider width and X position for triple layouts
    ///
    /// In triple layouts with a vertical expansion (left or right column merged),
    /// the horizontal divider should only span the column that's split.
    private var horizontalDividerGeometry: (width: CGFloat, x: CGFloat) {
        guard let config = tab.layoutConfiguration else {
            return (contentSize.width, contentSize.width / 2)
        }

        let span = horizontalDividerSpan(config: config)
        let leftWidth = contentSize.width * horizontalDivider
        let rightWidth = contentSize.width - leftWidth

        switch span {
        case .full:
            return (contentSize.width, contentSize.width / 2)
        case .firstHalf:
            // Left half only (right column merged)
            return (leftWidth, leftWidth / 2)
        case .secondHalf:
            // Right half only (left column merged)
            return (rightWidth, leftWidth + rightWidth / 2)
        }
    }
}

// MARK: - Divider Logic

extension UnifiedContentView {
    /// Determines if a vertical divider should be displayed
    ///
    /// **Visual Result:** Shows a vertical draggable line separating left and right panes
    ///
    /// **Cases:**
    /// - Same row: topLeft+topRight or bottomLeft+bottomRight
    /// - Diagonal: topLeft+bottomRight or topRight+bottomLeft (treated as vertical split)
    /// - Triple/Quad: Always needs vertical divider
    func needsVerticalDivider(config: LayoutConfiguration) -> Bool {
        let positions = Set(config.panePositions.values)

        let sameRowSplit = (positions.contains(.topLeft) && positions.contains(.topRight)) ||
            (positions.contains(.bottomLeft) && positions.contains(.bottomRight))

        let diagonalSplit = (positions.contains(.topLeft) && positions.contains(.bottomRight)) ||
            (positions.contains(.topRight) && positions.contains(.bottomLeft))

        return sameRowSplit || diagonalSplit || config.layoutType == .triple || config.layoutType == .quad
    }

    /// Determines if a horizontal divider should be displayed
    ///
    /// **Visual Result:** Shows a horizontal draggable line separating top and bottom panes
    ///
    /// **Cases:**
    /// - Same column: topLeft+bottomLeft or topRight+bottomRight
    /// - Triple/Quad: Always needs horizontal divider
    /// - Note: Diagonal splits use vertical divider only
    func needsHorizontalDivider(config: LayoutConfiguration) -> Bool {
        let positions = Set(config.panePositions.values)
        return positions.contains(.topLeft) && positions.contains(.bottomLeft) ||
            positions.contains(.topRight) && positions.contains(.bottomRight) ||
            config.layoutType == .triple || config.layoutType == .quad
    }

    /// Determines which portion of the vertical divider should be active in triple layouts
    ///
    /// When one pane spans the full width (top or bottom row merged), the vertical divider
    /// only exists in the row that's actually split.
    func verticalDividerSpan(config: LayoutConfiguration) -> DividerSpan {
        guard config.layoutType == .triple else { return .full }

        // First check for explicit expansions
        for (position, direction) in config.expansions {
            switch (position, direction) {
            case (.topLeft, .right), (.topRight, .left):
                // Top row merged → vertical divider only in bottom half
                return .secondHalf
            case (.bottomLeft, .right), (.bottomRight, .left):
                // Bottom row merged → vertical divider only in top half
                return .firstHalf
            default:
                continue
            }
        }

        // No explicit expansion - infer from which slot is missing
        // This matches the default behavior in tripleLayoutFrame
        let positions = Set(config.panePositions.values)
        let missingTopLeft = !positions.contains(.topLeft)
        let missingTopRight = !positions.contains(.topRight)
        let missingBottomLeft = !positions.contains(.bottomLeft)
        let missingBottomRight = !positions.contains(.bottomRight)

        // Check if any pane should expand horizontally to cover the missing slot
        // Following the same priority as frame calculations:
        // - topLeft prefers down over right
        // - topRight prefers down over left
        // - bottomLeft prefers up over right
        // - bottomRight prefers up over left
        //
        // So horizontal expansions only happen when the vertical expansion isn't applicable

        // Missing topRight: topLeft could expand right (if topLeft exists and bottomLeft doesn't need topLeft to expand down)
        if missingTopRight, positions.contains(.topLeft), !missingBottomLeft {
            return .secondHalf // Top row merged
        }

        // Missing topLeft: topRight could expand left (if topRight exists and bottomRight doesn't need topRight to expand down)
        if missingTopLeft, positions.contains(.topRight), !missingBottomRight {
            return .secondHalf // Top row merged
        }

        // Missing bottomRight: bottomLeft could expand right (if bottomLeft exists and topLeft doesn't need it to expand up)
        if missingBottomRight, positions.contains(.bottomLeft), !missingTopLeft {
            return .firstHalf // Bottom row merged
        }

        // Missing bottomLeft: bottomRight could expand left (if bottomRight exists and topRight doesn't need it to expand up)
        if missingBottomLeft, positions.contains(.bottomRight), !missingTopRight {
            return .firstHalf // Bottom row merged
        }

        return .full
    }

    /// Determines which portion of the horizontal divider should be active in triple layouts
    ///
    /// When one pane spans the full height (left or right column merged), the horizontal divider
    /// only exists in the column that's actually split.
    ///
    /// Priority: HORIZONTAL expansion first (returns .full), then vertical expansion (returns partial).
    /// This matches the visual behavior where horizontal expansions take precedence.
    func horizontalDividerSpan(config: LayoutConfiguration) -> DividerSpan {
        guard config.layoutType == .triple else { return .full }

        // First check for explicit expansions
        for (position, direction) in config.expansions {
            switch (position, direction) {
            case (.topLeft, .down), (.bottomLeft, .up):
                // Left column merged → horizontal divider only in right half
                return .secondHalf
            case (.topRight, .down), (.bottomRight, .up):
                // Right column merged → horizontal divider only in left half
                return .firstHalf
            case (.topLeft, .right), (.topRight, .left), (.bottomLeft, .right), (.bottomRight, .left):
                // Horizontal expansion → horizontal divider spans full width
                return .full
            default:
                continue
            }
        }

        // No explicit expansion - infer from which slot is missing
        let positions = Set(config.panePositions.values)
        let missingTopLeft = !positions.contains(.topLeft)
        let missingTopRight = !positions.contains(.topRight)
        let missingBottomLeft = !positions.contains(.bottomLeft)
        let missingBottomRight = !positions.contains(.bottomRight)

        // HORIZONTAL expansion takes priority for horizontal divider
        // When a pane expands left/right, the horizontal divider is full width
        // because the expanded pane creates a top-bottom boundary on both sides

        // Missing topRight: topLeft could expand right
        if missingTopRight, positions.contains(.topLeft), !missingBottomLeft {
            return .full
        }

        // Missing topLeft: topRight could expand left
        if missingTopLeft, positions.contains(.topRight), !missingBottomRight {
            return .full
        }

        // Missing bottomRight: bottomLeft could expand right
        if missingBottomRight, positions.contains(.bottomLeft), !missingTopLeft {
            return .full
        }

        // Missing bottomLeft: bottomRight could expand left
        if missingBottomLeft, positions.contains(.bottomRight), !missingTopRight {
            return .full
        }

        // Fall back to vertical expansion (one column is full-height)

        // Missing bottomLeft: topLeft could expand down
        if missingBottomLeft, positions.contains(.topLeft) {
            return .secondHalf // Left column merged
        }

        // Missing topLeft: bottomLeft could expand up
        if missingTopLeft, positions.contains(.bottomLeft) {
            return .secondHalf // Left column merged
        }

        // Missing bottomRight: topRight could expand down
        if missingBottomRight, positions.contains(.topRight) {
            return .firstHalf // Right column merged
        }

        // Missing topRight: bottomRight could expand up
        if missingTopRight, positions.contains(.bottomRight) {
            return .firstHalf // Right column merged
        }

        return .full
    }

    /// Handles user dragging of dividers to adjust pane sizes
    ///
    /// **Visual Result:** Dragging vertical divider adjusts left/right pane widths,
    /// dragging horizontal divider adjusts top/bottom pane heights
    ///
    /// **Behavior:**
    /// - Free movement during drag with clamping to min/max ratios (0.2-0.8)
    /// - Snaps only when released (in finalizeDividerDrag) if close to preset ratios
    /// - Updates immediately during drag for responsive feel
    func handleDividerDrag(_ type: DividerType, delta: CGFloat) {
        if activeDivider != type {
            dividerDragStartValue = type == .vertical ? horizontalDivider : verticalDivider
        }
        activeDivider = type

        switch type {
        case .vertical:
            let newPosition = dividerDragStartValue + (delta / contentSize.width)
            horizontalDivider = clamp(newPosition, min: Layout.minPaneRatio, max: Layout.maxPaneRatio)

        case .horizontal:
            let newPosition = dividerDragStartValue + (delta / contentSize.height)
            verticalDivider = clamp(newPosition, min: Layout.minPaneRatio, max: Layout.maxPaneRatio)
        }
    }

    /// Finalizes divider drag by snapping to nearby preset ratios if close enough
    /// and persisting the new positions to the tab's layout configuration.
    func finalizeDividerDrag(_ type: DividerType) {
        switch type {
        case .vertical:
            horizontalDivider = snapValue(horizontalDivider)
        case .horizontal:
            verticalDivider = snapValue(verticalDivider)
        }
        activeDivider = nil

        // Persist divider positions to tab's layout configuration.
        // This ensures divider positions survive tab switches.
        // Only save if we're in normal multi-pane mode (not layout editing mode).
        if !windowState.isInLayoutMode, var config = tab.layoutConfiguration {
            config.horizontalDivider = workingConfig.horizontalDivider
            config.verticalDivider = workingConfig.verticalDivider
            tab.layoutConfiguration = config
        }
    }

    func snapValue(_ value: CGFloat) -> CGFloat {
        for snapPoint in Layout.snapPoints {
            if abs(value - snapPoint) < Layout.snapThreshold {
                return snapPoint
            }
        }
        return value
    }

    func clamp(_ value: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, min), max)
    }
}
