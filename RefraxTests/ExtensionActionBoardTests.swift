import Foundation
import Testing
@testable import Refrax

/// What the rail and the page menu show for each extension's action, per tab.
@Suite("Extension action board")
struct ExtensionActionBoardTests {
    private let tab = UUID()
    private let otherTab = UUID()

    private func appearance(_ badge: String, unread: Bool = false, label: String = "Action") -> ExtensionActionAppearance {
        ExtensionActionAppearance(label: label, badgeText: badge, isEnabled: true, hasUnreadBadgeText: unread)
    }

    @Test
    func `A tab without its own action shows the default`() {
        var board = ExtensionActionBoard()
        board.record(appearance("1"), for: .init(contextID: "a", tabPageID: nil))
        board.record(appearance("7"), for: .init(contextID: "a", tabPageID: tab))

        #expect(board.appearance(contextID: "a", tabPageID: tab)?.badgeText == "7")
        #expect(board.appearance(contextID: "a", tabPageID: otherTab)?.badgeText == "1")
        #expect(board.appearance(contextID: "a", tabPageID: nil)?.badgeText == "1")
        #expect(board.appearance(contextID: "b", tabPageID: tab) == nil)
    }

    @Test
    func `An unread badge counts until it is marked read, and an empty badge never does`() {
        var board = ExtensionActionBoard()
        board.record(appearance("", unread: true), for: .init(contextID: "a", tabPageID: nil))
        board.record(appearance("3", unread: true), for: .init(contextID: "b", tabPageID: tab))
        #expect(!board.hasUnreadBadge(among: ["a"], tabPageID: tab))
        #expect(board.hasUnreadBadge(among: ["a", "b"], tabPageID: tab))
        #expect(!board.hasUnreadBadge(among: ["a", "b"], tabPageID: otherTab))

        board.markRead(["b"], tabPageID: tab)

        #expect(!board.hasUnreadBadge(among: ["a", "b"], tabPageID: tab))
    }

    @Test
    func `Marking a tab without its own action marks the default`() {
        var board = ExtensionActionBoard()
        board.record(appearance("2", unread: true), for: .init(contextID: "a", tabPageID: nil))
        board.markRead(["a"], tabPageID: tab)
        #expect(board.appearance(contextID: "a", tabPageID: nil)?.hasUnreadBadgeText == false)
    }

    @Test
    func `Closing a tab or unloading an extension forgets its actions`() {
        var board = ExtensionActionBoard()
        board.record(appearance("1"), for: .init(contextID: "a", tabPageID: nil))
        board.record(appearance("7"), for: .init(contextID: "a", tabPageID: tab))
        board.record(appearance("9"), for: .init(contextID: "b", tabPageID: tab))

        board.removeTabPage(tab)
        #expect(board.appearance(contextID: "a", tabPageID: tab)?.badgeText == "1")
        #expect(board.tabPageIDs(withActionsFor: "a").isEmpty)

        board.removeContext("a")
        #expect(board.appearance(contextID: "a", tabPageID: nil) == nil)
    }
}

/// Context identifiers stay the same across launches and differ between controllers.
@Suite("Extension context identifier")
struct ExtensionContextIdentifierTests {
    @Test
    func `The default controller's context reuses the installation's UUID in lowercase`() {
        let installed = "6F9619FF-8B86-D011-B42D-00CF4FC964FF"
        #expect(ExtensionContextIdentifier.identifier(installedID: installed, spaceID: nil) == installed.lowercased())
    }

    @Test
    func `A space's context gets an identifier of its own that never changes`() {
        let installed = "6F9619FF-8B86-D011-B42D-00CF4FC964FF"
        let space = UUID()
        let first = ExtensionContextIdentifier.identifier(installedID: installed, spaceID: space)
        #expect(first == ExtensionContextIdentifier.identifier(installedID: installed, spaceID: space))
        #expect(first != ExtensionContextIdentifier.identifier(installedID: installed, spaceID: UUID()))
        #expect(first != installed.lowercased())
        #expect(UUID(uuidString: first) != nil)
    }

    @Test
    func `A folder name that is no UUID still yields a valid host`() {
        let identifier = ExtensionContextIdentifier.identifier(installedID: "My Extension (dev)", spaceID: nil)
        #expect(UUID(uuidString: identifier) != nil)
        #expect(ExtensionContextIdentifier.baseURL(for: identifier).host() == identifier)
    }
}
