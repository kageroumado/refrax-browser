import SwiftUI

struct FloatingTabGroup: View {
    let tabs: [Tab]
    let area: CGRect
    @Environment(TabCanvasManager.self) private var canvas
    @State private var origins: [Tab.ID: CGPoint] = [:]
    @State private var originalBounds: CGRect?
    @State private var renaming = false
    @State private var name = ""

    private var bounds: CGRect { canvas.floatingGroupFrame(tabs, in: area) }

    var body: some View {
        RoundedRectangle(cornerRadius: 20).fill(.primary.opacity(0.04))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.15), lineWidth: 1) }
            .overlay(alignment: .topLeading) {
                Text(tabs.first?.group?.name ?? "Group")
                    .font(.caption.weight(.medium)).padding(.horizontal, 12).frame(height: 24)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("floatingTabs"))
                        .onChanged { value in
                            if origins.isEmpty {
                                origins = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, canvas.floatingPlacement(for: $0).frame(in: area).origin) })
                                originalBounds = bounds
                                canvas.beginFloatingManipulation()
                            }
                            let box = originalBounds ?? bounds
                            let dx = min(max(value.translation.width, -box.minX), area.maxX - box.maxX)
                            let dy = min(max(value.translation.height, -box.minY), area.maxY - box.maxY)
                            for tab in tabs {
                                guard let origin = origins[tab.id] else { continue }
                                var placement = canvas.floatingPlacement(for: tab)
                                placement.move(to: CGPoint(x: origin.x + dx, y: origin.y + dy), in: area)
                                canvas.updateFloatingPlacement(placement, for: tab)
                            }
                        }.onEnded { _ in
                            origins = [:]
                            originalBounds = nil
                            canvas.endFloatingManipulation()
                        })
                    .contextMenu {
                        Button("Rename Group…") { name = tabs.first?.group?.name ?? "Group"; renaming = true }
                        Button("Ungroup Tabs") { canvas.ungroupFloatingTabs(tabs) }
                    }
                    .accessibilityLabel("Move group: \(tabs.first?.group?.name ?? "Group")")
            }
            .frame(width: bounds.width, height: bounds.height)
            .offset(x: bounds.minX, y: bounds.minY)
            .alert("Group Name", isPresented: $renaming) {
                TextField("Name", text: $name)
                Button("Save") { canvas.renameFloatingGroup(tabs, to: name) }
                Button("Cancel", role: .cancel) {}
            }
    }
}
