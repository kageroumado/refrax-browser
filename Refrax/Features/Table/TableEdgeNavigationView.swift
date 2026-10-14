import SwiftUI

/// Shows the exact page each direction will reach while Control owns scrolling.
struct TableEdgeNavigationView: View {
    @Environment(TableController.self) private var table
    @Environment(TabCanvasManager.self) private var canvas

    private enum Layout {
        static let edgeInset: CGFloat = 16
        static let faviconSize: CGFloat = 16
        static let sideWidthRange: ClosedRange<CGFloat> = 190 ... 300
        static let sideHeightRange: ClosedRange<CGFloat> = 150 ... 260
        static let verticalWidthRange: ClosedRange<CGFloat> = 220 ... 360
        static let verticalHeightRange: ClosedRange<CGFloat> = 130 ... 220
        static let cornerRadius: CGFloat = 16
        static let sidePreviewRise: CGFloat = 88
        static let captionHeight: CGFloat = 34
        static let approachDistance: CGFloat = 26
    }

    var body: some View {
        GlassEffectContainer {
            ZStack {
                VStack {
                    edge(.up)
                    Spacer(minLength: 0)
                    edge(.down)
                }
                HStack {
                    edge(.left)
                    Spacer(minLength: 0)
                    edge(.right)
                }
                .offset(y: -Layout.sidePreviewRise)
                if hasOtherTabs && !hasAdjacentDestination && table.blockedDirection == nil {
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
                        Spacer().frame(height: Layout.edgeInset + 8)
                    }
                }
            }
        }
        .padding(.vertical, Layout.edgeInset)
        .padding(.trailing, Layout.edgeInset)
        .padding(.leading, Layout.edgeInset)
        .onChange(of: table.navigationTabID) { table.clearBlockedDirection() }
        .onDisappear { table.clearBlockedDirection() }
    }

    private var hasOtherTabs: Bool {
        guard let current = table.currentTab else { return false }
        return canvas.floatingTabs.contains { $0.id != current.id }
    }

    private var hasAdjacentDestination: Bool {
        TableDirection.allCases.contains { table.destination(toward: $0) != nil }
    }

    @ViewBuilder
    private func edge(_ direction: TableDirection) -> some View {
        if let tab = table.destination(toward: direction) {
            Button {
                table.step(direction)
            } label: {
                neighborPreview(tab, direction: direction)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("table-edge-\(direction.rawValue)")
            .accessibilityLabel("Go \(direction.rawValue) to \(tab.displayTitle)")
            .help("Go \(direction.rawValue) to \(tab.displayTitle)")
            .task(id: tab.id) { table.requestStoredSnapshot(for: tab) }
            .offset(approachOffset(for: direction))
        } else if hasOtherTabs && table.blockedDirection == direction {
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
        }
    }

    private func neighborPreview(_ tab: Tab, direction: TableDirection) -> some View {
        let size = previewSize(for: direction)
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

    private func previewSize(for direction: TableDirection) -> CGSize {
        switch direction {
        case .left, .right:
            CGSize(
                width: min(max(table.viewport.width * 0.14, Layout.sideWidthRange.lowerBound), Layout.sideWidthRange.upperBound),
                height: min(max(table.viewport.height * 0.20, Layout.sideHeightRange.lowerBound), Layout.sideHeightRange.upperBound),
            )
        case .up, .down:
            CGSize(
                width: min(max(table.viewport.width * 0.25, Layout.verticalWidthRange.lowerBound), Layout.verticalWidthRange.upperBound),
                height: min(max(table.viewport.height * 0.16, Layout.verticalHeightRange.lowerBound), Layout.verticalHeightRange.upperBound),
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
