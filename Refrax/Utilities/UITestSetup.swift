import Foundation
import SwiftData

/// Handles UI test setup from launch arguments.
///
/// When the app is launched with `--uitest`, this handler reads additional arguments
/// to configure the initial test state:
///
/// - `--uitest-tabs=N`: Creates N regular (unpinned) tabs
/// - `--uitest-pinned-tabs=N`: Creates N pinned tabs
/// - `--uitest-groups=N`: Creates N groups
/// - `--uitest-grouped-tabs=N`: Creates N tabs per group (default: 2)
/// - `--uitest-favorites=N`: Creates N favorite items
///
/// ## Example
///
/// ```bash
/// open Refrax.app --args --uitest --uitest-tabs=5 --uitest-pinned-tabs=2 --uitest-groups=2
/// ```
///
/// This creates:
/// - 5 regular tabs named "Test Tab 1" through "Test Tab 5"
/// - 2 pinned tabs named "Pinned Tab 1" and "Pinned Tab 2"
/// - 2 groups named "Test Group 1" and "Test Group 2", each with 2 tabs
enum UITestSetup {
    // MARK: - Configuration

    /// Parsed configuration from launch arguments.
    struct Configuration {
        var regularTabCount: Int = 0
        var pinnedTabCount: Int = 0
        var groupCount: Int = 0
        var tabsPerGroup: Int = 2
        var favoriteCount: Int = 0

        /// Whether any test data should be created.
        var hasTestData: Bool {
            regularTabCount > 0 || pinnedTabCount > 0 || groupCount > 0 || favoriteCount > 0
        }
    }

    // MARK: - Detection

    /// Whether the app was launched in UI test mode.
    static var isUITestMode: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("--uitest") || args.contains("-uitest")
    }

    /// Logs a debug message using NSLog (appears in Console.app and test logs).
    static func debugLog(_ message: String) {
        #if DEBUG
            NSLog("UITEST: %@", message)
        #endif
    }

    /// Parses launch arguments into a configuration.
    static func parseConfiguration() -> Configuration {
        var config = Configuration()
        let args = ProcessInfo.processInfo.arguments

        for arg in args {
            if arg.hasPrefix("--uitest-tabs="),
               let value = Int(arg.dropFirst("--uitest-tabs=".count)) {
                config.regularTabCount = value
            } else if arg.hasPrefix("--uitest-pinned-tabs="),
                      let value = Int(arg.dropFirst("--uitest-pinned-tabs=".count)) {
                config.pinnedTabCount = value
            } else if arg.hasPrefix("--uitest-groups="),
                      let value = Int(arg.dropFirst("--uitest-groups=".count)) {
                config.groupCount = value
            } else if arg.hasPrefix("--uitest-grouped-tabs="),
                      let value = Int(arg.dropFirst("--uitest-grouped-tabs=".count)) {
                config.tabsPerGroup = value
            } else if arg.hasPrefix("--uitest-favorites="),
                      let value = Int(arg.dropFirst("--uitest-favorites=".count)) {
                config.favoriteCount = value
            }
        }

        return config
    }

    // MARK: - Test Data Creation

    /// Creates test data for UI testing.
    ///
    /// - Parameters:
    ///   - space: The space to add tabs and groups to.
    ///   - config: The configuration specifying what to create.
    ///   - modelContext: The SwiftData context for persistence.
    ///   - bookmarksManager: Optional bookmarks manager for creating favorites.
    static func createTestData(
        in space: Space,
        config: Configuration,
        modelContext: ModelContext,
        bookmarksManager: BookmarksManager? = nil,
    ) {
        var currentPosition = 0
        var pinnedPosition = 0

        // Create pinned tabs
        for i in 1 ... max(1, config.pinnedTabCount) where config.pinnedTabCount > 0 {
            let tab = Tab(
                space: space,
                url: testURL(for: "pinned-\(i)"),
                title: "Pinned Tab \(i)",
                status: .pinned,
                position: pinnedPosition,
            )
            tab.customName = "Pinned Tab \(i)"
            modelContext.insert(tab)
            pinnedPosition += 1
        }

        // Create groups with their tabs
        for groupIndex in 1 ... max(1, config.groupCount) where config.groupCount > 0 {
            let group = TabGroup(
                space: space,
                name: "Test Group \(groupIndex)",
                color: groupColors[groupIndex % groupColors.count],
                position: currentPosition,
            )
            modelContext.insert(group)
            space.groups.append(group)
            currentPosition += 1

            // Create tabs in the group
            for tabIndex in 1 ... max(1, config.tabsPerGroup) where config.tabsPerGroup > 0 {
                let tab = Tab(
                    space: space,
                    url: testURL(for: "group\(groupIndex)-tab\(tabIndex)"),
                    title: "Group \(groupIndex) Tab \(tabIndex)",
                    status: .regular,
                    groupID: group.id,
                    position: currentPosition,
                )
                tab.customName = "Group \(groupIndex) Tab \(tabIndex)"
                tab.group = group
                modelContext.insert(tab)
                currentPosition += 1
            }
        }

        // Create regular (ungrouped) tabs
        for i in 1 ... max(1, config.regularTabCount) where config.regularTabCount > 0 {
            let tab = Tab(
                space: space,
                url: testURL(for: "tab-\(i)"),
                title: "Test Tab \(i)",
                status: .regular,
                position: currentPosition,
            )
            tab.customName = "Test Tab \(i)"
            modelContext.insert(tab)
            currentPosition += 1
        }

        try? modelContext.save()

        // Create favorites (live favorites with their own tabs)
        if let bookmarksManager, config.favoriteCount > 0 {
            for i in 1 ... config.favoriteCount {
                bookmarksManager.createBookmark(
                    url: testURL(for: "favorite-\(i)"),
                    title: "Test Favorite \(i)",
                    isFavorite: true,
                    favoriteMode: .liveFavorite,
                )
            }
        }
    }

    // MARK: - Helpers

    /// Generates a test URL for a given identifier.
    private static func testURL(for _: String) -> URL {
        // Use about:blank for test tabs - no actual web loading needed
        .blank
    }

    /// Colors available for test groups.
    private static let groupColors: [String] = [
        "#FF6B6B", // Red
        "#4ECDC4", // Teal
        "#45B7D1", // Blue
        "#96CEB4", // Green
        "#FFEAA7", // Yellow
        "#DDA0DD", // Purple
    ]
}
