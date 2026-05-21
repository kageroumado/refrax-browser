import SwiftUI

// MARK: - Favorites Settings

struct FavoritesSettingsView: View {
    @Environment(BrowserSettings.self) private var settings
    @Environment(BookmarksManager.self) private var bookmarksManager

    let highlightedItemId: String?

    @State private var enabledTypes: Set<AppShortcutType> = []

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Text("Add quick access shortcuts to app features in the favorites grid.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } header: {
                Text("App Shortcuts")
            }
            .highlightable(id: "favorites.appShortcuts", highlightedItemId: highlightedItemId)

            Section {
                ForEach(AppShortcutType.allCases) { type in
                    AppShortcutRow(
                        type: type,
                        isEnabled: enabledTypes.contains(type),
                        onToggle: { enabled in toggleShortcut(type, enabled: enabled) },
                        highlightedItemId: highlightedItemId,
                    )
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { syncEnabledTypes() }
        .onChange(of: bookmarksManager.favoritesVersion) { syncEnabledTypes() }
    }

    private func syncEnabledTypes() {
        enabledTypes = Set(bookmarksManager.allAppShortcuts().map(\.shortcutType))
    }

    private func toggleShortcut(_ type: AppShortcutType, enabled: Bool) {
        if enabled {
            enabledTypes.insert(type)
            bookmarksManager.addAppShortcut(type)
        } else {
            enabledTypes.remove(type)
            if let shortcut = bookmarksManager.allAppShortcuts().first(where: { $0.shortcutType == type }) {
                bookmarksManager.removeAppShortcut(shortcut)
            }
        }
    }
}

// MARK: - App Shortcut Row

private struct AppShortcutRow: View {
    let type: AppShortcutType
    let isEnabled: Bool
    let onToggle: (Bool) -> Void
    let highlightedItemId: String?

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: type.iconName)
                .font(.title2)
                .foregroundStyle(Color.resolveStoredColor(type.defaultColor))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.resolveStoredColor(type.defaultColor).opacity(0.15)),
                )

            // Label
            VStack(alignment: .leading, spacing: 2) {
                Text(type.displayName)
                    .fontWeight(.medium)

                Text(shortcutDescription(for: type))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Toggle
            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { onToggle($0) },
            ))
            .labelsHidden()
        }
        .highlightable(id: highlightId(for: type), highlightedItemId: highlightedItemId)
    }

    private func shortcutDescription(for type: AppShortcutType) -> String {
        switch type {
        case .downloads:
            "Quick access to downloads tray"
        case .bookmarks:
            "Quick access to bookmarks tray"
        case .history:
            "Quick access to history tray"
        case .settings:
            "Quick access to settings"
        }
    }

    private func highlightId(for type: AppShortcutType) -> String {
        switch type {
        case .downloads:
            "favorites.downloadsShortcut"
        case .bookmarks:
            "favorites.bookmarksShortcut"
        case .history:
            "favorites.historyShortcut"
        case .settings:
            "favorites.settingsShortcut"
        }
    }
}
