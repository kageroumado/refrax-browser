import SwiftUI

// MARK: - Toast Overlay

/// Isolated overlay for toast notifications.
///
/// Extracted to isolate observation of `toastMessage`
/// from the parent container. Changes to toast state only rebuild this view.
struct ToastOverlay: View {
    @Environment(WindowState.self) private var windowState

    var body: some View {
        Group {
            if let message = windowState.toastMessage {
                ToastNotificationView(message: message, action: windowState.toastAction)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, 16)
                    .ignoresSafeArea()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3), value: windowState.toastMessage != nil)
    }
}

// MARK: - Toast Action

/// A button a toast offers beside its message, such as Undo.
struct ToastAction {
    let title: String
    let perform: () -> Void
}

// MARK: - Toast Notification View

/// Brief notification displayed at the top of the window, with an optional button beside
/// the message. It dismisses itself after a few seconds; its button closes it at once.
struct ToastNotificationView: View {
    let message: String
    var action: ToastAction?
    @Environment(WindowState.self) private var windowState

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.body)
                .lineLimit(2)
            if let action {
                Button(action.title) {
                    windowState.isHoveringOverlayNotification = false
                    windowState.dismissToast()
                    action.perform()
                }
                .buttonStyle(.borderless)
                .fontWeight(.semibold)
                .foregroundStyle(Color.appAccentColor)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .glassEffect()
        .contentShape(Capsule())
        .onHover { hovering in
            guard action != nil else { return }
            windowState.isHoveringOverlayNotification = hovering
        }
        .onDisappear {
            if action != nil {
                windowState.isHoveringOverlayNotification = false
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(message)
    }
}
