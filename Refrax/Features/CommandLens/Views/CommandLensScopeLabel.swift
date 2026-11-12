import SwiftUI

/// Keeps the destination of what the lens opens beside the field for the duration of entry.
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
        guard let space = windowState.activeSpace else { return IslandState.looseTabsTitle }
        return space.groups.first(where: { $0.id == groupID })?.name ?? space.looseTabsTitle
    }

    private var text: String {
        if windowState.commandLensEntrance?.opensInGlimpse == true {
            return "Opens in a Glimpse window"
        }
        return "New tab in \(destination)"
    }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.bottom, Layout.bottomPadding)
            .accessibilityIdentifier("command-lens-destination")
    }
}
