import SwiftUI

// MARK: - Layout Constants

/// Layout constants for SpacePicker, extracted to file scope to avoid
/// issues with static stored properties in generic types.
private enum SpacePickerLayout {
    static let height: CGFloat = 32
    static let cornerRadius: CGFloat = 16
    static let highlightInset: CGFloat = 2
    static let iconOnlyWidth: CGFloat = 40
    static let iconWidth: CGFloat = 20
    static let iconTextSpacing: CGFloat = 4
    static let segmentPadding: CGFloat = 16
    static let dividerHeight: CGFloat = 16
    static let iconFontSize: CGFloat = 11
    static let emojiFontSize: CGFloat = 14
    static let textFontSize: CGFloat = 12
    static let tooltipFontSize: CGFloat = 11
    static let tooltipCornerRadius: CGFloat = 6
    static let tooltipOffsetY: CGFloat = -12
    static let defaultTextWidth: CGFloat = 50
    /// Extra horizontal inset on each side to keep content clear of the capsule's rounded corners.
    static let edgePadding: CGFloat = 8
}

/// A space picker with Safari-style capsule design and adaptive sizing.
///
/// Progressively collapses segments when space is constrained:
/// 1. **Full**: All segments show icon + name
/// 2. **Compact**: Inactive segments show icon only, active shows icon + name
/// 3. **Minimal**: All segments show icon only
///
/// Uses SwiftUI PreferenceKey to measure text sizes and determine the appropriate mode.
/// Icon-only segments display a hover tooltip with the space name.
///
/// Wraps a native Picker for full accessibility support while providing custom visual styling.
///
/// ## Observation
///
/// Accepts `Space` objects directly. Each segment view observes only the display properties
/// it needs (name, iconName, isEmoji, isLockEnabled), avoiding observation of the tabs/groups
/// arrays which would cause excessive rebuilds.
///
/// ## Context Menu Support
///
/// The `contextMenuBuilder` callback allows the parent to provide a context menu for each
/// space segment. The callback receives the `Space` for the right-clicked space.
struct SpacePicker<ContextMenu: View>: View {
    @Binding var selection: UUID
    let spaces: [Space]
    let unlockedSpaceIDs: Set<UUID>
    var cornerRadius: CGFloat = SpacePickerLayout.cornerRadius
    var contextMenuBuilder: ((Space) -> ContextMenu)?

    @State private var measuredWidths: [UUID: CGFloat] = [:]
    @State private var hoveredSpaceID: UUID?
    @State private var tooltipSpaceID: UUID?
    @State private var hoverTask: Task<Void, any Error>?

    // MARK: - Initializers

    /// Creates a space picker with an optional context menu builder.
    ///
    /// - Parameters:
    ///   - selection: Binding to the currently selected space ID.
    ///   - spaces: Array of spaces to display.
    ///   - unlockedSpaceIDs: Set of space IDs that are currently unlocked.
    ///   - cornerRadius: Corner radius for the picker capsule.
    ///   - contextMenuBuilder: Optional closure that builds a context menu for each space.
    init(
        selection: Binding<UUID>,
        spaces: [Space],
        unlockedSpaceIDs: Set<UUID>,
        cornerRadius: CGFloat = SpacePickerLayout.cornerRadius,
        @ViewBuilder contextMenuBuilder: @escaping (Space) -> ContextMenu,
    ) {
        self._selection = selection
        self.spaces = spaces
        self.unlockedSpaceIDs = unlockedSpaceIDs
        self.cornerRadius = cornerRadius
        self.contextMenuBuilder = contextMenuBuilder
    }

    // MARK: - Type Aliases

    private typealias Layout = SpacePickerLayout

    // MARK: - Display Mode

    private enum DisplayMode: Equatable {
        case full
        case compact
        case minimal
    }

    // MARK: - Computed Properties

    private var selectedIndex: Int {
        spaces.firstIndex { $0.id == selection } ?? 0
    }

