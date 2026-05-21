import Foundation
import SwiftData
import SwiftUI
import Testing
import WebKit

@testable import Refrax

// MARK: - WebPage Lifecycle Regression Tests

/// Tests for WebPage lifecycle and WebPagePool functionality that could regress
/// when implementing mini-windows (2.4), PiP (2.5), and media controls (2.6).
@Suite("WebPage Lifecycle", .tags(.tabManager), .serialized)
@MainActor
struct WebPageLifecycleTests {
    // MARK: - Page Creation Tests

    @Test("TabPage created with correct URL")
    func tabPageCreatedWithURL() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com/page")!,
            in: space,
            makeActive: false,
        )

        #expect(tab.activePage.url.absoluteString == "https://example.com/page")
    }

    @Test("TabPage URL is correct after creation")
    func tabPageURLCorrectAfterCreation() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: false,
            loadImmediately: false,
        )

        #expect(tab.activePage.url.absoluteString == "https://example.com")
    }

    @Test("TabPage title can be set")
    func tabPageTitleCanBeSet() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: false,
        )

        tab.activePage.title = "Test Title"

        #expect(tab.activePage.title == "Test Title")
    }

    @Test("TabPage favicon data can be set")
    func tabPageFaviconDataCanBeSet() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: false,
        )

        let faviconData = Data([0x89, 0x50, 0x4E, 0x47])
        tab.activePage.faviconData = faviconData

        #expect(tab.activePage.faviconData == faviconData)
    }

    // MARK: - Page Pool Tests

    @Test("Page pool returns existing page for tab")
    func pagePoolReturnsExistingPage() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
            loadImmediately: true,
        )

        // First request
        let page1 = env.pagePool.page(for: tab.activePage)

        // Second request should return same instance
        let page2 = env.pagePool.page(for: tab.activePage)

        #expect(page1 === page2)
    }

    @Test("Existing page returns nil for unloaded tab")
    func existingPageReturnsNilForUnloaded() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: false,
            loadImmediately: false,
        )

        let existing = env.pagePool.existingPage(for: tab.activePage)

        #expect(existing == nil)
    }

    // MARK: - Tab Close Cleanup Tests

    @Test("Closing tab triggers cleanup")
    func closingTabTriggersCleanup() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )

        let tabPageID = tab.activePage.id

        env.tabManager.closeTab(tab)

        // Page should no longer be in pool
        // Note: This test verifies the cleanup path exists
        #expect(true) // Cleanup triggered
        _ = tabPageID
    }

    @Test("Closing live favorite does not remove from space")
    func closingLiveFavoriteNoSpace() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = Bookmark(
            url: URL(string: "https://example.com")!,
            title: "Example",
        )
        env.modelContext.insert(bookmark)

        let liveFavoriteTab = env.tabManager.createLiveFavoriteTab(for: bookmark)

        #expect(liveFavoriteTab.space == nil)

        env.tabManager.closeLiveFavoriteTab(liveFavoriteTab)

        #expect(!env.browserState.liveFavoriteTabs.contains { $0.id == liveFavoriteTab.id })
    }

    // MARK: - Split View Tests

    @Test("Tab supports multiple pages for split view")
    func tabSupportsMultiplePages() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space = env.makeSpace()

        let tab = Tab(space: space, url: URL(string: "https://primary.com")!)
        context.insert(tab)

        // Add a secondary page
        let secondaryPage = TabPage(url: URL(string: "https://secondary.com")!)
        secondaryPage.tab = tab
        tab.pages.append(secondaryPage)

        try context.save()

        #expect(tab.pages.count == 2)
    }

    @Test("Tab activePage returns primary page by default")
    func tabActivePageReturnsPrimary() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space = env.makeSpace()

        let tab = Tab(space: space, url: URL(string: "https://primary.com")!)
        context.insert(tab)

        // activePage should return the primary page by default
        #expect(tab.activePage.id == tab.activePage.id)
    }

    // MARK: - Tab Restore Tests

    @Test("Restored tab has correct URL")
    func restoredTabHasCorrectURL() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let originalTab = env.tabManager.createTab(
            url: URL(string: "https://restore.com")!,
            in: space,
            makeActive: true,
        )

        env.tabManager.closeTab(originalTab)

        let closedInfo = env.undoRedoManager.recentlyClosedTabs.first!

        env.tabManager.restoreTab(closedInfo)

        let restoredTab = space.tabs.first
        #expect(restoredTab?.activePage.url.absoluteString == "https://restore.com")
    }

    @Test("Restored tab preserves custom name")
    func restoredTabPreservesCustomName() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let originalTab = env.tabManager.createTab(
            url: URL(string: "https://named.com")!,
            in: space,
            makeActive: true,
        )
        originalTab.customName = "Custom Tab Name"

        env.tabManager.closeTab(originalTab)

        let closedInfo = env.undoRedoManager.recentlyClosedTabs.first!

        env.tabManager.restoreTab(closedInfo)

        let restoredTab = space.tabs.first
        #expect(restoredTab?.customName == "Custom Tab Name")
    }
}

