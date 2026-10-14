import SwiftUI

/// Places an edge preview on the same row or column as its destination's table anchor.
nonisolated enum TableEdgePreviewLayout {
    static let inset: CGFloat = 16
    /// Keeps row previews above the Control Island's page strip.
    static let sideLift: CGFloat = 88

    struct Reserves {
        var top: CGFloat = 0
        var bottom: CGFloat = 0
        var left: CGFloat = 0
        var right: CGFloat = 0
    }

    static func center(
        for direction: TableDirection,
        current: CGRect,
        destination: CGRect,
        viewport: CGSize,
        preview: CGSize,
        scale: CGFloat,
        reserves: Reserves = .init(),
    ) -> CGPoint {
        let x = viewport.width / 2 + (destination.minX - current.minX) * scale
        let y = viewport.height / 2 - sideLift + (destination.minY - current.minY) * scale
        switch direction {
        case .left:
            return CGPoint(x: inset + preview.width / 2,
                           y: clamp(y, lower: inset + reserves.top + preview.height / 2,
                                    upper: viewport.height - inset - reserves.bottom - preview.height / 2))
        case .right:
            return CGPoint(x: viewport.width - inset - preview.width / 2,
                           y: clamp(y, lower: inset + reserves.top + preview.height / 2,
                                    upper: viewport.height - inset - reserves.bottom - preview.height / 2))
        case .up:
            return CGPoint(x: clamp(x, lower: inset + reserves.left + preview.width / 2,
                                    upper: viewport.width - inset - reserves.right - preview.width / 2),
                           y: inset + preview.height / 2)
        case .down:
            return CGPoint(x: clamp(x, lower: inset + reserves.left + preview.width / 2,
                                    upper: viewport.width - inset - reserves.right - preview.width / 2),
                           y: viewport.height - inset - preview.height / 2)
        }
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard lower <= upper else { return (lower + upper) / 2 }
        return min(max(value, lower), upper)
    }
}

/// Shows the exact page each direction will reach while Control owns scrolling.
struct TableEdgeNavigationView: View {
    @Environment(TableController.self) private var table
    @Environment(TabCanvasManager.self) private var canvas

    private enum Layout {
        static let faviconSize: CGFloat = 16
        static let sideWidthRange: ClosedRange<CGFloat> = 190 ... 300
        static let sideHeightRange: ClosedRange<CGFloat> = 150 ... 260
        static let verticalWidthRange: ClosedRange<CGFloat> = 220 ... 360
        static let verticalHeightRange: ClosedRange<CGFloat> = 130 ... 220
        static let cornerRadius: CGFloat = 16
        static let captionHeight: CGFloat = 34
        static let approachDistance: CGFloat = 26
    }

    var body: some View {
        let viewport = table.viewport
        let left = table.destination(toward: .left)
        let right = table.destination(toward: .right)
        let up = table.destination(toward: .up)
        let down = table.destination(toward: .down)
        let reserves = TableEdgePreviewLayout.Reserves(
            top: up == nil ? 0 : previewSize(for: .up, in: viewport).height + Layout.captionHeight + TableEdgePreviewLayout.inset,
            bottom: down == nil ? 0 : previewSize(for: .down, in: viewport).height + Layout.captionHeight + TableEdgePreviewLayout.inset,
            left: left == nil ? 0 : previewSize(for: .left, in: viewport).width + TableEdgePreviewLayout.inset,
            right: right == nil ? 0 : previewSize(for: .right, in: viewport).width + TableEdgePreviewLayout.inset,
        )
        GlassEffectContainer {
            ZStack {
                VStack {
                    edge(.up, tab: up, in: viewport, reserves: reserves)
                    Spacer(minLength: 0)
                    edge(.down, tab: down, in: viewport, reserves: reserves)
                }
                HStack {
                    edge(.left, tab: left, in: viewport, reserves: reserves)
                    Spacer(minLength: 0)
                    edge(.right, tab: right, in: viewport, reserves: reserves)
                }
                .offset(y: -TableEdgePreviewLayout.sideLift)
                if hasOtherTabs && [left, right, up, down].allSatisfy({ $0 == nil }) && table.blockedDirection == nil {
                    VStack {
                        Spacer(minLength: 0)
                        Button {
                            canvas.show(fittingEverything: true)
                        } label: {
                            Label("View all tabs", systemImage: TabCanvasManager.symbolName)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .fixedSize()
                        }
                        .buttonStyle(.plain)
                        .fixedSize()
                        .glassEffect(.regular.interactive(), in: Capsule())
                        .accessibilityIdentifier("table-view-all-tabs")
                        .help("Open the table to reach other tab groups")
                        Spacer().frame(height: TableEdgePreviewLayout.inset + 8)
                    }
                }
            }
        }
        .padding(TableEdgePreviewLayout.inset)
        .onChange(of: table.navigationTabID) { table.clearBlockedDirection() }
        .onDisappear { table.clearBlockedDirection() }
    }

    private var hasOtherTabs: Bool {
        guard let current = table.currentTab else { return false }
        return canvas.floatingTabs.contains { $0.id != current.id }
    }

