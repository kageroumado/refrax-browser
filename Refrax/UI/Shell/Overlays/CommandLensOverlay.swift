import SwiftUI

// MARK: - Command Lens Overlay

/// Overlay for the command lens (Cmd+K).
///
/// Isolated observation of `showsCommandLens` from the parent container.
/// The command lens appears centered at the top of the window with a scale/fade animation.
struct CommandLensOverlay: View {
    @Environment(WindowState.self) private var windowState

    var body: some View {
        if windowState.showsCommandLens {
            ZStack(alignment: .topLeading) {
                clickCapture

                VStack {
                    CommandLensView()
                        .frame(maxWidth: 640)
                        .padding(.horizontal, 20)
                        .padding(.top, 180)

                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .allowsHitTesting(true)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
            }
        }
    }

    private var clickCapture: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .onTapGesture {
                windowState.closeCommandLens()
            }
    }
}
