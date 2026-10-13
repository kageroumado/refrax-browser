import Foundation
import Testing
@testable import Refrax

/// The sidebar tab row's menu, as a person reads it.
@Suite(.serialized)
@MainActor
struct SidebarTabMenuTests {
    @MainActor
    private struct Fixture {
        let env: TabManagerTestEnvironment
        let space: Space
        let window: WindowState
        let sharing = SharingCoordinator()
        let tabs: [Tab]

        init() throws {
            let env = try TabManagerTestEnvironment()
            let space = env.makeSpace()
            _ = env.makeSpace(name: "Research")
            self.env = env
            self.space = space
            self.window = env.makeActiveWindowState(with: space)
            _ = try env.groupManager.createGroup(in: space, name: "Work")
            self.tabs = (0 ..< 3).map { index in
                env.tabManager.createTab(url: URL(string: "https://example.com/\(index)")!, in: space, makeActive: false)
            }
        }

        func tree(for tab: Tab, isCompactMode: Bool = false, onRename: (() -> Void)? = {}, onGetInfo: (() -> Void)? = {}) -> MenuTree {
            SidebarContextMenus.Tab.tree(
                for: tab, isCompactMode: isCompactMode, onRename: onRename, onGetInfo: onGetInfo,
                tabManager: env.tabManager, groupManager: env.groupManager, pagePool: env.pagePool, bookmarksManager: env.bookmarksManager,
                sharingCoordinator: sharing, windowState: window, settings: env.settings,
            )
        }
    }

    private func topLevel(_ tree: MenuTree) -> [String] {
        tree.outline.filter { !$0.hasPrefix(" ") }
    }

    @Test
    func `a tab row folds its identity, organization, and close family`() throws {
        let fixture = try Fixture()
        fixture.env.settings.archiveEnabled = true
        let tree = fixture.tree(for: fixture.tabs[1])
        #expect(tree.rowCount == 12)
        #expect(topLevel(tree) == [
            "Rename Tab", "Tab ▸ (5)", "——", "Move to Group ▸ (1)", "Add to New Group…", "Move to Space ▸ (1)", "——", "Copy Address", "Copy as Markdown Link", "——",
            "Share…", "Sort Tabs ▸ (8)", "Open Reflected Window", "——", "Archive Tab", "Close ▸ (7)",
        ])
        let close = Array(tree.outline.drop { $0 != "Close ▸ (7)" }.dropFirst().prefix(7))
        #expect(close == [
            "  Archive Other Tabs", "  Archive All Tabs Above", "  Archive All Tabs Below", "  Delete Immediately",
            "  Delete Other Tabs Immediately", "  Delete All Tabs Above Immediately", "  Delete All Tabs Below Immediately",
        ])
        let identity = Array(tree.outline.drop { $0 != "Tab ▸ (5)" }.dropFirst().prefix(5))
        #expect(identity == ["  Get Info", "  Pin", "  Move to Favorites", "  Mark as Read", "  Duplicate Tab"])
    }

    @Test
    func `without archiving the close family stays inline and compact mode promotes Get Info`() throws {
        let fixture = try Fixture()
        let tree = fixture.tree(for: fixture.tabs[0], isCompactMode: true)
        #expect(Array(topLevel(tree).prefix(2)) == ["Get Info", "Tab ▸ (4)"])
        let closing = Array(topLevel(tree).suffix(3))
        #expect(Array(closing.prefix(2)) == ["Close Tab", "Close Other Tabs"])
        #expect(closing.last?.hasPrefix("Close All Tabs") == true)
        #expect(!tree.ids.contains("sidebar.rename"))
    }

    @Test
    func `a pinned tab gains its home and a grouped tab loses the pin`() throws {
        let fixture = try Fixture()
        let pinned = fixture.tabs[0]
        fixture.env.tabManager.togglePinTab(pinned)
        let pinnedTree = fixture.tree(for: pinned)
        #expect(topLevel(pinnedTree).contains("Set Current Page as Home"))
        #expect(pinnedTree.outline.contains("  Unpin"))

        let group = try #require(fixture.space.groups.first)
        let grouped = fixture.tabs[2]
        fixture.env.groupManager.moveTabToGroup(grouped, group: group)
        let groupedTree = fixture.tree(for: grouped)
        #expect(!groupedTree.outline.contains("  Pin"))
        #expect(topLevel(groupedTree).contains("Remove from Group"))
        #expect(!groupedTree.ids.contains("sidebar.moveToGroup"))
    }
}