    private var selectedSpace: Space? {
        spaces.first { $0.id == selection }
    }

    // MARK: - Body

    var body: some View {
        Group {
            if spaces.isEmpty {
                emptyState
            } else {
                mainContent
            }
        }
        .frame(height: Layout.height)
        .accessibilityRepresentation {
            accessibilityPicker
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Text("No Spaces")
            .font(.system(size: Layout.textFontSize, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    // MARK: - Main Content

    private var mainContent: some View {
        GeometryReader { geometry in
            let layoutInfo = calculateLayout(for: geometry.size.width)

            ZStack(alignment: .leading) {
                if spaces.count > 1 {
                    highlightPill(segmentWidths: layoutInfo.segmentWidths)
                }
                segmentsRow(layoutInfo: layoutInfo)
            }
        }
        .adaptiveBackground(.subtle, in: RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            // Tooltip overlay - placed after clipShape so it won't be clipped
            GeometryReader { geometry in
                let layoutInfo = calculateLayout(for: geometry.size.width)
                tooltipOverlay(layoutInfo: layoutInfo)
            }
            .allowsHitTesting(false)
        }
        .onHover { isHovering in
            if !isHovering {
                dismissTooltip()
            }
        }
        .onPreferenceChange(TextWidthPreferenceKey.self) { widths in
            measuredWidths.merge(widths) { _, new in new }
        }
    }

    // MARK: - Layout Calculation

    private struct LayoutInfo {
        let mode: DisplayMode
        let segmentWidths: [CGFloat]
    }

    private func calculateLayout(for totalWidth: CGFloat) -> LayoutInfo {
        let mode = calculateDisplayMode(availableWidth: totalWidth)
        let widths = calculateSegmentWidths(totalWidth: totalWidth, mode: mode)
        return LayoutInfo(mode: mode, segmentWidths: widths)
    }

    // MARK: - Segments Row

    private func segmentsRow(layoutInfo: LayoutInfo) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(spaces.enumerated()), id: \.element.id) { index, space in
                let showsLabel = shouldShowLabel(mode: layoutInfo.mode, isSelected: index == selectedIndex)
                let width = layoutInfo.segmentWidths[index]
                let isLocked = space.isLockEnabled && !unlockedSpaceIDs.contains(space.id)

                SpaceSegmentButton(
                    space: space,
                    isLocked: isLocked,
                    width: width,
                    showsLabel: showsLabel,
                    onSelect: { selection = space.id },
                    onHover: { isHovering in handleHover(isHovering: isHovering, spaceID: space.id) },
                    contextMenuBuilder: contextMenuBuilder,
                )
                .background { measurementView(for: space) }

                if index < spaces.count - 1 {
                    divider(at: index)
                }
            }
        }
    }

    // MARK: - Tooltip Overlay

    @ViewBuilder
    private func tooltipOverlay(layoutInfo: LayoutInfo) -> some View {
        if let spaceID = tooltipSpaceID,
           let (space, index) = findSpace(by: spaceID),
           !shouldShowLabel(mode: layoutInfo.mode, isSelected: index == selectedIndex) {
            let centerX = layoutInfo.segmentWidths.prefix(index).reduce(0, +)
                + layoutInfo.segmentWidths[index] / 2

            SpaceTooltip(space: space, centerX: centerX)
        }
    }

    /// Find a space and its index by ID in a single pass
    private func findSpace(by id: UUID) -> (space: Space, index: Int)? {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { return nil }
        return (spaces[index], index)
    }

    // MARK: - Highlight Pill

    private func highlightPill(segmentWidths: [CGFloat]) -> some View {
        let inset = Layout.highlightInset
        let width = segmentWidths[selectedIndex] - (inset * 2)
        let offset = segmentWidths.prefix(selectedIndex).reduce(inset, +)

        return Color.clear
            .frame(width: width, height: Layout.height - (inset * 2))
            .adaptiveBackground(.emphasized, in: RoundedRectangle(cornerRadius: cornerRadius - inset))
            .offset(x: offset)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedIndex)
    }

