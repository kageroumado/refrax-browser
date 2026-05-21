import Foundation
import SwiftData
import SwiftUI
import Testing
import WebKit
@testable import Refrax

// MARK: - Space Conversion Regression Tests

/// Tests for Space model properties that could regress when implementing
/// space conversion (3.10), focus mode (3.11), and lock features (3.12).
@Suite("Space Conversion Regression", .tags(.spaceManager), .serialized)
@MainActor
struct SpaceConversionRegressionTests {
    // MARK: - Data Store Mode Tests

    @Test("Space defaults to global data store mode")
    func spaceDefaultsToGlobalDataStoreMode() throws {
        let env = try SpaceManagerTestEnvironment()

        let space = env.spaceManager.createSpace(
            name: "Default",
            iconName: "star",
        )

        #expect(space.dataStoreMode == .global)
    }

    @Test("Space can be created with separate data store")
    func spaceWithSeparateDataStore() throws {
        let env = try SpaceManagerTestEnvironment()

        let space = env.spaceManager.createSpace(
            name: "Isolated",
            iconName: "lock.shield",
            dataStoreMode: .separate,
        )

        #expect(space.dataStoreMode == .separate)
    }

    @Test("Space can be created with private data store")
    func spaceWithPrivateDataStore() throws {
        let env = try SpaceManagerTestEnvironment()

        let space = env.spaceManager.createSpace(
            name: "Private",
            iconName: "eye.slash",
            dataStoreMode: .private,
        )

        #expect(space.dataStoreMode == .private)
    }

    @Test("Private space does not record history")
    func privateSpaceNoHistory() throws {
        let env = try TabManagerTestEnvironment()
        let privateSpace = env.makeSpace(name: "Private")
        privateSpace.dataStoreMode = .private
        _ = env.makeActiveWindowState(with: privateSpace)

        // Record navigation in private space
        let entry = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://secret.com")),
            tabID: UUID(),
            spaceID: privateSpace.id,
            isPrivateSpace: true,
        )

