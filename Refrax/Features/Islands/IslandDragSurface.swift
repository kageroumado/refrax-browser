import SwiftUI

/// The empty glass of an island moves its placement within the browser window.
struct IslandDragSurface: View {
    let islandID: UUID
    @Environment(IslandController.self) private var islands
    @State private var origin: CGPoint?
    @GestureState private var isDragging = false

    var body: some View {
        Color.clear
            .contentShape(WindowCorner.concentric)
            .pointerStyle(.grabIdle)
            .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .named("islands"))
                .updating($isDragging) { _, dragging, _ in dragging = true }
                .onChanged { value in
                    guard let island = islands.island(islandID) else { return }
                    let start = origin ?? islands.frame(of: island).origin
                    origin = start
                    islands.draggedIslandID = islandID
                    islands.moveIsland(islandID, to: CGPoint(x: start.x + value.translation.width, y: start.y + value.translation.height))
                }
                .onEnded { _ in
                    finish(cancelled: false)
                })
            .onChange(of: isDragging) { _, dragging in
                if !dragging { finish(cancelled: true) }
            }
            .onDisappear { finish(cancelled: true) }
    }

    private func finish(cancelled: Bool) {
        guard let start = origin else { return }
        origin = nil
        if cancelled { islands.moveIsland(islandID, to: start) }
        islands.draggedIslandID = nil
        islands.endIslandMove(keeping: islandID)
    }
}
