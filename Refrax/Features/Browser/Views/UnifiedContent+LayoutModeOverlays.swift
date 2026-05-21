import SwiftUI

// MARK: - Layout Mode Overlays

extension UnifiedContentView {
    /// Empty slots layer shown below webpages in layout mode
    @ViewBuilder
    var emptySlots: some View {
        ZStack(alignment: .topLeading) {
            ForEach(emptyGridPositions, id: \.self) { position in
                emptySlotVisual(at: position)
            }

            DragTrackingView(
                onDragMove: { location, pasteboard in
                    handleDragMove(at: location, pasteboard: pasteboard)
                },
                onDragExit: {
                    clearDragState()
                },
                onDrop: { pasteboard, location in
                    guard let targetPosition = findEmptySlotForDropLocation(location) else {
                        return false
                    }

                    // Try Refrax tab ID first (from hybrid drag system)
                    let tabIDs = DragPasteboardWriter.extractTabIDs(from: pasteboard)
                    if !tabIDs.isEmpty {
                        return handleDrop(at: targetPosition, items: tabIDs.map(\.uuidString))
                    }

                    // Fall back to plain string (legacy .draggable)
                    guard let string = pasteboard.string(forType: .string) else {
                        return false
                    }
                    return handleDrop(at: targetPosition, items: [string])
                },
            )
        }
        .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
    }

    /// Control buttons and highlights layer shown above webpages in layout mode
    @ViewBuilder
    var layoutModeControls: some View {
        ZStack(alignment: .topLeading) {
            if let highlightPosition = highlightedDropTarget {
                let frame = layoutModeFrame(at: highlightPosition)
                RoundedRectangle(cornerRadius: Layout.layoutModeCornerRadius)
                    .strokeBorder(Color.appAccentColor, lineWidth: 3)
                    .background(
                        RoundedRectangle(cornerRadius: Layout.layoutModeCornerRadius)
                            .fill(Color.appAccentColor.opacity(0.1)),
                    )
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.minX, y: frame.minY)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }

            if let invalidPosition = invalidDragTarget {
                invalidDragIndicator(at: invalidPosition)
            }

            ForEach(visiblePages) { page in
                if let position = layoutGrid.position(for: page),
                   let frame = cachedFrames[page.id],
                   draggedPaneID != page.id {
                    controlButtons(for: page, at: position, frame: frame)
                        .zIndex(1_000)
                }
            }
        }
    }

    /// Find which empty slot contains a given point
    func findEmptySlotForDropLocation(_ location: CGPoint) -> PanePosition? {
        for position in emptyGridPositions {
            let frame = layoutModeFrame(at: position)
            if frame.contains(location) {
                return position
            }
        }
        return nil
    }
}

// MARK: - Drag Validation

extension UnifiedContentView {
    /// Handles drag movement with validation
    func handleDragMove(at location: CGPoint, pasteboard: NSPasteboard) -> DragValidationResult {
        guard let targetPosition = findEmptySlotForDropLocation(location) else {
            clearDragState()
            return .noTarget
        }

        // Try Refrax tab ID first (from hybrid drag system)
        var tabID: UUID?
        let tabIDs = DragPasteboardWriter.extractTabIDs(from: pasteboard)
        if let firstID = tabIDs.first {
            tabID = firstID
        } else if let string = pasteboard.string(forType: .string) {
            // Fall back to plain string (legacy .draggable)
            tabID = UUID(uuidString: string)
        }

        guard let tabID, let draggedTab = tabManager.state.tab(for: tabID) else {
            clearDragState()
            return .noTarget
        }

        // Cannot drop a tab on itself
        if draggedTab.id == tab.id {
            clearDragState()
            return .noTarget
        }

        if draggedTab.isMultiPage || draggedTab.pages.count > 1 {
            withAnimation(.snappy(duration: 0.2)) {
                dropTarget = nil
                invalidDragTarget = targetPosition
                invalidDragMessage = "Multi-page tabs cannot be added to layouts"
            }
            return .invalid(message: "Multi-page tabs cannot be added to layouts")
        }

        withAnimation(.snappy(duration: 0.2)) {
            invalidDragTarget = nil
            invalidDragMessage = nil
            if dropTarget != targetPosition {
                dropTarget = targetPosition
            }
        }
        return .valid
    }

    /// Clears all drag-related state
    func clearDragState() {
        withAnimation(.snappy(duration: 0.2)) {
            dropTarget = nil
            invalidDragTarget = nil
            invalidDragMessage = nil
        }
    }
}

// MARK: - Invalid Drag Indicator

