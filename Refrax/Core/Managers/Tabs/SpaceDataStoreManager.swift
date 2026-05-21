import Foundation
import WebKit

/// Manages WKWebsiteDataStore instances for spaces with separate browsing data.
///
/// This manager handles the lifecycle of per-space data stores:
/// - Creates/retrieves persistent data stores using the space's UUID as identifier
/// - Creates non-persistent data stores for private browsing spaces
/// - Caches data store instances to avoid redundant creation
/// - Removes data stores when spaces are deleted
/// - Provides the appropriate data store for WebPage configuration
///
/// ## Data Store Types
///
/// | `dataStoreMode` | Data Store Type | Persistence |
/// |-----------------|-----------------|-------------|
/// | `.global`       | `.default()`    | Shared persistent |
/// | `.separate`     | `WKWebsiteDataStore(forIdentifier:)` | Isolated persistent |
/// | `.private`      | `.nonPersistent()` | None (memory only) |
///
/// ## Thread Safety
///
/// All methods must be called on the main actor (WKWebsiteDataStore requirement).
@Observable
final class SpaceDataStoreManager {
    /// Cached persistent data stores keyed by space ID.
    ///
    /// Stores are cached to avoid creating multiple instances for the same space.
    /// The cache is cleared when a space is deleted.
    private var dataStoreCache: [UUID: WKWebsiteDataStore] = [:]

    /// Cached non-persistent data stores for private spaces, keyed by space ID.
    ///
    /// Each private space gets its own non-persistent store instance for isolation.
    /// These are cleaned up when the private space is closed.
    private var privateStoreCache: [UUID: WKWebsiteDataStore] = [:]

    /// The shared default data store for spaces without separate data.
    private let defaultDataStore: WKWebsiteDataStore = .default()

    // MARK: - Initialization

    init() {}

    // MARK: - Data Store Access

    /// Returns the appropriate data store for a space.
    ///
    /// - Parameter space: The space to get a data store for.
    /// - Returns: The appropriate data store based on space configuration:
    ///   - Private spaces: non-persistent (memory-only) data store
    ///   - Separate data store spaces: persistent isolated data store
    ///   - Normal spaces: shared default data store
    func dataStore(for space: Space) -> WKWebsiteDataStore {
        switch space.dataStoreMode {
        case .private:
            nonPersistentDataStore(forSpaceID: space.id)
        case .separate:
            dataStore(forSpaceID: space.id)
        case .global:
            defaultDataStore
        }
    }

    /// Returns a non-persistent data store for a private space.
    ///
    /// Each private space gets its own non-persistent store instance so that
    /// multiple private spaces remain isolated from each other.
    ///
    /// - Parameter spaceID: The space's unique identifier.
    /// - Returns: A non-persistent data store.
    func nonPersistentDataStore(forSpaceID spaceID: UUID) -> WKWebsiteDataStore {
        if let cached = privateStoreCache[spaceID] {
            return cached
        }

        let store = WKWebsiteDataStore.nonPersistent()
        privateStoreCache[spaceID] = store

        Logger.info("Created non-persistent data store for private space: \(spaceID)", category: Logger.tabs)

        return store
    }

    /// Returns a persistent data store for a space ID.
    ///
    /// Creates the data store if it doesn't exist in the cache.
    ///
    /// - Parameter spaceID: The space's unique identifier.
    /// - Returns: A persistent data store associated with the space ID.
    func dataStore(forSpaceID spaceID: UUID) -> WKWebsiteDataStore {
        if let cached = dataStoreCache[spaceID] {
            return cached
        }

        let store = WKWebsiteDataStore(forIdentifier: spaceID)
        dataStoreCache[spaceID] = store

        Logger.info("Created data store for space: \(spaceID)", category: Logger.tabs)

        return store
    }

    // MARK: - Data Store Removal

    /// Removes the data store for a space.
    ///
    /// For persistent data stores, this:
    /// 1. Removes the store from the cache
    /// 2. Calls `WKWebsiteDataStore.remove(forIdentifier:)` to delete the persisted data
    ///
    /// For private (non-persistent) data stores, this simply removes from the cache.
    /// The data is automatically discarded since nothing was persisted.
    ///
    /// - Parameter space: The space whose data store should be removed.
    func removeDataStore(for space: Space) async {
        switch space.dataStoreMode {
        case .private:
            removePrivateDataStore(forSpaceID: space.id)
        case .separate:
            await removeDataStore(forSpaceID: space.id)
        case .global:
            break // Nothing to clean up
        }
    }

    /// Removes a non-persistent data store from the cache.
    ///
    /// Since private data stores don't persist anything, this just cleans up the cache.
    ///
    /// - Parameter spaceID: The space's unique identifier.
    func removePrivateDataStore(forSpaceID spaceID: UUID) {
        privateStoreCache.removeValue(forKey: spaceID)
        Logger.info("Removed non-persistent data store for private space: \(spaceID)", category: Logger.tabs)
    }

    /// Removes the data store for a space ID.
    ///
    /// - Parameter spaceID: The space's unique identifier.
    func removeDataStore(forSpaceID spaceID: UUID) async {
        dataStoreCache.removeValue(forKey: spaceID)

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                WKWebsiteDataStore.remove(forIdentifier: spaceID) { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }
            Logger.info("Removed data store for space: \(spaceID)", category: Logger.tabs)
        } catch {
            Logger.error("Failed to remove data store for space \(spaceID): \(error)", category: Logger.tabs)
        }
    }

    // MARK: - Cache Management

    /// Clears a data store from the cache without deleting it.
    ///
    /// Use this when a space is unloaded but not deleted.
    ///
    /// - Parameter spaceID: The space's unique identifier.
    func evictFromCache(spaceID: UUID) {
        dataStoreCache.removeValue(forKey: spaceID)
        privateStoreCache.removeValue(forKey: spaceID)
    }

    /// Clears all cached data stores.
    ///
    /// Does not delete the underlying persistent data stores.
    func clearCache() {
        dataStoreCache.removeAll()
        privateStoreCache.removeAll()
    }

    // MARK: - Diagnostics

    /// Returns the number of cached persistent data stores.
    var cachedStoreCount: Int {
        dataStoreCache.count
    }

    /// Returns the number of cached private (non-persistent) data stores.
    var cachedPrivateStoreCount: Int {
        privateStoreCache.count
    }

    /// Lists all existing data store identifiers on disk.
    ///
    /// This includes data stores that may no longer be associated with any space.
    func fetchAllDataStoreIdentifiers() async -> [UUID] {
        await withCheckedContinuation { continuation in
            WKWebsiteDataStore.fetchAllDataStoreIdentifiers { identifiers in
                continuation.resume(returning: identifiers)
            }
        }
    }

    /// Cleans up orphaned data stores that are no longer associated with any space.
    ///
    /// - Parameter validSpaceIDs: Set of space IDs that should retain their data stores.
    func cleanupOrphanedDataStores(validSpaceIDs: Set<UUID>) async {
        let existingIdentifiers = await fetchAllDataStoreIdentifiers()

        for identifier in existingIdentifiers {
            if !validSpaceIDs.contains(identifier) {
                Logger.info("Removing orphaned data store: \(identifier)", category: Logger.tabs)
                await removeDataStore(forSpaceID: identifier)
            }
        }
    }
}
