import SwiftUI

/// Preferences window for configuring Refrax behavior and appearance.
///
/// Presents a split-view interface with a searchable sidebar and category detail panels.
/// All changes are immediately applied and persisted via ``BrowserSettings`` and `UserDefaults`.
///
/// ## File layout
/// - `SettingsSupport.swift`: category metadata, search items, sidebar/content views, and highlight modifier.
/// - `SettingsGeneralView.swift`: General section UI.
/// - `SettingsAppearanceView.swift`: Appearance section UI + color picker helpers.
/// - `SettingsPrivacyView.swift`: Privacy section UI + related sheets (redirects, GPC, clear history).
/// - `SettingsSearchView.swift`: Search section UI.
/// - `SettingsAdvancedView.swift`: Advanced section UI + JavaScript site sheets.
struct SettingsView: View {
    @State private var selectedCategory: SettingsCategory = .general
    @State private var searchText: String = ""
    @State private var highlightedItemId: String?

    var body: some View {
        NavigationSplitView {
            SettingsSidebarView(
                selectedCategory: $selectedCategory,
                searchText: $searchText,
                highlightedItemId: $highlightedItemId,
            )
            .toolbar(removing: .sidebarToggle)
        } detail: {
            SettingsContentView(
                selectedCategory: selectedCategory,
                highlightedItemId: highlightedItemId,
            )
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 750, minHeight: 500)
    }
}