    @ViewBuilder
    private func edge(_ direction: TableDirection, tab: Tab?, in viewport: CGSize, reserves: TableEdgePreviewLayout.Reserves) -> some View {
        if let tab, let current = table.currentTab {
            let size = previewSize(for: direction, in: viewport)
            let cardSize = CGSize(width: size.width, height: size.height + Layout.captionHeight)
            let currentFrame = canvas.tablePlacement(for: current).frame(in: canvas.floatingArea)
            let destinationFrame = canvas.tablePlacement(for: tab).frame(in: canvas.floatingArea)
            let center = TableEdgePreviewLayout.center(
                for: direction, current: currentFrame, destination: destinationFrame,
                viewport: viewport, preview: cardSize, scale: canvas.floatingCamera.scale, reserves: reserves
            )
            Button {
                table.step(direction)
            } label: {
                neighborPreview(tab, direction: direction, size: size)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("table-edge-\(direction.rawValue)")
            .accessibilityLabel("Go \(direction.rawValue) to \(tab.displayTitle)")
            .help("Go \(direction.rawValue) to \(tab.displayTitle)")
            .task(id: tab.id) { table.requestStoredSnapshot(for: tab) }
            .offset(approachOffset(for: direction))
            .offset(placementOffset(for: direction, center: center, in: viewport))
        } else if hasOtherTabs && table.blockedDirection == direction {
            let size = CGSize(width: 180, height: 36)
            let center = TableEdgePreviewLayout.center(
                for: direction, current: .zero, destination: .zero,
                viewport: viewport, preview: size, scale: 1, reserves: reserves
            )
            Button {
                canvas.show(fittingEverything: true)
            } label: {
                HStack(spacing: 8) {
                    Text("End of group")
                        .foregroundStyle(.secondary)
                    Label("Desk", systemImage: TabCanvasManager.symbolName)
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .fixedSize()
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Capsule())
            .accessibilityIdentifier("table-edge-boundary-\(direction.rawValue)")
            .accessibilityLabel("End of group \(direction.rawValue). Open Desk")
            .help("Open Desk to reach another tab group")
            .offset(placementOffset(for: direction, center: center, in: viewport))
        }
    }

    private func neighborPreview(_ tab: Tab, direction: TableDirection, size: CGSize) -> some View {
        return VStack(spacing: 0) {
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                if let snapshot = table.snapshot(for: tab.id) {
                    Image(nsImage: snapshot)
                        .resizable()
                        .scaledToFill()
                        .frame(width: size.width, height: size.height)
                        .clipped()
                } else {
                    favicon(for: tab)
                        .font(.largeTitle)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(width: size.width, height: size.height)

            HStack(spacing: 7) {
                favicon(for: tab)
                Text(tab.displayTitle)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: symbol(for: direction))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
            }
            .padding(.horizontal, 10)
            .frame(height: Layout.captionHeight)
        }
        .frame(width: size.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous)
                .strokeBorder(.tint, lineWidth: 2)
        }
        .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: Layout.cornerRadius, style: .continuous))
    }

    private func previewSize(for direction: TableDirection, in viewport: CGSize) -> CGSize {
        switch direction {
        case .left, .right:
            CGSize(
                width: min(max(viewport.width * 0.14, Layout.sideWidthRange.lowerBound), Layout.sideWidthRange.upperBound),
                height: min(max(viewport.height * 0.20, Layout.sideHeightRange.lowerBound), Layout.sideHeightRange.upperBound),
            )
        case .up, .down:
            CGSize(
                width: min(max(viewport.width * 0.25, Layout.verticalWidthRange.lowerBound), Layout.verticalWidthRange.upperBound),
                height: min(max(viewport.height * 0.16, Layout.verticalHeightRange.lowerBound), Layout.verticalHeightRange.upperBound),
            )
        }
    }

    private func approachOffset(for direction: TableDirection) -> CGSize {
        guard table.approachDirection == direction else { return .zero }
        let distance = table.approachFraction * Layout.approachDistance
        switch direction {
        case .left: return CGSize(width: distance, height: 0)
        case .right: return CGSize(width: -distance, height: 0)
        case .up: return CGSize(width: 0, height: distance)
        case .down: return CGSize(width: 0, height: -distance)
        }
    }

    private func placementOffset(for direction: TableDirection, center: CGPoint, in viewport: CGSize) -> CGSize {
        switch direction {
        case .left, .right:
            CGSize(width: 0, height: center.y - viewport.height / 2 + TableEdgePreviewLayout.sideLift)
        case .up, .down:
            CGSize(width: center.x - viewport.width / 2, height: 0)
        }
    }

    @ViewBuilder
    private func favicon(for tab: Tab) -> some View {
        if let data = tab.activePage.faviconData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: Layout.faviconSize, height: Layout.faviconSize)
        } else {
            Image(systemName: "globe")
                .frame(width: Layout.faviconSize, height: Layout.faviconSize)
        }
    }

    private func symbol(for direction: TableDirection) -> String {
        switch direction {
        case .left: "chevron.left"
        case .right: "chevron.right"
        case .up: "chevron.up"
        case .down: "chevron.down"
        }
    }
}