    // MARK: - Divider

    private func divider(at index: Int) -> some View {
        let adjacentToSelected = index == selectedIndex || (index + 1) == selectedIndex

        return Rectangle()
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 1, height: Layout.dividerHeight)
            .opacity(adjacentToSelected ? 0 : 1)
            .animation(.easeInOut(duration: 0.2), value: selectedIndex)
    }

    // MARK: - Measurement

    private func measurementView(for space: Space) -> some View {
        SpaceMeasurementView(space: space)
    }

    // MARK: - Hover Management

    private func handleHover(isHovering: Bool, spaceID: UUID) {
        if isHovering {
            hoveredSpaceID = spaceID

            if tooltipSpaceID != nil {
                // Already showing a tooltip - switch immediately
                cancelHoverTimer()
                withAnimation(.easeInOut(duration: 0.12)) {
                    tooltipSpaceID = spaceID
                }
            } else {
                // Start delay timer for initial appearance
                startHoverTimer(for: spaceID)
            }
        } else if hoveredSpaceID == spaceID {
            hoveredSpaceID = nil
        }
    }

    private func startHoverTimer(for spaceID: UUID) {
        cancelHoverTimer()

        hoverTask = Task {
            try await Task.sleep(for: .milliseconds(300))
            guard hoveredSpaceID == spaceID else { return }

            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                tooltipSpaceID = spaceID
            }
        }
    }

    private func cancelHoverTimer() {
        hoverTask?.cancel()
        hoverTask = nil
    }

    private func dismissTooltip() {
        cancelHoverTimer()
        withAnimation(.easeOut(duration: 0.15)) {
            tooltipSpaceID = nil
        }
    }

    // MARK: - Layout Calculations

    private func calculateDisplayMode(availableWidth: CGFloat) -> DisplayMode {
        // Account for capsule edge insets and inter-segment dividers
        let dividerWidth = CGFloat(max(0, spaces.count - 1))
        let effectiveWidth = availableWidth - 2 * Layout.edgePadding - dividerWidth

        // Full mode: all segments show icon + name
        let fullWidth = spaces.reduce(CGFloat(0)) { sum, space in
            let textWidth = measuredWidths[space.id] ?? Layout.defaultTextWidth
            return sum + Layout.iconWidth + Layout.iconTextSpacing + textWidth + Layout.segmentPadding
        }

        if fullWidth <= effectiveWidth {
            return .full
        }

        // Compact mode: only selected segment shows name
        let activeTextWidth = selectedSpace.flatMap { measuredWidths[$0.id] } ?? Layout.defaultTextWidth
        let activeSegmentWidth = Layout.iconWidth + Layout.iconTextSpacing + activeTextWidth + Layout.segmentPadding
        let compactWidth = CGFloat(spaces.count - 1) * Layout.iconOnlyWidth + activeSegmentWidth

        if compactWidth <= effectiveWidth {
            return .compact
        }

        return .minimal
    }

    private func shouldShowLabel(mode: DisplayMode, isSelected: Bool) -> Bool {
        mode == .full || (mode == .compact && isSelected)
    }

    private func calculateSegmentWidths(totalWidth: CGFloat, mode: DisplayMode) -> [CGFloat] {
        switch mode {
        case .full, .minimal:
            let width = totalWidth / CGFloat(spaces.count)
            return Array(repeating: width, count: spaces.count)

        case .compact:
            let activeWidth = totalWidth - CGFloat(spaces.count - 1) * Layout.iconOnlyWidth
            return spaces.indices.map { index in
                index == selectedIndex ? max(activeWidth, Layout.iconOnlyWidth) : Layout.iconOnlyWidth
            }
        }
    }

    // MARK: - Accessibility

    private var accessibilityPicker: some View {
        Picker("Space", selection: $selection) {
            ForEach(spaces) { space in
                Text(space.name).tag(space.id)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }
}

// MARK: - Convenience Initializer (No Context Menu)

extension SpacePicker where ContextMenu == EmptyView {
    /// Creates a space picker without a context menu.
    ///
    /// - Parameters:
    ///   - selection: Binding to the currently selected space ID.
    ///   - spaces: Array of spaces to display.
    ///   - unlockedSpaceIDs: Set of space IDs that are currently unlocked.
    ///   - cornerRadius: Corner radius for the picker capsule.
    init(
        selection: Binding<UUID>,
        spaces: [Space],
        unlockedSpaceIDs: Set<UUID>,
        cornerRadius: CGFloat = SpacePickerLayout.cornerRadius,
    ) {
        self._selection = selection
        self.spaces = spaces
        self.unlockedSpaceIDs = unlockedSpaceIDs
        self.cornerRadius = cornerRadius
        self.contextMenuBuilder = nil
    }
}

// MARK: - Space Segment Button

/// A button for a single space segment that observes only the display properties.
private struct SpaceSegmentButton<ContextMenu: View>: View {
    let space: Space
    let isLocked: Bool
    let width: CGFloat
    let showsLabel: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void
    let contextMenuBuilder: ((Space) -> ContextMenu)?

    private typealias Layout = SpacePickerLayout

    /// Accessibility identifier for the space button
    private var accessibilityID: String {
        let sanitized = space.name
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
            .prefix(20)
        return "space-\(sanitized)"
    }

    var body: some View {
        let button = Button(action: onSelect) {
            HStack(spacing: Layout.iconTextSpacing) {
                spaceIcon

                if showsLabel {
                    Text(space.name)
                        .font(.system(size: Layout.textFontSize, weight: .regular))
                        .lineLimit(1)
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .foregroundStyle(.primary)
            .frame(width: width, height: Layout.height)
            .contentShape(Rectangle())
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: showsLabel)
        }
        .buttonStyle(.plain)
        .onHover(perform: onHover)
        .accessibilityIdentifier(accessibilityID)
        .accessibilityLabel(space.name)

        if let builder = contextMenuBuilder {
            button.contextMenu {
                builder(space)
            }
        } else {
            button
        }
    }

    private var spaceIcon: some View {
        ZStack(alignment: .bottomTrailing) {
            if space.isEmoji {
                Text(space.iconName)
                    .font(.system(size: Layout.emojiFontSize))
            } else {
                Image(systemName: space.iconName)
                    .font(.system(size: Layout.iconFontSize, weight: .medium))
            }

            // Lock indicator for locked spaces
            if space.isLockEnabled {
                Image(systemName: isLocked ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.primary.opacity(isLocked ? 0.85 : 0.6))
                    .padding(2)
                    .background(.ultraThinMaterial, in: Circle())
                    .offset(x: 5, y: 3)
            }
        }
    }
}

// MARK: - Space Tooltip

/// A tooltip view that observes only the space name.
private struct SpaceTooltip: View {
    let space: Space
    let centerX: CGFloat

    private typealias Layout = SpacePickerLayout

    var body: some View {
        Text(space.name)
            .font(.system(size: Layout.tooltipFontSize, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Layout.tooltipCornerRadius))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
            .fixedSize()
            .position(x: centerX, y: Layout.tooltipOffsetY)
            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
    }
}

// MARK: - Space Measurement View

/// A hidden view that measures space name width and reports via preference key.
private struct SpaceMeasurementView: View {
    let space: Space

    private typealias Layout = SpacePickerLayout

    var body: some View {
        Text(space.name)
            .font(.system(size: Layout.textFontSize, weight: .medium))
            .fixedSize()
            .hidden()
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: TextWidthPreferenceKey.self,
                        value: [space.id: geo.size.width],
                    )
                },
            )
    }
}

// MARK: - Preference Key

private struct TextWidthPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]

    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}
