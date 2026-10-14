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
    let navigation: SettingsNavigation
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
        // The sidebar's selection and the controls follow Refrax's accent, not the system's.
        .tint(Color.appAccentColor)
        .frame(minWidth: 750, minHeight: 500)
        .onChange(of: navigation.requestedCategory, initial: true) { _, category in
            guard let category else { return }
            searchText = ""
            selectedCategory = category
            navigation.requestedCategory = nil
        }
    }
}
