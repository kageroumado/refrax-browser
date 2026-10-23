import AppKit
import Foundation
import Testing
@testable import Refrax

// MARK: - Helpers

@MainActor
private func makeManager(_ env: TabManagerTestEnvironment, windowState: WindowState) -> CommandLensManager {
    CommandLensManager(
        tabManager: env.tabManager,
        historyManager: env.historyManager,
        windowState: windowState,
        browserSettings: env.settings,
        siteSettingsManager: env.siteSettingsManager,
        downloadManager: env.downloadManager,
        extensionManager: env.extensionManager,
        customSearchEngineManager: env.customSearchEngineManager,
        localNetworkSource: EmptyLocalNetworkSource(),
    )
}

/// Waits until the lens has finished computing suggestions for its current input.
@MainActor
private func settle(_ manager: CommandLensManager) async throws {
    for _ in 0 ..< 150 {
        if !manager.isLoading, !manager.suggestions.isEmpty {
            return
        }
        try await Task.sleep(for: .milliseconds(20))
    }
}

@MainActor
private func actionTitles(_ query: String, env: TabManagerTestEnvironment, windowState: WindowState) async -> [String] {
    let provider = ActionsProvider(tabs: env.tabManager, windowState: windowState)
    let context = SuggestionContext(input: query, settings: env.settings, currentTabID: nil, selectedSearchEngine: nil)
    return await provider.suggestions(for: context).map(\.text)
}

// MARK: - Bare Domains

@Suite("Command Lens bare domains", .tags(.commandLensManager), .serialized)
@MainActor
struct CommandLensBareDomainTests {
    @Test(arguments: ["com", "org", "io", "uk", "fr", "dev"])
    func `Common top-level domains are known before the suffix list loads`(suffix: String) {
        #expect(PublicSuffixList.shared.isPublicSuffix(suffix))
    }

    @Test(arguments: ["news.ycombinator.com", "bbc.com", "example.co.uk"])
    func `A bare domain offers Go to website first and preselects it`(domain: String) async throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)
        let manager = makeManager(env, windowState: windowState)

        manager.onInputChanged(domain)
        try await settle(manager)

        let first = try #require(manager.suggestions.first)
        #expect(first.type == .url)
        #expect(first.description == "Go to website")
        #expect(first.url == URL(string: "https://\(domain)"))
        #expect(manager.selection.index == 0)
    }

    @Test
    func `Return on a bare domain opens the site`() async throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)
        let manager = makeManager(env, windowState: windowState)

        manager.onInputChanged("bbc.com")
        try await settle(manager)
        manager.commitSelection()

        #expect(space.tabs.contains { $0.activePage.url.host == "bbc.com" })
    }

    @Test
    func `Return before the suggestions catch up follows the typed domain`() async throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)
        let manager = makeManager(env, windowState: windowState)

        manager.onInputChanged("bbc")
        try await settle(manager)
        manager.onInputChanged("bbc.com")
        manager.commitSelection()

        #expect(space.tabs.contains { $0.activePage.url.host == "bbc.com" })
        // The query the edit started must finish before the environment goes away.
        try await settle(manager)
    }
}

// MARK: - Everyday Words

