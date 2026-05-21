import Foundation
import SwiftData
import SwiftUI
import Testing
import WebKit

@testable import Refrax

// MARK: - TabManager+Navigation Tests

@Suite("TabManager Navigation", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerNavigationTests {
    @Test("Select next tab moves to next in list")
    func selectNextTab() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab1 = env.createActiveTab(
            url: URL(string: "https://one.com")!,
            in: space,
            for: windowState,
        )
        let tab2 = env.tabManager.createTab(
            url: URL(string: "https://two.com")!,
            in: space,
            makeActive: false,
        )
        let tab3 = env.tabManager.createTab(
            url: URL(string: "https://three.com")!,
            in: space,
            makeActive: false,
        )

        #expect(windowState.activeTabID == tab1.id)

        // Select next in the filtered list
        env.tabManager.selectNextTab(in: [tab1, tab2, tab3])

        #expect(windowState.activeTabID == tab2.id, "Should move to next tab")
    }

    @Test("Select next tab at end does nothing")
    func selectNextTabAtEnd() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab1 = env.tabManager.createTab(
            url: URL(string: "https://one.com")!,
            in: space,
            makeActive: false,
        )
        let tab2 = env.tabManager.createTab(
            url: URL(string: "https://two.com")!,
            in: space,
            makeActive: false,
        )
        let tab3 = env.createActiveTab(
            url: URL(string: "https://three.com")!,
            in: space,
            for: windowState,
        )

        #expect(windowState.activeTabID == tab3.id)

        env.tabManager.selectNextTab(in: [tab1, tab2, tab3])

        #expect(windowState.activeTabID == tab3.id, "Should stay on last tab")
    }

    @Test("Select previous tab moves to previous in list")
    func selectPreviousTab() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab1 = env.tabManager.createTab(
            url: URL(string: "https://one.com")!,
            in: space,
            makeActive: false,
        )
        let tab2 = env.createActiveTab(
            url: URL(string: "https://two.com")!,
            in: space,
            for: windowState,
        )
        let tab3 = env.tabManager.createTab(
            url: URL(string: "https://three.com")!,
            in: space,
            makeActive: false,
        )

        #expect(windowState.activeTabID == tab2.id)

        env.tabManager.selectPreviousTab(in: [tab1, tab2, tab3])

        #expect(windowState.activeTabID == tab1.id, "Should move to previous tab")
    }

    @Test("Select previous tab at start does nothing")
    func selectPreviousTabAtStart() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab1 = env.createActiveTab(
            url: URL(string: "https://one.com")!,
            in: space,
            for: windowState,
        )
        let tab2 = env.tabManager.createTab(
            url: URL(string: "https://two.com")!,
            in: space,
            makeActive: false,
        )

        #expect(windowState.activeTabID == tab1.id)

        env.tabManager.selectPreviousTab(in: [tab1, tab2])

        #expect(windowState.activeTabID == tab1.id, "Should stay on first tab")
    }

    @Test("Select next with no current selection activates first")
    func selectNextNoSelection() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab1 = env.tabManager.createTab(
            url: URL(string: "https://one.com")!,
            in: space,
            makeActive: false,
        )
        let tab2 = env.tabManager.createTab(
            url: URL(string: "https://two.com")!,
            in: space,
            makeActive: false,
        )

        // Create a different tab as active that's not in our filtered list
        _ = env.createActiveTab(
            url: URL(string: "https://other.com")!,
            in: space,
            for: windowState,
        )

        // When current active tab is not in the filtered list
        env.tabManager.selectNextTab(in: [tab1, tab2])

        #expect(windowState.activeTabID == tab1.id, "Should activate first tab when no current selection in list")
    }

    @Test("Select previous with no current selection activates first")
    func selectPreviousNoSelection() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab1 = env.tabManager.createTab(
            url: URL(string: "https://one.com")!,
            in: space,
            makeActive: false,
        )
        let tab2 = env.tabManager.createTab(
            url: URL(string: "https://two.com")!,
            in: space,
            makeActive: false,
        )

        // Create a different tab as active that's not in our filtered list
        _ = env.createActiveTab(
            url: URL(string: "https://other.com")!,
            in: space,
            for: windowState,
        )

        env.tabManager.selectPreviousTab(in: [tab1, tab2])

        #expect(windowState.activeTabID == tab1.id, "Should activate first tab when no current selection in list")
    }

    @Test("Select next with empty list does nothing")
    func selectNextEmptyList() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab = env.createActiveTab(
            url: URL(string: "https://active.com")!,
            in: space,
            for: windowState,
        )

        env.tabManager.selectNextTab(in: [])

        #expect(windowState.activeTabID == tab.id, "Should keep current active tab")
    }

    @Test("Select previous with empty list does nothing")
    func selectPreviousEmptyList() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab = env.createActiveTab(
            url: URL(string: "https://active.com")!,
            in: space,
            for: windowState,
        )

        env.tabManager.selectPreviousTab(in: [])

        #expect(windowState.activeTabID == tab.id, "Should keep current active tab")
    }
}
