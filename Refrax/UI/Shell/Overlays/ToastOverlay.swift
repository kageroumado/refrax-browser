import SwiftUI

// MARK: - Toast Overlay

/// Isolated overlay for toast notifications.
///
/// Extracted to isolate observation of `toastMessage` and `sidebarThickness`
/// from the parent container. Changes to toast state only rebuild this view.
struct ToastOverlay: View {
    @Environment(WindowState.self) private var windowState

    var body: some View {
        Group {
            if let message = windowState.toastMessage {
                ToastNotificationView(message: message)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 16)
                    .offset(x: windowState.sidebarThickness / 2)
                    .ignoresSafeArea()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: windowState.toastMessage != nil)
    }
}

// MARK: - Toast Notification View

/// Brief notification displayed at the top-right of the window.
///
/// Used for informational messages like crash recovery notifications.
/// Automatically dismisses after a few seconds, or can be dismissed by clicking.
struct ToastNotificationView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.body)
            .lineLimit(2)
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .glassEffect()
            .accessibilityElement(children: .combine)
            .accessibilityLabel(message)
    }
}
