import Foundation
import SwiftData
import SwiftUI
import Testing
import WebKit

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for SpaceDataStoreManager operations.
    @Tag static var spaceDataStoreManager: Self
}

// MARK: - SpaceDataStoreManager Initial State Tests

@Suite("SpaceDataStoreManager Initial State", .tags(.spaceDataStoreManager), .serialized)
@MainActor
struct SpaceDataStoreInitialStateTests {
    @Test("Initially has empty cache")
    func initiallyEmptyCache() {
        let manager = SpaceDataStoreManager()

        #expect(manager.cachedStoreCount == 0)
    }
}

// MARK: - SpaceDataStoreManager Data Store Access Tests

@Suite("SpaceDataStoreManager Data Store Access", .tags(.spaceDataStoreManager), .serialized)
@MainActor
struct SpaceDataStoreAccessTests {
    @Test("Returns default store for space without separate data store")
    func defaultStoreForNonSeparate() throws {
        let env = try TabManagerTestEnvironment()
        let manager = SpaceDataStoreManager()

        let space = env.makeSpace()
        space.dataStoreMode = .global

        let store = manager.dataStore(for: space)

        #expect(store === WKWebsiteDataStore.default())
        #expect(manager.cachedStoreCount == 0, "Default store should not be cached")
    }

    @Test("Returns separate store for space with separate data store")
    func separateStoreForSeparate() throws {
        let env = try TabManagerTestEnvironment()
        let manager = SpaceDataStoreManager()

        let space = env.makeSpace()
        space.dataStoreMode = .separate

        let store = manager.dataStore(for: space)

        #expect(store !== WKWebsiteDataStore.default())
        #expect(manager.cachedStoreCount == 1, "Separate store should be cached")
    }

    @Test("Same space returns same cached store")
    func sameCachedStore() throws {
        let env = try TabManagerTestEnvironment()
        let manager = SpaceDataStoreManager()

        let space = env.makeSpace()
        space.dataStoreMode = .separate

        let store1 = manager.dataStore(for: space)
        let store2 = manager.dataStore(for: space)

        #expect(store1 === store2, "Same space should return cached instance")
        #expect(manager.cachedStoreCount == 1)
    }

    @Test("Different spaces get different stores")
    func differentStores() throws {
        let env = try TabManagerTestEnvironment()
        let manager = SpaceDataStoreManager()

        let space1 = env.makeSpace(name: "Space 1")
        space1.dataStoreMode = .separate

        let space2 = env.makeSpace(name: "Space 2")
        space2.dataStoreMode = .separate

        let store1 = manager.dataStore(for: space1)
        let store2 = manager.dataStore(for: space2)

        #expect(store1 !== store2, "Different spaces should have different stores")
        #expect(manager.cachedStoreCount == 2)
    }

    @Test("Direct space ID access creates and caches store")
    func directSpaceIDAccess() {
        let manager = SpaceDataStoreManager()
        let spaceID = UUID()

        #expect(manager.cachedStoreCount == 0)

        let store1 = manager.dataStore(forSpaceID: spaceID)
        #expect(manager.cachedStoreCount == 1)

        let store2 = manager.dataStore(forSpaceID: spaceID)
        #expect(store1 === store2, "Should return cached instance")
        #expect(manager.cachedStoreCount == 1)
    }
}

// MARK: - SpaceDataStoreManager Cache Management Tests

@Suite("SpaceDataStoreManager Cache Management", .tags(.spaceDataStoreManager), .serialized)
@MainActor
struct SpaceDataStoreCacheTests {
    @Test("Evict from cache removes single entry")
    func evictSingleEntry() throws {
        let env = try TabManagerTestEnvironment()
        let manager = SpaceDataStoreManager()

        let space1 = env.makeSpace(name: "Space 1")
        space1.dataStoreMode = .separate

        let space2 = env.makeSpace(name: "Space 2")
        space2.dataStoreMode = .separate

        _ = manager.dataStore(for: space1)
        _ = manager.dataStore(for: space2)
        #expect(manager.cachedStoreCount == 2)

        manager.evictFromCache(spaceID: space1.id)

        #expect(manager.cachedStoreCount == 1)
    }

    @Test("Evict non-existent space ID is no-op")
    func evictNonExistent() {
        let manager = SpaceDataStoreManager()
        let spaceID = UUID()

        manager.evictFromCache(spaceID: spaceID)

        #expect(manager.cachedStoreCount == 0)
    }

    @Test("Clear cache removes all entries")
    func clearAllEntries() {
        let manager = SpaceDataStoreManager()

        _ = manager.dataStore(forSpaceID: UUID())
        _ = manager.dataStore(forSpaceID: UUID())
        _ = manager.dataStore(forSpaceID: UUID())
        #expect(manager.cachedStoreCount == 3)

        manager.clearCache()

        #expect(manager.cachedStoreCount == 0)
    }

