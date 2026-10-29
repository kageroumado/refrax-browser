import SwiftUI

/// Keeps the new tab's destination beside the field for the duration of entry.
struct CommandLensScopeLabel: View {
    @Environment(WindowState.self) private var windowState
    private enum Layout {
        static let bottomPadding: CGFloat = 10
    }

    private var destination: String {
        let groupID = if let island = windowState.newTabIsland {
            island.groupID
        } else {
            windowState.activeTab?.groupID
        }
        return windowState.activeSpace?.groups.first(where: { $0.id == groupID })?.name ?? "Tabs"
    }

    var body: some View {
        Text("New tab in \(destination)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.bottom, Layout.bottomPadding)
            .accessibilityIdentifier("command-lens-destination")
    }
}
