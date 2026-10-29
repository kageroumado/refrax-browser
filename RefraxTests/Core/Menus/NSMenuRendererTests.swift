import AppKit
import Testing
@testable import Refrax

@Suite(.serialized)
@MainActor
struct NSMenuRendererTests {
    @Test
    func `rows become items, sections become separators, and the closure outlives the weak target`() throws {
        var ran = 0
        let tree = MenuComposer.compose([
            MenuAction("copy.address", "Copy Address", symbol: "link", key: .init("c"), group: .copy) { ran += 1 },
            MenuAction("copy.markdown", "Copy as Markdown Link", group: .copy, isEnabled: false),
            MenuAction("tab.pin", "Keep Visible", group: .tab, state: .on),
        ])
        let menu = NSMenuRenderer.menu(tree)
        #expect(!menu.autoenablesItems)
        #expect(menu.items.map(\.title) == ["Keep Visible", "", "Copy Address", "Copy as Markdown Link"])
        #expect(menu.items[1].isSeparatorItem)

        let pin = menu.items[0]
        #expect(pin.state == .on)
        #expect(pin.accessibilityIdentifier() == "menu-tab.pin")

        let copy = menu.items[2]
        #expect(copy.keyEquivalent == "c")
        #expect(copy.keyEquivalentModifierMask == .command)
        #expect(copy.image != nil)
        #expect(copy.isEnabled)
        #expect(copy.representedObject as AnyObject? === copy.target as AnyObject?)
        let target = try #require(copy.target as? MenuActionTarget)
        target.performAction(copy)
        #expect(ran == 1)

        #expect(!menu.items[3].isEnabled)
        #expect(menu.items[3].image == nil)
    }

    @Test
    func `a folded group is a submenu titled with the group`() throws {
        let tree = MenuComposer.compose((1 ... 4).map { MenuAction("open.\($0)", "Open \($0)", group: .open, isPrimary: $0 == 2) })
        let menu = NSMenuRenderer.menu(tree)
        #expect(menu.items.map(\.title) == ["Open 2", "Open"])
        let submenu = try #require(menu.items[1].submenu)
        #expect(menu.items[1].image != nil)
        #expect(menu.items[1].accessibilityIdentifier() == "menu-group.open")
        #expect(submenu.items.map(\.title) == ["Open 1", "Open 3", "Open 4"])
        #expect(!submenu.autoenablesItems)
    }

    @Test
    func `children render as a nested submenu with its own separators`() throws {
        let sort = MenuAction("sort", "Sort Tabs", symbol: "arrow.up.arrow.down", group: .sort, children: [
            MenuAction("sort.name", "Name", group: .sort("name")),
            MenuAction("sort.domain", "Domain", group: .sort("domain")),
        ])
        let menu = NSMenuRenderer.menu(MenuComposer.compose([sort]))
        let submenu = try #require(menu.items[0].submenu)
        #expect(submenu.items.map(\.title) == ["Name", "", "Domain"])
        #expect(submenu.items[1].isSeparatorItem)
    }
}
