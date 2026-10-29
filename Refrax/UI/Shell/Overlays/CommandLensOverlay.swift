import SwiftUI

// MARK: - Command Lens Overlay

/// The Command Lens at full size, centered near the top of the window (⌘T, the rail button).
///
/// Isolated observation of the lens entrance from the parent container; the anchored
/// entrance is drawn by `AnchoredLensOverlay`.
///
/// The container stays in the hierarchy and owns the animation, so the lens's removal always
/// runs to its end: a transition left to whatever transaction closed the lens could stop
/// halfway and leave a faded copy on screen.
struct CommandLensOverlay: View {
    @Environment(WindowState.self) private var windowState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isShown: Bool {
        windowState.showsCommandLens && !windowState.showsAnchoredLens
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if isShown {
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isShown)
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
