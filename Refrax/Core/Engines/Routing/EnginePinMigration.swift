import Foundation
import SwiftData

/// Clears, once per install, the engine pins that name the default engine.
///
/// A move to the engine a page gets anyway leaves it unpinned (``EngineChoice/pin(movingTo:at:)``),
/// so a stored pin naming the default engine would only keep its page from following site rules.
enum EnginePinMigration {
    private enum Constants {
        static let completedKey = "website.refrax.migration.enginePinsFollowSiteRules"
    }

    /// Clears the pins once; later calls do nothing.
    ///
    /// - Returns: How many pins were cleared.
    @discardableResult
    static func runOnce(in context: ModelContext, defaultEngine: EngineID, defaults: UserDefaults = .standard) -> Int {
        guard !defaults.bool(forKey: Constants.completedKey) else { return 0 }
        let cleared = clearPins(naming: defaultEngine, in: context)
        defaults.set(true, forKey: Constants.completedKey)
        return cleared
    }

    /// Unpins every page pinned to `engine`.
    static func clearPins(naming engine: EngineID, in context: ModelContext) -> Int {
        let raw = engine.rawValue
        let descriptor = FetchDescriptor<TabPage>(predicate: #Predicate { $0.engineID != nil })
        guard let pinned = try? context.fetch(descriptor) else { return 0 }
        let matching = pinned.filter { $0.engineID == raw }
        for page in matching {
            page.engineID = nil
        }
        if !matching.isEmpty {
            try? context.save()
            Logger.info("Unpinned \(matching.count) page(s) from the default engine \(engine)", category: Logger.engines)
        }
        return matching.count
    }
}
