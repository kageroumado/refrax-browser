import SwiftUI

// MARK: - Command Lens Overlay

/// The Command Lens at full size, centered near the top of the window (⌘T, the rail button).
///
/// Isolated observation of the lens entrance from the parent container; the anchored
/// entrance is drawn by `AnchoredLensOverlay`.
struct CommandLensOverlay: View {
    @Environment(WindowState.self) private var windowState

    var body: some View {
        if windowState.showsCommandLens, !windowState.showsAnchoredLens {
            ZStack(alignment: .topLeading) {
                clickCapture

                VStack {
                    CommandLensView()
                        .frame(maxWidth: 640)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { windowState.commandLensFrame = $0 }
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
