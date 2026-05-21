import SwiftUI

// MARK: - Frame Calculations

extension UnifiedContentView {
    /// Recalculates and caches frame positions for all visible panes
    ///
    /// This method is the primary frame calculation entry point, computing precise CGRect frames for each visible page
    /// based on the current mode (single, multi-pane, or layout editing). Frames are cached to avoid redundant calculations
    /// during animations and rendering.
    ///
    /// **Visual Result:** Determines where each webpage appears on screen - their position and size
    ///
    /// **Performance:** Only called when layout changes (mode switches, window resize, divider drags)
    /// to avoid unnecessary recalculations on every frame render
    ///
    /// - Parameter animated: Whether to animate the frame transition. Set to `false` for
    ///   geometry-driven updates (window resize) to avoid animation churn.
    func updateCachedFrames(animated: Bool = true) {
        guard contentSize != .zero else { return }

        var newFrames: [UUID: CGRect] = [:]

        for page in visiblePages {
            let frame: CGRect

            if windowState.isInLayoutMode {
                if let position = layoutGrid.position(for: page) {
                    frame = layoutModeFrame(at: position)
                } else {
                    continue
                }
            } else if tab.isMultiPage {
                if let position = tab.layoutConfiguration?.panePositions[page.id] {
                    frame = multiPaneFrame(at: position)
                } else {
                    frame = CGRect(origin: .zero, size: contentSize)
                }
            } else {
                frame = CGRect(origin: .zero, size: contentSize)
            }

            if frame.width > 0, frame.height > 0 {
                newFrames[page.id] = frame
            }
        }

        if animated {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                cachedFrames = newFrames
            }
        } else {
            cachedFrames = newFrames
        }
    }

    /// Calculates the frame for a pane in layout editing mode (2×2 grid with expansions)
    ///
    /// **Visual Result:** Creates the 2×2 grid layout with asymmetric padding:
    /// - Left edge: 0pt (MainContentView already adds 8pt gap from sidebar)
    /// - Top/Right/Bottom edges: 8pt padding
    /// - Spacing between slots: 8pt
    ///
    /// **UI Appearance:**
    /// - 4 equal quadrants by default
    /// - Panes can double in width (expand right/left) or height (expand down/up)
    /// - Consistent spacing maintained for visual alignment
    func layoutModeFrame(at position: PanePosition) -> CGRect {
        let leftPadding: CGFloat = 0
        let rightPadding: CGFloat = 8
        let topPadding: CGFloat = 8
        let bottomPadding: CGFloat = 8
        let halfSpacing: CGFloat = 4

        let availableWidth = contentSize.width - leftPadding - rightPadding - (halfSpacing * 2)
        let availableHeight = contentSize.height - topPadding - bottomPadding - (halfSpacing * 2)
        let slotWidth = availableWidth / 2
        let slotHeight = availableHeight / 2

        let expansion = workingConfig.expansions[position]
        let isExpandedRight = expansion == .right
        let isExpandedDown = expansion == .down
        let isExpandedLeft = expansion == .left
        let isExpandedUp = expansion == .up

        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat

        switch position {
        case .topLeft, .single:
            x = leftPadding
            y = topPadding
            width = isExpandedRight ? (slotWidth * 2 + halfSpacing * 2) : slotWidth
            height = isExpandedDown ? (slotHeight * 2 + halfSpacing * 2) : slotHeight

        case .topRight:
            x = isExpandedLeft ? leftPadding : (leftPadding + slotWidth + (halfSpacing * 2))
            y = topPadding
            width = isExpandedLeft ? (slotWidth * 2 + halfSpacing * 2) : slotWidth
            height = isExpandedDown ? (slotHeight * 2 + halfSpacing * 2) : slotHeight

        case .bottomLeft:
            x = leftPadding
            y = isExpandedUp ? topPadding : (topPadding + slotHeight + (halfSpacing * 2))
            width = isExpandedRight ? (slotWidth * 2 + halfSpacing * 2) : slotWidth
            height = isExpandedUp ? (slotHeight * 2 + halfSpacing * 2) : slotHeight

        case .bottomRight:
            x = isExpandedLeft ? leftPadding : (leftPadding + slotWidth + (halfSpacing * 2))
            y = isExpandedUp ? topPadding : (topPadding + slotHeight + (halfSpacing * 2))
            width = isExpandedLeft ? (slotWidth * 2 + halfSpacing * 2) : slotWidth
            height = isExpandedUp ? (slotHeight * 2 + halfSpacing * 2) : slotHeight
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Calculates the frame for a pane in normal multi-pane mode (with user-adjustable dividers)
    ///
    /// **Visual Result:** Creates flexible split-view layouts with draggable dividers separating panes.
    /// Supports 2, 3, or 4 panes with intelligent layout based on which quadrants are occupied.
    ///
    /// **UI Appearance:**
    /// - **Split (2 panes):** Vertical or horizontal split based on pane positions
    /// - **Triple (3 panes):** One expanded pane covers the empty quadrant
    /// - **Quad (4 panes):** Standard 2×2 grid with dividers
    /// - Dividers positioned at user-defined ratios (default 0.5)
    func multiPaneFrame(at position: PanePosition) -> CGRect {
        guard let config = tab.layoutConfiguration else {
            return CGRect(origin: .zero, size: contentSize)
        }

        let divider = Layout.dividerGap
        let positions = Set(config.panePositions.values)

        switch config.layoutType {
        case .single:
            return CGRect(origin: .zero, size: contentSize)

        case .split:
            return splitLayoutFrame(at: position, positions: positions, divider: divider)

        case .triple:
            return tripleLayoutFrame(at: position, positions: positions, divider: divider)

        case .quad:
            return quadLayoutFrame(at: position, divider: divider)
        }
    }

    private func splitLayoutFrame(at position: PanePosition, positions: Set<PanePosition>, divider _: CGFloat) -> CGRect {
        // Note: divider parameter kept for API compatibility but not used.
        // Panes extend to their natural boundaries; the divider is drawn on top.
        // This avoids sub-pixel gaps that cause visual misalignment.

        let inSameRow = (positions.contains(.topLeft) && positions.contains(.topRight)) ||
            (positions.contains(.bottomLeft) && positions.contains(.bottomRight))

        let isDiagonal = (positions.contains(.topLeft) && positions.contains(.bottomRight)) ||
            (positions.contains(.topRight) && positions.contains(.bottomLeft))

        if inSameRow || isDiagonal {
            let splitX = contentSize.width * horizontalDivider

            switch position {
            case .topLeft, .bottomLeft:
                return CGRect(x: 0, y: 0, width: splitX, height: contentSize.height)
            case .topRight, .bottomRight:
                return CGRect(x: splitX, y: 0, width: contentSize.width - splitX, height: contentSize.height)
            default:
                return CGRect(origin: .zero, size: contentSize)
            }
        } else {
            let splitY = contentSize.height * verticalDivider

            switch position {
            case .topLeft, .topRight:
                return CGRect(x: 0, y: 0, width: contentSize.width, height: splitY)
            case .bottomLeft, .bottomRight:
                return CGRect(x: 0, y: splitY, width: contentSize.width, height: contentSize.height - splitY)
            default:
                return CGRect(origin: .zero, size: contentSize)
            }
        }
    }

    private func tripleLayoutFrame(at position: PanePosition, positions: Set<PanePosition>, divider _: CGFloat) -> CGRect {
        // Note: divider parameter kept for API compatibility but not used.
        // Panes extend to their natural boundaries; the divider is drawn on top.
        // This avoids sub-pixel gaps that cause visual misalignment.

        guard let config = tab.layoutConfiguration else {
            return CGRect(origin: .zero, size: contentSize)
        }

        let splitX = contentSize.width * horizontalDivider
        let splitY = contentSize.height * verticalDivider

        let missingTopLeft = !positions.contains(.topLeft)
        let missingTopRight = !positions.contains(.topRight)
        let missingBottomLeft = !positions.contains(.bottomLeft)
        let missingBottomRight = !positions.contains(.bottomRight)

        // Check which pane has an expansion that covers the missing slot
        let expansionCoveringMissing = findExpansionCoveringMissingSlot(
            positions: positions,
            expansions: config.expansions,
        )

        switch position {
        case .topLeft:
            let shouldExpandDown = missingBottomLeft &&
                (expansionCoveringMissing == nil || expansionCoveringMissing == .topLeft)
            let shouldExpandRight = missingTopRight &&
                (expansionCoveringMissing == nil || expansionCoveringMissing == .topLeft)

            if shouldExpandDown {
                return CGRect(x: 0, y: 0, width: splitX, height: contentSize.height)
            } else if shouldExpandRight {
                return CGRect(x: 0, y: 0, width: contentSize.width, height: splitY)
            } else {
                return CGRect(x: 0, y: 0, width: splitX, height: splitY)
            }

        case .topRight:
            let shouldExpandDown = missingBottomRight &&
                (expansionCoveringMissing == nil || expansionCoveringMissing == .topRight)
            let shouldExpandLeft = missingTopLeft &&
                (expansionCoveringMissing == nil || expansionCoveringMissing == .topRight)

            if shouldExpandDown {
                return CGRect(x: splitX, y: 0, width: contentSize.width - splitX, height: contentSize.height)
            } else if shouldExpandLeft {
                return CGRect(x: 0, y: 0, width: contentSize.width, height: splitY)
            } else {
                return CGRect(x: splitX, y: 0, width: contentSize.width - splitX, height: splitY)
            }

        case .bottomLeft:
            let shouldExpandUp = missingTopLeft &&
                (expansionCoveringMissing == nil || expansionCoveringMissing == .bottomLeft)
            let shouldExpandRight = missingBottomRight &&
                (expansionCoveringMissing == nil || expansionCoveringMissing == .bottomLeft)

            if shouldExpandUp {
                return CGRect(x: 0, y: 0, width: splitX, height: contentSize.height)
            } else if shouldExpandRight {
                return CGRect(x: 0, y: splitY, width: contentSize.width, height: contentSize.height - splitY)
            } else {
                return CGRect(x: 0, y: splitY, width: splitX, height: contentSize.height - splitY)
            }

        case .bottomRight:
            let shouldExpandUp = missingTopRight &&
                (expansionCoveringMissing == nil || expansionCoveringMissing == .bottomRight)
            let shouldExpandLeft = missingBottomLeft &&
                (expansionCoveringMissing == nil || expansionCoveringMissing == .bottomRight)

            if shouldExpandUp {
                return CGRect(x: splitX, y: 0, width: contentSize.width - splitX, height: contentSize.height)
            } else if shouldExpandLeft {
                return CGRect(x: 0, y: splitY, width: contentSize.width, height: contentSize.height - splitY)
            } else {
                return CGRect(x: splitX, y: splitY, width: contentSize.width - splitX, height: contentSize.height - splitY)
            }

        case .single:
            return CGRect(origin: .zero, size: contentSize)
        }
    }

    /// Finds which pane position has an expansion that covers the missing slot
    ///
    /// In a triple layout, one slot is missing. If the user explicitly expanded a pane
    /// to cover that slot, return that pane's position. Otherwise return nil.
    private func findExpansionCoveringMissingSlot(
        positions: Set<PanePosition>,
        expansions: [PanePosition: ExpansionDirection],
    ) -> PanePosition? {
        let allPositions: Set<PanePosition> = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        let missingPositions = allPositions.subtracting(positions)

        guard let missingPosition = missingPositions.first else { return nil }

        for (expandedPosition, direction) in expansions {
            let coveredPosition: PanePosition? = switch (expandedPosition, direction) {
            case (.topLeft, .right): .topRight
            case (.topLeft, .down): .bottomLeft
            case (.topRight, .left): .topLeft
            case (.topRight, .down): .bottomRight
            case (.bottomLeft, .right): .bottomRight
            case (.bottomLeft, .up): .topLeft
            case (.bottomRight, .left): .bottomLeft
            case (.bottomRight, .up): .topRight
            default: nil
            }

            if coveredPosition == missingPosition {
                return expandedPosition
            }
        }

        return nil
    }

    private func quadLayoutFrame(at position: PanePosition, divider _: CGFloat) -> CGRect {
        // Note: divider parameter kept for API compatibility but not used.
        // Panes extend to their natural boundaries; the divider is drawn on top.
        // This avoids sub-pixel gaps that cause visual misalignment.

        let splitX = contentSize.width * horizontalDivider
        let splitY = contentSize.height * verticalDivider

        switch position {
        case .topLeft:
            return CGRect(x: 0, y: 0, width: splitX, height: splitY)
        case .topRight:
            return CGRect(x: splitX, y: 0, width: contentSize.width - splitX, height: splitY)
        case .bottomLeft:
            return CGRect(x: 0, y: splitY, width: splitX, height: contentSize.height - splitY)
        case .bottomRight:
            return CGRect(x: splitX, y: splitY, width: contentSize.width - splitX, height: contentSize.height - splitY)
        case .single:
            return CGRect(origin: .zero, size: contentSize)
        }
    }
}

// MARK: - Effective Frame

extension UnifiedContentView {
    /// Calculate the effective frame for a page, accounting for temporary displacement
    ///
    /// **Visual Result:** During drag operations, displaced panes smoothly animate to temporary positions
    /// to make room for the dragged pane. This method returns the correct frame whether a pane is in its
    /// original position or temporarily displaced.
    ///
    /// **Tab Switching Optimization:** When switching tabs, we read the WKWebView's actual frame
    /// directly if available. This is the most accurate source since it reflects the exact size
    /// the webView was rendered at. Only fall back to computation when no webView exists yet.
    func effectiveFrame(for page: TabPage) -> CGRect {
        // Check for temporary displacement during layout mode drag operations
        if let tempPosition = temporarilyDisplacedPanes[page.id],
           let currentPosition = layoutGrid.position(for: page),
           tempPosition != currentPosition,
           windowState.isInLayoutMode {
            return layoutModeFrame(at: tempPosition)
        }

        // Try cached frame first (most common path during normal operation)
        if let cached = cachedFrames[page.id] {
            return cached
        }
        // Cache miss during tab switch — read the WKWebView's actual frame if available.
        // The webView already has the correct frame from its previous display, so we use
        // that directly instead of recomputing. This avoids the "squeeze" artifact when
        // switching between tabs with different layout types.
        // IMPORTANT: Use existingPage to avoid creating pages during body evaluation.
        if let webPage = pagePool.existingPage(for: page) {
            let webViewFrame = webPage.backingWebView.frame
            // Only use if the frame has valid dimensions (webView was displayed before)
            if webViewFrame.width > 0, webViewFrame.height > 0 {
                return webViewFrame
            }
        }

        // No webView yet or webView has no valid frame — compute synchronously
        return computeFrame(for: page)
    }

    /// Computes the frame for a page based on current mode and layout configuration.
    ///
    /// Used as a fallback when cached frames aren't available (e.g., during tab switches).
    /// This method reads divider values directly from `tab.layoutConfiguration` instead of
    /// `workingConfig` to ensure correct frames even before `reinitializeForNewTab` runs.
    private func computeFrame(for page: TabPage) -> CGRect {
        guard contentSize != .zero else {
            return .zero
        }

        if windowState.isInLayoutMode {
            if let position = layoutGrid.position(for: page) {
                return layoutModeFrame(at: position)
            }
        } else if tab.isMultiPage, let config = tab.layoutConfiguration {
            if let position = config.panePositions[page.id] {
                // Compute frame using tab's actual configuration, not workingConfig.
                // This ensures correct frames during tab switches before sync happens.
                return computeMultiPaneFrame(at: position, using: config)
            }
        }

        // Single page or fallback - fill container
        return CGRect(origin: .zero, size: contentSize)
    }

    /// Computes a multi-pane frame using the provided configuration's divider values.
    ///
    /// This is similar to `multiPaneFrame` but takes an explicit configuration parameter
    /// to avoid reading from `workingConfig` during tab switches.
    func computeMultiPaneFrame(at position: PanePosition, using config: LayoutConfiguration) -> CGRect {
        let positions = Set(config.panePositions.values)
        let hDivider = CGFloat(config.horizontalDivider)
        let vDivider = CGFloat(config.verticalDivider)

        switch config.layoutType {
        case .single:
            return CGRect(origin: .zero, size: contentSize)

        case .split:
            return computeSplitFrame(at: position, positions: positions, hDivider: hDivider, vDivider: vDivider)

        case .triple:
            return computeTripleFrame(at: position, positions: positions, config: config, hDivider: hDivider, vDivider: vDivider)

        case .quad:
            return computeQuadFrame(at: position, hDivider: hDivider, vDivider: vDivider)
        }
    }

    private func computeSplitFrame(at position: PanePosition, positions: Set<PanePosition>, hDivider: CGFloat, vDivider: CGFloat) -> CGRect {
        let inSameRow = (positions.contains(.topLeft) && positions.contains(.topRight)) ||
            (positions.contains(.bottomLeft) && positions.contains(.bottomRight))

        let isDiagonal = (positions.contains(.topLeft) && positions.contains(.bottomRight)) ||
            (positions.contains(.topRight) && positions.contains(.bottomLeft))

        if inSameRow || isDiagonal {
            let splitX = contentSize.width * hDivider
            switch position {
            case .topLeft, .bottomLeft:
                return CGRect(x: 0, y: 0, width: splitX, height: contentSize.height)
            case .topRight, .bottomRight:
                return CGRect(x: splitX, y: 0, width: contentSize.width - splitX, height: contentSize.height)
            default:
                return CGRect(origin: .zero, size: contentSize)
            }
        } else {
            let splitY = contentSize.height * vDivider
            switch position {
            case .topLeft, .topRight:
                return CGRect(x: 0, y: 0, width: contentSize.width, height: splitY)
            case .bottomLeft, .bottomRight:
                return CGRect(x: 0, y: splitY, width: contentSize.width, height: contentSize.height - splitY)
            default:
                return CGRect(origin: .zero, size: contentSize)
            }
        }
    }

    private func computeTripleFrame(at position: PanePosition, positions: Set<PanePosition>, config: LayoutConfiguration, hDivider: CGFloat, vDivider: CGFloat) -> CGRect {
        let splitX = contentSize.width * hDivider
        let splitY = contentSize.height * vDivider

        let missingTopLeft = !positions.contains(.topLeft)
        let missingTopRight = !positions.contains(.topRight)
        let missingBottomLeft = !positions.contains(.bottomLeft)
        let missingBottomRight = !positions.contains(.bottomRight)

        let expansionCoveringMissing = findExpansionCoveringMissingSlot(positions: positions, expansions: config.expansions)

        switch position {
        case .topLeft:
            let shouldExpandDown = missingBottomLeft && (expansionCoveringMissing == nil || expansionCoveringMissing == .topLeft)
            let shouldExpandRight = missingTopRight && (expansionCoveringMissing == nil || expansionCoveringMissing == .topLeft)
            if shouldExpandDown {
                return CGRect(x: 0, y: 0, width: splitX, height: contentSize.height)
            } else if shouldExpandRight {
                return CGRect(x: 0, y: 0, width: contentSize.width, height: splitY)
            } else {
                return CGRect(x: 0, y: 0, width: splitX, height: splitY)
            }

        case .topRight:
            let shouldExpandDown = missingBottomRight && (expansionCoveringMissing == nil || expansionCoveringMissing == .topRight)
            let shouldExpandLeft = missingTopLeft && (expansionCoveringMissing == nil || expansionCoveringMissing == .topRight)
            if shouldExpandDown {
                return CGRect(x: splitX, y: 0, width: contentSize.width - splitX, height: contentSize.height)
            } else if shouldExpandLeft {
                return CGRect(x: 0, y: 0, width: contentSize.width, height: splitY)
            } else {
                return CGRect(x: splitX, y: 0, width: contentSize.width - splitX, height: splitY)
            }

        case .bottomLeft:
            let shouldExpandUp = missingTopLeft && (expansionCoveringMissing == nil || expansionCoveringMissing == .bottomLeft)
            let shouldExpandRight = missingBottomRight && (expansionCoveringMissing == nil || expansionCoveringMissing == .bottomLeft)
            if shouldExpandUp {
                return CGRect(x: 0, y: 0, width: splitX, height: contentSize.height)
            } else if shouldExpandRight {
                return CGRect(x: 0, y: splitY, width: contentSize.width, height: contentSize.height - splitY)
            } else {
                return CGRect(x: 0, y: splitY, width: splitX, height: contentSize.height - splitY)
            }

        case .bottomRight:
            let shouldExpandUp = missingTopRight && (expansionCoveringMissing == nil || expansionCoveringMissing == .bottomRight)
            let shouldExpandLeft = missingBottomLeft && (expansionCoveringMissing == nil || expansionCoveringMissing == .bottomRight)
            if shouldExpandUp {
                return CGRect(x: splitX, y: 0, width: contentSize.width - splitX, height: contentSize.height)
            } else if shouldExpandLeft {
                return CGRect(x: 0, y: splitY, width: contentSize.width, height: contentSize.height - splitY)
            } else {
                return CGRect(x: splitX, y: splitY, width: contentSize.width - splitX, height: contentSize.height - splitY)
            }

        case .single:
            return CGRect(origin: .zero, size: contentSize)
        }
    }

    private func computeQuadFrame(at position: PanePosition, hDivider: CGFloat, vDivider: CGFloat) -> CGRect {
        let splitX = contentSize.width * hDivider
        let splitY = contentSize.height * vDivider

        switch position {
        case .topLeft:
            return CGRect(x: 0, y: 0, width: splitX, height: splitY)
        case .topRight:
            return CGRect(x: splitX, y: 0, width: contentSize.width - splitX, height: splitY)
        case .bottomLeft:
            return CGRect(x: 0, y: splitY, width: splitX, height: contentSize.height - splitY)
        case .bottomRight:
            return CGRect(x: splitX, y: splitY, width: contentSize.width - splitX, height: contentSize.height - splitY)
        case .single:
            return CGRect(origin: .zero, size: contentSize)
        }
    }
}
