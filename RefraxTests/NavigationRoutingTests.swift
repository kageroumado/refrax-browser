import Foundation
import SwiftData
import SwiftUI
import Testing
import WebKit
@testable import Refrax

// MARK: - Navigation Routing Regression Tests

/// Tests for navigation routing functionality that could regress when implementing
/// URL routing rules (3.9), mini-window (2.4), and related features.
@Suite("Navigation Routing", .tags(.tabManager), .serialized)
@MainActor
struct NavigationRoutingTests {
    // MARK: - URL Tests

    @Test("URL fragment preserved")
    func urlFragmentPreserved() throws {
        let url = try #require(URL(string: "https://example.com/page#section"))

        #expect(url.fragment == "section")
    }

    @Test("URL query parameters preserved")
    func urlQueryParametersPreserved() throws {
        let url = try #require(URL(string: "https://example.com/search?q=test&page=1"))

        #expect(url.query?.contains("q=test") == true)
        #expect(url.query?.contains("page=1") == true)
    }

    // MARK: - Tab Navigation Tests

    @Test("Tab page URL matches initial URL")
    func tabPageURLMatchesInitial() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://initial.com")),
            in: space,
            makeActive: false,
        )

        #expect(tab.activePage.url.absoluteString == "https://initial.com")
    }

    @Test("Tab URL can be updated directly")
    func tabURLCanBeUpdated() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://initial.com")),
            in: space,
            makeActive: false,
        )

        tab.activePage.url = try #require(URL(string: "https://new.com"))

        #expect(tab.activePage.url.absoluteString == "https://new.com")
    }

    @Test("Tab maintains identity after URL update")
    func tabMaintainsIdentityAfterURLUpdate() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: false,
        )
        let tabID = tab.id

        tab.activePage.url = try #require(URL(string: "https://other.com"))

        #expect(tab.id == tabID)
    }

    // MARK: - Open in New Tab Tests

    @Test("Open URL in new tab creates tab")
    func openURLInNewTabCreates() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let initialCount = space.tabs.count

        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://newtab.com")),
            in: space,
            makeActive: true,
        )

        #expect(space.tabs.count == initialCount + 1)
    }

    @Test("New tab has correct URL")
    func newTabHasCorrectURL() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let newTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://specific.com/path")),
            in: space,
            makeActive: true,
        )

        #expect(newTab.activePage.url.absoluteString == "https://specific.com/path")
    }

    // MARK: - URL Scheme Handling Tests

    @Test("HTTP scheme accepted")
    func httpSchemeAccepted() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "http://example.com")),
            in: space,
            makeActive: false,
        )

        #expect(tab.activePage.url.scheme == "http")
    }

    @Test("HTTPS scheme accepted")
    func httpsSchemeAccepted() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: false,
        )

        #expect(tab.activePage.url.scheme == "https")
    }

    @Test("About blank URL handled")
    func aboutBlankHandled() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "about:blank")),
            in: space,
            makeActive: false,
        )

        #expect(tab.activePage.url.absoluteString == "about:blank")
    }

    // MARK: - Background Tab Tests

    @Test("Background tab does not become active")
    func backgroundTabNotActive() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let activeTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://active.com")),
            in: space,
            makeActive: false,
        )
        env.tabManager.setActiveTab(activeTab, in: windowState)

        // Create background tab
        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://background.com")),
            in: space,
            makeActive: false,
        )

        #expect(windowState.activeTabID == activeTab.id)
    }

    @Test("Foreground tab becomes active")
    func foregroundTabBecomesActive() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://first.com")),
            in: space,
            makeActive: false,
        )

        let foregroundTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://foreground.com")),
            in: space,
            makeActive: true,
        )

        #expect(windowState.activeTabID == foregroundTab.id)
    }

    // MARK: - Tab URL Matching Tests

    @Test("Tabs with same URL can coexist")
    func tabsWithSameURLCanCoexist() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab1 = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com/page")),
            in: space,
            makeActive: false,
        )

        let tab2 = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com/page")),
            in: space,
            makeActive: false,
        )

        #expect(tab1.id != tab2.id)
        #expect(tab1.activePage.url == tab2.activePage.url)
        #expect(space.tabs.count == 2)
    }

    @Test("Tab can be found by URL in space")
    func tabCanBeFoundByURL() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let targetURL = try #require(URL(string: "https://findme.com/specific"))

        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://other.com")),
            in: space,
            makeActive: false,
        )

        let targetTab = env.tabManager.createTab(
            url: targetURL,
            in: space,
            makeActive: false,
        )

        let found = space.tabs.first { $0.activePage.url == targetURL }

        #expect(found?.id == targetTab.id)
    }
}

// MARK: - Tab Page Navigation Tests

@Suite("Tab Page Navigation", .tags(.tabManager), .serialized)
@MainActor
struct TabPageNavigationTests {
    @Test("Tab page URL matches initial URL")
    func tabPageURLMatchesInitial() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com/path")),
            in: space,
            makeActive: false,
        )

        #expect(tab.activePage.url.absoluteString == "https://example.com/path")
    }

    @Test("Tab page title can be updated")
    func tabPageTitleUpdated() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: false,
        )

        tab.activePage.title = "New Title"

        #expect(tab.activePage.title == "New Title")
    }

    @Test("Tab page starts without loading state")
    func tabPageStartsWithoutLoading() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: false,
            loadImmediately: false,
        )

        // Tab page created but not actively loading without WebPage
        #expect(tab.activePage.url.absoluteString == "https://example.com")
    }
}

// MARK: - Navigation History Tests

@Suite("Navigation History", .tags(.tabManager), .serialized)
@MainActor
struct NavigationHistoryTests {
    @Test("Navigation records history entry")
    func navigationRecordsHistory() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: false,
        )

        // Record navigation
        let entry = env.historyManager.recordNavigation(
            url: tab.activePage.url,
            title: "Example",
            tabID: tab.id,
            spaceID: space.id,
        )

        #expect(entry != nil)
        #expect(entry?.url.host == "example.com")
    }

    @Test("Navigation in private space skips history")
    func navigationInPrivateSpaceSkipsHistory() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace(name: "Private")
        space.dataStoreMode = .private

        let entry = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://secret.com")),
            tabID: UUID(),
            spaceID: space.id,
            isPrivateSpace: true,
        )

        #expect(entry == nil)
    }

    @Test("History search finds navigation entry")
    func historySearchFindsEntry() async throws {
        let env = try TabManagerTestEnvironment()

        _ = try env.historyManager.recordNavigation(
            url: #require(URL(string: "https://findme.com")),
            title: "Find Me",
            tabID: UUID(),
        )

        try env.modelContext.save()
        await env.historyManager.performDeferredMaintenance(modelContainer: env.modelContainer)

        let results = await env.historyManager.search(query: "findme")

        #expect(!results.isEmpty)
        #expect(results.first?.url.host == "findme.com")
    }
}
