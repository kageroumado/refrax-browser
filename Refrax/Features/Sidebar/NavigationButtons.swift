import SwiftUI

struct NavigationButtons: View {
    let canGoBack: Bool
    let canGoForward: Bool
    let onGoBack: () -> Void
    let onGoForward: () -> Void
    
    var body: some View {
        ControlGroup {
            Button(action: onGoBack) {
                Image(systemName: "chevron.left")
            }
            .disabled(!canGoBack)
            .accessibilityIdentifier("nav-back")
            .accessibilityLabel("Back")

            Button(action: onGoForward) {
                Image(systemName: "chevron.right")
            }
            .disabled(!canGoForward)
            .accessibilityIdentifier("nav-forward")
            .accessibilityLabel("Forward")
        }
        .controlGroupStyle(.navigation)
        .accessibilityIdentifier("nav-buttons")
        .animation(.easeInOut(duration: 0.2), value: canGoForward)
    }
}