@Suite("Command Lens everyday words", .tags(.commandLensManager), .serialized)
@MainActor
struct CommandLensEverydayWordsTests {
    @Test(arguments: ["copy", "copy link", "copy url", "copy address"])
    func `Copy words find Copy Address`(query: String) async throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)
        _ = try env.tabManager.createTab(url: #require(URL(string: "https://example.com")), in: space, makeActive: true)

        let titles = await actionTitles(query, env: env, windowState: windowState)

        #expect(titles.first == "Copy Address")
    }

    @Test(arguments: ["accent", "color", "colour", "theme", "appearance"])
    func `Appearance words find Appearance Settings`(query: String) async throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let titles = await actionTitles(query, env: env, windowState: windowState)

        #expect(titles.first == "Appearance Settings")
    }

    @Test(arguments: ["tabs", "open tabs", "how many tabs"])
    func `Tab words find Show Open Tabs first`(query: String) async throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let titles = await actionTitles(query, env: env, windowState: windowState)

        #expect(titles.first == "Show Open Tabs")
    }

    @Test
    func `An unrelated word finds none of the everyday actions`() async throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)
        _ = try env.tabManager.createTab(url: #require(URL(string: "https://example.com")), in: space, makeActive: true)

        let titles = await actionTitles("xylophone", env: env, windowState: windowState)
        let everyday: Set = ["Copy Address", "Copy as Markdown Link", "Appearance Settings", "Show Open Tabs"]

        #expect(titles.allSatisfy { !everyday.contains($0) })
    }

    @Test
    func `Show Open Tabs lists the space's tabs under a count`() async throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)
        _ = try env.tabManager.createTab(url: #require(URL(string: "https://example.com")), in: space, makeActive: true)
        _ = try env.tabManager.createTab(url: #require(URL(string: "https://example.org")), in: space, makeActive: false)
        let manager = makeManager(env, windowState: windowState)

        manager.onInputChanged("how many tabs")
        try await settle(manager)
        let row = try #require(manager.suggestions.first { $0.text == "Show Open Tabs" })
        manager.choose(row)
        manager.commitSelection()

        #expect(manager.inputText.isEmpty)
        #expect(manager.suggestions.count == 2)
        #expect(manager.suggestions.allSatisfy { $0.groupHeader == "2 Open Tabs" })
    }
}

// MARK: - Move to Space

@Suite("Move to Space confirmation", .serialized)
@MainActor
struct MoveToSpaceConfirmationTests {
    @Test
    func `Moving a tab confirms with a toast whose Undo returns it`() throws {
        let env = try TabManagerTestEnvironment()
        let home = env.makeSpace(name: "Home")
        let work = env.makeSpace(name: "Work")
        let windowState = env.makeActiveWindowState(with: home)
        _ = try env.tabManager.createTab(url: #require(URL(string: "https://example.org")), in: home, makeActive: false)
        let tab = try env.tabManager.createTab(url: #require(URL(string: "https://example.com")), in: home, makeActive: true)

        env.tabManager.moveTabs([tab], to: work, confirmingIn: windowState)

        #expect(tab.space?.id == work.id)
        #expect(windowState.toastMessage == "Moved to Work")
        let undo = try #require(windowState.toastAction)
        #expect(undo.title == "Undo")

        undo.perform()

        #expect(tab.space?.id == home.id)
    }

    @Test
    func `Undo puts a moved tab back in the group it left`() throws {
        let env = try TabManagerTestEnvironment()
        let home = env.makeSpace(name: "Home")
        let work = env.makeSpace(name: "Work")
        let windowState = env.makeActiveWindowState(with: home)
        let tab = try env.tabManager.createTab(url: #require(URL(string: "https://example.com")), in: home, makeActive: true)
        let group = try env.groupManager.createGroup(in: home, name: "Reading")
        env.groupManager.moveTabToGroup(tab, group: group, in: home)

        env.tabManager.moveTabs([tab], to: work, confirmingIn: windowState)
        let undone = env.undoRedoManager.undoMoveToSpace(named: "Move to Work")

        #expect(undone)
        #expect(tab.space?.id == home.id)
        #expect(tab.groupID == group.id)
    }
}

// MARK: - Menus

@Suite("Tab Layout and Save menus", .serialized)
@MainActor
struct TabLayoutMenuTests {
    @Test
    func `The islands menu names the four steps and the new island`() throws {
        let env = try TabManagerTestEnvironment()
        let menuBar = MenuBarManager(windowManager: env.windowManager, undoRedoManager: UndoRedoManager())

        let item = menuBar.createTableMenuItem()
        let titles = item.submenu?.items.filter { !$0.isSeparatorItem }.map(\.title) ?? []

        #expect(item.title == "Islands")
        #expect(titles == ["Tab Left", "Tab Right", "Tab Above", "Tab Below", "New Island with This Tab"])
    }

    @Test
    func `Save Page As is on Command-S`() throws {
        let env = try TabManagerTestEnvironment()
        let menuBar = MenuBarManager(windowManager: env.windowManager, undoRedoManager: UndoRedoManager())

        let fileMenu = try #require(menuBar.createFileMenu().submenu)
        let save = try #require(fileMenu.items.first { $0.title == "Save Page As…" })

        #expect(save.keyEquivalent == "s")
        #expect(save.keyEquivalentModifierMask == [.command])
    }
}
