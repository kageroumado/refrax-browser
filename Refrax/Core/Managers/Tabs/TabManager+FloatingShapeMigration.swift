import Foundation

// MARK: - Migration

extension TabManager {
    /// Rewrites every stored floating placement's compact flag as a card shape, once per store.
    ///
    /// Runs at launch after the spaces load and before anything else reads the placements.
    func migrateFloatingShapesIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: FloatingShapeMigration.completedKey) else { return }

        var tabs = state.favoriteTabs
        for space in state.spaces {
            spaceManager.ensureLoaded(space)
            tabs += space.tabs
        }
        var migrated = 0
        for tab in tabs {
            guard let data = FloatingShapeMigration.migrated(tab.boardFrameData) else { continue }
            tab.boardFrameData = data
            migrated += 1
        }
        defaults.set(true, forKey: FloatingShapeMigration.completedKey)
        scheduleSave()
        Logger.info("Floating shape migration rewrote \(migrated) placements", category: Logger.tabs)
    }
}

/// The once-per-store move from a floating placement's `isCompact` flag to its ``FloatingCardShape``:
/// a compact card becomes a tab, any other card a live page.
nonisolated enum FloatingShapeMigration {
    /// The defaults key set once the migration has run.
    static let completedKey = "website.refrax.migration.floatingShapes"

    /// The stored board data with its floating placement's flag rewritten as a shape, or `nil`
    /// when there is nothing to rewrite.
    static func migrated(_ boardFrameData: Data?) -> Data? {
        guard let boardFrameData,
              var board = (try? JSONSerialization.jsonObject(with: boardFrameData)) as? [String: Any],
              var floating = board["floating"] as? [String: Any],
              floating["shape"] == nil else { return nil }
        let isCompact = floating.removeValue(forKey: "isCompact") as? Bool ?? true
        floating["shape"] = (isCompact ? FloatingCardShape.tab : .live).rawValue
        board["floating"] = floating
        return try? JSONSerialization.data(withJSONObject: board, options: [.sortedKeys])
    }
}
