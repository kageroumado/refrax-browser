import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Refrax

// MARK: - Close Other Tabs Tests

@Suite("Close Other Tabs", .tags(.tabManager), .serialized)
@MainActor
struct TabPinningRegressionTests {
    @Test
    func `Close other tabs closes all except specified`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let otherTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://other.com")),
            in: space,
            makeActive: false,
        )

        let keepTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://keep.com")),
            in: space,
            makeActive: true,
        )

        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://close.com")),
            in: space,
            makeActive: true,
        )

        env.tabManager.setActiveTab(keepTab, in: windowState)

        env.tabManager.closeOtherTabsInSpace(except: keepTab)

        #expect(!space.tabs.contains { $0.id == otherTab.id })
        #expect(space.tabs.contains { $0.id == keepTab.id })
        #expect(space.tabs.count == 1)
    }

    @Test
    func `Close other tabs leaves pinned tabs as they are`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let pinned = try env.tabManager.createTab(url: #require(URL(string: "https://pinned.com")), in: space, makeActive: false)
        let keep = try env.tabManager.createTab(url: #require(URL(string: "https://keep.com")), in: space, makeActive: false)
        _ = try env.tabManager.createTab(url: #require(URL(string: "https://close.com")), in: space, makeActive: false)
        env.tabManager.pin(pinned)

        env.tabManager.closeOtherTabsInSpace(except: keep)

        #expect(Set(space.mainTabs.map(\.id)) == [pinned.id, keep.id])
        #expect(pinned.isPinned)
    }
}
