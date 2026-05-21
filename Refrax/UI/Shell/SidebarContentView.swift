import SwiftUI

struct SidebarContentView: View {
    @GestureState var isDraggingWindow = false

    var body: some View {
        VStack {
            Sidebar()
        }
        .gesture(dragWindow)
        .allowsWindowActivationEvents()
    }

    private var dragWindow: some Gesture {
        WindowDragGesture()
            .updating($isDraggingWindow) { _, state, _ in
                state = true
            }
    }
}