    @Test("Evict followed by access creates new instance")
    func evictThenAccess() {
        let manager = SpaceDataStoreManager()
        let spaceID = UUID()

        _ = manager.dataStore(forSpaceID: spaceID)
        manager.evictFromCache(spaceID: spaceID)
        _ = manager.dataStore(forSpaceID: spaceID)

        // Note: WKWebsiteDataStore(forIdentifier:) may return the same underlying
        // instance for the same UUID, but from the cache perspective, it's a fresh lookup
        #expect(manager.cachedStoreCount == 1)
        // We can't guarantee store1 !== store2 because WebKit may reuse instances
    }
}

// MARK: - SpaceDataStoreManager Remove Tests

@Suite("SpaceDataStoreManager Remove", .tags(.spaceDataStoreManager), .serialized)
@MainActor
struct SpaceDataStoreRemoveTests {
    @Test("Remove is no-op for space without separate data store")
    func removeNoOpForNonSeparate() async throws {
        let env = try TabManagerTestEnvironment()
        let manager = SpaceDataStoreManager()

        let space = env.makeSpace()
        space.dataStoreMode = .global

        // Should not crash and should be a no-op
        await manager.removeDataStore(for: space)

        #expect(manager.cachedStoreCount == 0)
    }

    @Test("Remove clears cache entry")
    func removeClearsCache() async throws {
        let env = try TabManagerTestEnvironment()
        let manager = SpaceDataStoreManager()

        let space = env.makeSpace()
        space.dataStoreMode = .separate

        _ = manager.dataStore(for: space)
        #expect(manager.cachedStoreCount == 1)

        await manager.removeDataStore(for: space)

        #expect(manager.cachedStoreCount == 0, "Cache should be cleared after remove")
    }

    @Test("Remove by space ID clears cache entry")
    func removeByIDClearsCache() async {
        let manager = SpaceDataStoreManager()
        let spaceID = UUID()

        _ = manager.dataStore(forSpaceID: spaceID)
        #expect(manager.cachedStoreCount == 1)

        await manager.removeDataStore(forSpaceID: spaceID)

        #expect(manager.cachedStoreCount == 0)
    }
}

// MARK: - SpaceDataStoreManager Edge Cases

@Suite("SpaceDataStoreManager Edge Cases", .tags(.spaceDataStoreManager), .serialized)
@MainActor
struct SpaceDataStoreEdgeCaseTests {
    @Test("Multiple managers can coexist with separate caches")
    func multipleCaches() {
        let manager1 = SpaceDataStoreManager()
        let manager2 = SpaceDataStoreManager()
        let spaceID = UUID()

        _ = manager1.dataStore(forSpaceID: spaceID)

        #expect(manager1.cachedStoreCount == 1)
        #expect(manager2.cachedStoreCount == 0, "Managers have independent caches")

        _ = manager2.dataStore(forSpaceID: spaceID)

        #expect(manager1.cachedStoreCount == 1)
        #expect(manager2.cachedStoreCount == 1)
    }

    @Test("Clear cache is safe when empty")
    func clearEmptyCache() {
        let manager = SpaceDataStoreManager()

        #expect(manager.cachedStoreCount == 0)

        manager.clearCache()

        #expect(manager.cachedStoreCount == 0)
    }

    @Test("Mixed spaces with different data store settings")
    func mixedSettings() throws {
        let env = try TabManagerTestEnvironment()
        let manager = SpaceDataStoreManager()

        let regularSpace = env.makeSpace(name: "Regular")
        regularSpace.dataStoreMode = .global

        let separateSpace = env.makeSpace(name: "Separate")
        separateSpace.dataStoreMode = .separate

        let regularStore = manager.dataStore(for: regularSpace)
        let separateStore = manager.dataStore(for: separateSpace)

        #expect(regularStore === WKWebsiteDataStore.default())
        #expect(separateStore !== WKWebsiteDataStore.default())
        #expect(manager.cachedStoreCount == 1, "Only separate store is cached")
    }
}

// MARK: - Notes

//
// The following SpaceDataStoreManager functionality touches the file system and
// requires integration testing:
//
// 1. WKWebsiteDataStore.remove(forIdentifier:) - Deletes persisted data from disk
// 2. fetchAllDataStoreIdentifiers() - Queries disk for all existing data stores
// 3. cleanupOrphanedDataStores() - Depends on fetchAllDataStoreIdentifiers
//
// The cache-based tests above verify the in-memory behavior correctly.