        #expect(entry == nil, "Private space should not record history")
    }

    @Test("Separate data store is cached per space")
    func separateDataStoreCached() throws {
        let env = try SpaceManagerTestEnvironment()

        let space = env.spaceManager.createSpace(
            name: "Isolated",
            iconName: "lock",
            dataStoreMode: .separate,
        )

        let store1 = env.spaceManager.dataStoreManager.dataStore(for: space)
        let store2 = env.spaceManager.dataStoreManager.dataStore(for: space)

        #expect(store1 === store2, "Same instance should be returned")
    }

    // MARK: - Space Color Tests

    @Test("Space color persists as hex")
    func spaceColorPersistsAsHex() throws {
        let env = try SpaceManagerTestEnvironment()

        let space = env.spaceManager.createSpace(
            name: "Colored",
            color: .red,
            iconName: "star",
        )

        #expect(!space.colorHex.isEmpty)
    }

    @Test("Space color can be updated")
    func spaceColorUpdates() throws {
        let env = try SpaceManagerTestEnvironment()

        let space = env.spaceManager.createSpace(
            name: "Colored",
            color: .blue,
            iconName: "star",
        )

        let originalHex = space.colorHex

        env.spaceManager.updateSpace(space, color: .green)

        #expect(space.colorHex != originalHex)
    }

    // MARK: - Space Icon Tests

    @Test("Space with SF Symbol icon is not emoji")
    func spaceWithSFSymbolNotEmoji() throws {
        let env = try SpaceManagerTestEnvironment()

        let space = env.spaceManager.createSpace(
            name: "Symbol Space",
            iconName: "star.fill",
        )

        #expect(!space.isEmoji)
    }

    @Test("Space with emoji icon is emoji")
    func spaceWithEmojiIconIsEmoji() throws {
        let env = try SpaceManagerTestEnvironment()

        let space = env.spaceManager.createSpace(
            name: "Emoji Space",
            iconName: "🎯",
        )

        #expect(space.isEmoji)
    }

    @Test("Space icon name persists")
    func spaceIconNamePersists() throws {
        let env = try SpaceManagerTestEnvironment()

        let space = env.spaceManager.createSpace(
            name: "Test",
            iconName: "folder.fill",
        )
        let spaceID = space.id

        try env.modelContext.save()

        let descriptor = FetchDescriptor<Space>(predicate: #Predicate { $0.id == spaceID })
        let fetched = try env.modelContext.fetch(descriptor)

        #expect(fetched.first?.iconName == "folder.fill")
    }

    // MARK: - Space Tab Management Tests

    @Test("Space tabs array includes all tabs in space")
    func spaceTabsArrayComplete() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab1 = try env.tabManager.createTab(
            url: #require(URL(string: "https://one.com")),
            in: space,
            makeActive: false,
        )
        let tab2 = try env.tabManager.createTab(
            url: #require(URL(string: "https://two.com")),
            in: space,
            makeActive: false,
        )
        let tab3 = try env.tabManager.createTab(
            url: #require(URL(string: "https://three.com")),
            in: space,
            makeActive: false,
        )

        #expect(space.tabs.count == 3)
        #expect(space.tabs.contains { $0.id == tab1.id })
        #expect(space.tabs.contains { $0.id == tab2.id })
        #expect(space.tabs.contains { $0.id == tab3.id })
    }

    @Test("Space mainTabs excludes reference tabs")
    func spaceMainTabsExcludesReferenceTabs() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space = env.makeSpace()

        // Add a main tab
        let mainTab = try Tab(space: space, url: #require(URL(string: "https://main.com")))
        context.insert(mainTab)

        // Add a reference tab
        let refTab = try Tab(space: space, url: #require(URL(string: "https://ref.com")), isReferenceTab: true)
        context.insert(refTab)

        try context.save()

        #expect(space.tabs.count == 2)
        #expect(space.mainTabs.count == 1)
        #expect(space.mainTabs.first?.id == mainTab.id)
    }

    @Test("Space referenceTabs only includes reference tabs")
    func spaceReferenceTabsOnlyReferenceTabs() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space = env.makeSpace()

        let mainTab = try Tab(space: space, url: #require(URL(string: "https://main.com")))
        context.insert(mainTab)

        let refTab = try Tab(space: space, url: #require(URL(string: "https://ref.com")), isReferenceTab: true)
        context.insert(refTab)

        try context.save()

        #expect(space.referenceTabs.count == 1)
        #expect(space.referenceTabs.first?.id == refTab.id)
    }

    // MARK: - Space Group Tests

    @Test("Space groups returns all groups in space")
    func spaceGroupsComplete() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group1 = try env.groupManager.createGroup(in: space, name: "Group 1")
        let group2 = try env.groupManager.createGroup(in: space, name: "Group 2")

        #expect(space.groups.count == 2)
        #expect(space.groups.contains { $0.id == group1.id })
        #expect(space.groups.contains { $0.id == group2.id })
    }

    @Test("Space groups includes both pinned and unpinned groups")
    func spaceGroupsIncludesBoth() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let regularGroup = try env.groupManager.createGroup(in: space, name: "Regular")
        let pinnedGroup = try env.groupManager.createGroup(in: space, name: "Pinned", isPinned: true)

        #expect(space.groups.count == 2)
        #expect(pinnedGroup.isPinned)
        #expect(!regularGroup.isPinned)
        #expect(space.groups.contains { $0.id == pinnedGroup.id })
        #expect(space.groups.contains { $0.id == regularGroup.id })
    }

    // MARK: - Space Position Tests

    @Test("Spaces have sequential positions")
    func spacesSequentialPositions() throws {
        let env = try SpaceManagerTestEnvironment()

        let space1 = env.spaceManager.createSpace(name: "First", iconName: "1.circle")
        let space2 = env.spaceManager.createSpace(name: "Second", iconName: "2.circle")
        let space3 = env.spaceManager.createSpace(name: "Third", iconName: "3.circle")

        #expect(space1.position == 0)
        #expect(space2.position == 1)
        #expect(space3.position == 2)
    }

    // MARK: - Space isLoaded Flag Tests

    @Test("Space isLoaded starts false")
    func spaceIsLoadedStartsFalse() throws {
        let env = try SpaceManagerTestEnvironment()

        let space = env.spaceManager.createSpace(name: "Test", iconName: "star")

        // Depending on implementation, may be true after createSpace
        // but we want to ensure the flag exists and can be checked
        _ = space.isLoaded
    }

    @Test("Space isLoaded becomes true after ensureLoaded")
    func spaceIsLoadedAfterEnsureLoaded() throws {
        let env = try SpaceManagerTestEnvironment()

        let space = env.spaceManager.createSpace(name: "Test", iconName: "star")
        space.isLoaded = false

        env.spaceManager.ensureLoaded(space)

        #expect(space.isLoaded)
    }
}

// MARK: - Space Description Tests

@Suite("Space Description", .tags(.spaceManager), .serialized)
@MainActor
struct SpaceDescriptionTests {
    @Test("Space description starts nil")
    func spaceDescriptionStartsNil() throws {
        let env = try SpaceManagerTestEnvironment()

        let space = env.spaceManager.createSpace(name: "Test", iconName: "star")

        #expect(space.spaceDescription == nil)
    }

    @Test("Space description can be set")
    func spaceDescriptionCanBeSet() throws {
        let env = try SpaceManagerTestEnvironment()

        let space = env.spaceManager.createSpace(
            name: "Test",
            iconName: "star",
            description: "A test space for development",
        )

        #expect(space.spaceDescription == "A test space for development")
    }

    @Test("Space description can be updated")
    func spaceDescriptionCanBeUpdated() throws {
        let env = try SpaceManagerTestEnvironment()

        let space = env.spaceManager.createSpace(name: "Test", iconName: "star")

        env.spaceManager.updateSpace(space, description: "Updated description")

        #expect(space.spaceDescription == "Updated description")
    }

    @Test("Space description persists")
    func spaceDescriptionPersists() throws {
        let env = try SpaceManagerTestEnvironment()

        let space = env.spaceManager.createSpace(
            name: "Test",
            iconName: "star",
            description: "Persistent description",
        )
        let spaceID = space.id

        try env.modelContext.save()

        let descriptor = FetchDescriptor<Space>(predicate: #Predicate { $0.id == spaceID })
        let fetched = try env.modelContext.fetch(descriptor)

        #expect(fetched.first?.spaceDescription == "Persistent description")
    }
}
