import SwiftUI

/// Unplaced pages accumulate here while existing placements remain stable.
struct FloatingRecentTabs: View {
    let area: CGRect
    @Environment(TabCanvasManager.self) private var canvas

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent").font(.headline)
                Text(openCount)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                Button("Done") { canvas.recentIsOpen = false }
            }
            if canvas.unplacedFloatingTabs.isEmpty {
                Text("New pages collect here. Your placed tabs stay where you left them.")
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(canvas.unplacedFloatingTabs) { tab in
                        HStack {
                            Button { canvas.openFloatingTab(tab) } label: {
                                VStack(alignment: .leading) {
                                    Text(tab.displayTitle).lineLimit(1)
                                    Text(tab.activePage.url.host ?? "Local page").font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 44).contentShape(Rectangle())
                            }
                            .draggable(FloatingTabDrag(id: tab.id))
                            .onDragSessionUpdated { session in
                                switch session.phase {
                                case .initial, .active: canvas.draggedRecentTabID = tab.id
                                default: canvas.draggedRecentTabID = nil
                                }
                            }
                            TabStateSymbols(tab: tab)
                            Button("Place") {
                                var placement = FloatingTabPlacement.initial(index: 0, count: 4)
                                placement.move(to: CGPoint(x: area.midX - 125, y: area.midY), in: area)
                                canvas.updateFloatingPlacement(placement, for: tab)
                                canvas.recentIsOpen = false
                            }
                            PageActionsMenu(tab: tab, surface: .floatingCard, area: area)
                                .frame(width: 28, height: 28)
                        }
                        .closesOnMiddleClick(tab)
                    }
                }
            }
        }.padding(16).buttonStyle(.plain)
    }

    /// "12 tabs": every tab open in this window's space, placed or not.
    private var openCount: String {
        let count = canvas.floatingTabs.count
        return "\(count) \(count == 1 ? "tab" : "tabs")"
    }
}
