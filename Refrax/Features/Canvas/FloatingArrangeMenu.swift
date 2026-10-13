import SwiftUI

/// Arrange ▸ Grid, Stacks by Site, Stacks by Group, for the floating layer of the active space.
/// Stacks by Site carries a check while the space keeps its site stacks.
struct FloatingArrangeMenu: View {
    @Environment(TabCanvasManager.self) private var canvas

    var body: some View {
        Menu {
            ForEach(FloatingArrangement.allCases, id: \.self) { arrangement in
                if arrangement == .stacksBySite {
                    Toggle(isOn: Binding(get: { canvas.stacksBySite }, set: { on in
                        if on {
                            canvas.arrange(arrangement)
                        } else {
                            canvas.stopStackingBySite()
                        }
                    })) {
                        Label(arrangement.title, systemImage: arrangement.symbol)
                    }
                } else {
                    Button(arrangement.title, systemImage: arrangement.symbol) { canvas.arrange(arrangement) }
                }
            }
        } label: {
            Label("Arrange", systemImage: "square.grid.3x2")
        }
    }
}
