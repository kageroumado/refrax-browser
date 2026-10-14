import SwiftUI

extension View {
    /// Asks before closing tabs that play media or use the camera or microphone, in the active
    /// window only: ``TabManager/pendingCloseConfirmation`` is shared by every window.
    func tabCloseConfirmation(tabManager: TabManager, windowState: WindowState) -> some View {
        alert(
            tabManager.pendingCloseConfirmation?.title ?? "Close Tab?",
            isPresented: Binding(
                get: { tabManager.pendingCloseConfirmation != nil && tabManager.activeWindowState === windowState },
                set: {
                    if !$0 {
                        tabManager.cancelCloseTabs()
                    }
                },
            ),
            presenting: tabManager.pendingCloseConfirmation,
        ) { _ in
            Button("Cancel", role: .cancel) {
                tabManager.cancelCloseTabs()
            }
            Button("Close", role: .destructive) {
                tabManager.confirmCloseTabs()
            }
        } message: { confirmation in
            TabCloseConfirmationMessage(confirmation: confirmation)
        }
    }
}

/// The tabs a close would interrupt, and what each is doing.
private struct TabCloseConfirmationMessage: View {
    let confirmation: TabManager.CloseConfirmation

    var body: some View {
        if confirmation.reasons.count == 1, let reason = confirmation.reasons.first {
            Text("\"\(reason.tab.displayTitle)\" \(reason.reasons.map(\.description).joined(separator: " and ")).")
        } else {
            Text(batchMessage)
        }
    }

    private var batchMessage: String {
        let items = confirmation.reasons.map { reason in
            "• \(reason.tab.displayTitle): \(reason.reasons.map(\.description).joined(separator: ", "))"
        }
        return "The following tabs have warnings:\n\n" + items.joined(separator: "\n") + "\n"
    }
}
