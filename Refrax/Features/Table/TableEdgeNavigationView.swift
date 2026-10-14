import SwiftUI

/// Shows the exact page each direction will reach while Control owns scrolling.
struct TableEdgeNavigationView: View {
    @Environment(TableController.self) private var table

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
            }
        }
        .padding(.vertical, Layout.edgeInset)
        .padding(.trailing, Layout.edgeInset)
        .padding(.leading, Layout.railClearance)
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
