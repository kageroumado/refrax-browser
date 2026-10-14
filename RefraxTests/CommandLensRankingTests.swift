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
private func command(_ title: String) -> CommandLensSuggestion {
    CommandLensSuggestion(
        type: .appAction(.newSpace),
        text: title,
        description: "",
        iconName: "plus",
        groupHeader: "Actions",
        isRemovable: false,
        keywordAction: nil,
        url: nil,
    )
}

// MARK: - Exact Command Matches

@Suite("Command Lens ranking", .tags(.commandLensManager))
@MainActor
struct CommandLensRankingTests {
    @Test(arguments: [
        ("move to work", "Move to Work"),
        ("new space", "New Space…"),
        ("New Space", "New Space…"),
        ("copy address", "Copy Address"),
        ("copy adress", "Copy Address"),
        ("copy addre", "Copy Address"),
        ("move  to   work", "Move to Work"),
    ])
    func `Typed text that names a command matches it`(query: String, title: String) {
        #expect(CommandLensRanking.isExactCommandMatch(query: query, title: title))
    }

    @Test(arguments: [
        ("copy", "Copy Address"),
        ("move", "Move to Work"),
        ("save", "Save Page As…"),
        ("mute", "Mute This Tab"),
        ("space", "New Space…"),
        ("", "New Space…"),
    ])
    func `A word from a command's title leaves it ranked by its provider`(query: String, title: String) {
        #expect(!CommandLensRanking.isExactCommandMatch(query: query, title: title))
    }

    @Test
    func `Exact commands are split out without their group header, the rest keep their order`() {
        let rows = [command("Send Feedback"), command("New Space…"), command("Dock Left")]

        let (exact, rest) = CommandLensRanking.partitionExactCommands(rows, query: "new space")

        let exactTitles = exact.map(\.text)
        let restTitles = rest.map(\.text)
        #expect(exactTitles == ["New Space…"])
        #expect(exact.first?.groupHeader == nil)
        #expect(restTitles == ["Send Feedback", "Dock Left"])
    }

    @Test
    func `Navigation rows are places to go, commands are not`() {
        #expect(CommandLensRanking.isNavigation(.url))
        #expect(CommandLensRanking.isNavigation(.search))
        #expect(CommandLensRanking.isNavigation(.openTab(tabID: UUID())))
        #expect(!CommandLensRanking.isNavigation(.appAction(.checkForUpdates)))
        #expect(!CommandLensRanking.isNavigation(.appAction(.moveCurrentTabToNewWindow)))
        #expect(!CommandLensRanking.isNavigation(.setting(key: "k", scope: .global)))
    }
}

// MARK: - Lens Order

@Suite("Command Lens order", .tags(.commandLensManager), .serialized)
@MainActor
struct CommandLensOrderTests {
    @Test
    func `An exact command leads above the web search`() async throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)
        let manager = makeManager(env, windowState: windowState)

        manager.onInputChanged("new space")
        try await settle(manager)

        let first = try #require(manager.suggestions.first)
        #expect(first.type == .appAction(.newSpace))
        let searchIndex = try #require(manager.suggestions.firstIndex { $0.type == .search })
        #expect(searchIndex > 0)
        #expect(manager.selection.index == 0)
    }

    @Test
    func `Copy Address leads when typed in full`() async throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)
        _ = try env.tabManager.createTab(url: #require(URL(string: "https://example.com")), in: space, makeActive: true)
        let manager = makeManager(env, windowState: windowState)

        manager.onInputChanged("copy address")
        try await settle(manager)

        let first = try #require(manager.suggestions.first)
        #expect(first.text == "Copy Address")
    }

    @Test
    func `A partial word keeps the web search first`() async throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)
        let manager = makeManager(env, windowState: windowState)

        manager.onInputChanged("space")
        try await settle(manager)

        let first = try #require(manager.suggestions.first)
        #expect(first.type == .search)
    }

    @Test(arguments: ["example.com", "https://www.w3.org/TR/", "localhost:3000", "192.168.1.1", "update.example.org"])
    func `An address lists only places to go`(address: String) async throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)
        _ = try env.tabManager.createTab(url: #require(URL(string: "https://example.com")), in: space, makeActive: true)
        let manager = makeManager(env, windowState: windowState)

        manager.onInputChanged(address)
        try await settle(manager)

        #expect(!manager.suggestions.isEmpty)
        #expect(manager.suggestions.allSatisfy { CommandLensRanking.isNavigation($0.type) })
    }
}
