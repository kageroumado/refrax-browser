import SwiftUI

/// Shows the exact page each direction will reach while Control owns scrolling.
struct TableEdgeNavigationView: View {
    @Environment(TableController.self) private var table
    @Environment(TabCanvasManager.self) private var canvas

    private enum Layout {
        static let edgeInset: CGFloat = 20
        static let railClearance: CGFloat = 104
        static let titleWidth: CGFloat = 174
        static let faviconSize: CGFloat = 16
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
        .padding(.leading, Layout.railClearance)
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
                HStack(spacing: 8) {
                    if direction == .right || direction == .down {
                        favicon(for: tab)
                    }
                    Text(tab.displayTitle)
                        .lineLimit(1)
                        .frame(maxWidth: Layout.titleWidth, alignment: .leading)
                    Image(systemName: symbol(for: direction))
                        .fontWeight(.semibold)
                    if direction == .left || direction == .up {
                        favicon(for: tab)
                    }
                }
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Capsule())
                .fixedSize(horizontal: true, vertical: false)
            }
            .buttonStyle(.plain)
            .fixedSize(horizontal: true, vertical: false)
            .glassEffect(.regular.interactive(), in: Capsule())
            .accessibilityIdentifier("table-edge-\(direction.rawValue)")
            .accessibilityLabel("Go \(direction.rawValue) to \(tab.displayTitle)")
            .help("Go \(direction.rawValue) to \(tab.displayTitle)")
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