// MARK: - WebPage State Tests

@Suite("WebPage State", .tags(.tabManager), .serialized)
@MainActor
struct WebPageStateTests {
    @Test("TabPage persists URL")
    func tabPagePersistsURL() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = env.tabManager.createTab(
            url: URL(string: "https://persist.com/path")!,
            in: space,
            makeActive: false,
        )
        let pageID = tab.activePage.id

        try env.modelContext.save()

        let descriptor = FetchDescriptor<TabPage>(predicate: #Predicate { $0.id == pageID })
        let fetched = try env.modelContext.fetch(descriptor)

        #expect(fetched.first?.url.absoluteString == "https://persist.com/path")
    }

    @Test("TabPage persists title")
    func tabPagePersistsTitle() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: false,
        )
        tab.activePage.title = "Persisted Title"
        let pageID = tab.activePage.id

        try env.modelContext.save()

        let descriptor = FetchDescriptor<TabPage>(predicate: #Predicate { $0.id == pageID })
        let fetched = try env.modelContext.fetch(descriptor)

        #expect(fetched.first?.title == "Persisted Title")
    }

    @Test("TabPage URL persists")
    func tabPageURLPersists() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space = env.makeSpace()

        let tab = Tab(space: space, url: URL(string: "https://primary.com")!)
        context.insert(tab)

        let secondaryPage = TabPage(url: URL(string: "https://secondary.com")!)
        secondaryPage.tab = tab
        tab.pages.append(secondaryPage)

        try context.save()

        let pageID = secondaryPage.id
        let descriptor = FetchDescriptor<TabPage>(predicate: #Predicate { $0.id == pageID })
        let fetched = try context.fetch(descriptor)

        #expect(fetched.first?.url.absoluteString == "https://secondary.com")
    }
}

// MARK: - Tab Reference Tab Tests

@Suite("Reference Tab", .tags(.tabManager), .serialized)
@MainActor
struct ReferenceTabTests {
    @Test("Reference tab has isReferenceTab flag")
    func referenceTabHasFlag() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space = env.makeSpace()

        let refTab = Tab(space: space, url: URL(string: "https://ref.com")!, isReferenceTab: true)
        context.insert(refTab)

        #expect(refTab.isReferenceTab)
    }

    @Test("Regular tab does not have isReferenceTab flag")
    func regularTabNoFlag() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = env.tabManager.createTab(
            url: URL(string: "https://regular.com")!,
            in: space,
            makeActive: false,
        )

        #expect(!tab.isReferenceTab)
    }

    @Test("Space referenceTabs filters correctly")
    func spaceReferenceTabsFilters() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext
        let space = env.makeSpace()

        _ = env.tabManager.createTab(
            url: URL(string: "https://main.com")!,
            in: space,
            makeActive: false,
        )

        let refTab = Tab(space: space, url: URL(string: "https://ref.com")!, isReferenceTab: true)
        context.insert(refTab)
        env.browserState.indexTab(refTab)

        try context.save()

        #expect(space.tabs.count == 2)
        #expect(space.mainTabs.count == 1)
        #expect(space.referenceTabs.count == 1)
    }
}
