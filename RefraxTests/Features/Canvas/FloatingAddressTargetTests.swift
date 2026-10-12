import Foundation
import Testing
@testable import Refrax

@Suite(.serialized)
@MainActor
struct FloatingAddressTargetTests {
    @Test func `editing a preview address navigates the identified page and preserves the main activity`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let main = env.createActiveTab(url: try #require(URL(string: "about:blank#draft")), in: space, for: window)
        let preview = env.tabManager.createTab(url: try #require(URL(string: "about:blank#reference")), in: space, makeActive: false)
        let mainPage = try #require(env.pagePool.page(for: main.activePage))
        let previewPage = try #require(env.pagePool.page(for: preview.activePage))
        window.recordInteraction(with: preview.activePage.id)
        window.openAddressLens()
        let manager = CommandLensManager(
            tabManager: env.tabManager, historyManager: env.historyManager, windowState: window,
            browserSettings: env.settings, siteSettingsManager: env.siteSettingsManager,
            downloadManager: env.downloadManager, referencePaneManager: env.referencePaneManager,
            extensionManager: env.extensionManager, customSearchEngineManager: env.customSearchEngineManager,
            localNetworkSource: EmptyLocalNetworkSource()
        )
        let mainGeneration = mainPage.navigationGeneration
        let previewGeneration = previewPage.navigationGeneration
        manager.inputText = "about:blank#edited"
        manager.commitSelection()
        #expect(previewPage.navigationGeneration > previewGeneration)
        #expect(mainPage.navigationGeneration == mainGeneration)
        #expect(window.activeTabID == main.id)
        #expect(space.mainTabs.count == 2)
    }
}