extension UnifiedContentView {
    @ViewBuilder
    func invalidDragIndicator(at position: PanePosition) -> some View {
        let frame = layoutModeFrame(at: position)

        ZStack {
            RoundedRectangle(cornerRadius: Layout.layoutModeCornerRadius)
                .strokeBorder(Color.red, lineWidth: 3)
                .background(
                    RoundedRectangle(cornerRadius: Layout.layoutModeCornerRadius)
                        .fill(Color.red.opacity(0.1)),
                )

            if let message = invalidDragMessage {
                VStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(.red)

                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }
            }
        }
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .allowsHitTesting(false)
        .transition(.opacity)
    }
}

// MARK: - Empty Slot Visual

extension UnifiedContentView {
    @ViewBuilder
    func emptySlotVisual(at position: PanePosition) -> some View {
        let frame = layoutModeFrame(at: position)
        let isInvalidTarget = invalidDragTarget == position

        ZStack {
            RoundedRectangle(cornerRadius: Layout.layoutModeCornerRadius)
                .fill(.ultraThinMaterial)

            if !isInvalidTarget {
                VStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 72))
                        .foregroundStyle(.tertiary)

                    Text("Click or drop tab")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            glassRim(cornerRadius: Layout.layoutModeCornerRadius)

            if dropTarget == position, !isInvalidTarget {
                RoundedRectangle(cornerRadius: Layout.layoutModeCornerRadius)
                    .strokeBorder(Color.appAccentColor, lineWidth: 2)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .shadow(color: .black.opacity(0.15), radius: 3, x: 1, y: 1)
        .scaleEffect(dropTarget == position && !isInvalidTarget ? 1.02 : 1.0)
        .animation(.snappy(duration: 0.2), value: dropTarget)
        .contentShape(Rectangle())
        .onTapGesture {
            handleEmptySlotTap(at: position)
        }
        .offset(x: frame.minX, y: frame.minY)
    }
}

// MARK: - Control Buttons

extension UnifiedContentView {
    @ViewBuilder
    func controlButtons(for _: TabPage, at position: PanePosition, frame: CGRect) -> some View {
        ZStack {
            if layoutGrid.filledPositions.count > 1 {
                VStack {
                    HStack {
                        GlassButton(
                            systemName: "arrow.left.to.line.square",
                            size: 56.6,
                            fontSize: 22.6,
                        ) {
                            movePaneToTabList(at: position)
                        }
                        .offset(x: 16, y: 16)

                        Spacer()
                    }
                    Spacer()
                }
            }

            if windowState.activeSpace?.referenceTabCount ?? 0 < 4 {
                VStack {
                    HStack {
                        Spacer()

                        GlassButton(
                            systemName: "arrow.right.to.line.square",
                            size: 56.6,
                            fontSize: 22.6,
                        ) {
                            moveToReferencePane(at: position)
                        }
                        .offset(x: -16, y: 16)
                    }
                    Spacer()
                }
            }

            expansionButtons(for: position)
        }
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .allowsHitTesting(true)
    }

    @ViewBuilder
    private func expansionButtons(for position: PanePosition) -> some View {
        if canExpandDown(from: position) {
            VStack {
                Spacer()
                GlassButton(systemName: "arrow.down", size: 80, fontSize: 32) {
                    expandDown(from: position)
                }
                .offset(y: -16)
            }
        }

        if canExpandUp(from: position) {
            VStack {
                GlassButton(systemName: "arrow.up", size: 80, fontSize: 32) {
                    expandUp(from: position)
                }
                .offset(y: 16)
                Spacer()
            }
        }

        if canExpandRight(from: position) {
            HStack {
                Spacer()
                GlassButton(systemName: "arrow.right", size: 80, fontSize: 32) {
                    expandRight(from: position)
                }
                .offset(x: -16)
            }
        }

        if canExpandLeft(from: position) {
            HStack {
                GlassButton(systemName: "arrow.left", size: 80, fontSize: 32) {
                    expandLeft(from: position)
                }
                .offset(x: 16)
                Spacer()
            }
        }

        if canCollapseRight(at: position) {
            HStack {
                Spacer()
                GlassButton(systemName: "arrow.left", size: 80, fontSize: 32) {
                    collapseRight(at: position)
                }
                .offset(x: -16)
            }
        }

        if canCollapseLeft(at: position) {
            HStack {
                GlassButton(systemName: "arrow.right", size: 80, fontSize: 32) {
                    collapseLeft(at: position)
                }
                .offset(x: 16)
                Spacer()
            }
        }

        if canCollapseDown(at: position) {
            VStack {
                Spacer()
                GlassButton(systemName: "arrow.up", size: 80, fontSize: 32) {
                    collapseDown(at: position)
                }
                .offset(y: -16)
            }
        }

        if canCollapseUp(at: position) {
            VStack {
                GlassButton(systemName: "arrow.down", size: 80, fontSize: 32) {
                    collapseUp(at: position)
                }
                .offset(y: 16)
                Spacer()
            }
        }
    }
}
