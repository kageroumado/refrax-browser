import Testing
@testable import Refrax

@Suite
@MainActor
struct MenuComposerTests {
    private func action(
        _ id: String,
        _ group: MenuGroupID,
        primary: Bool = false,
        enabled: Bool = true,
        destructive: Bool = false,
        children: [MenuAction] = [],
    ) -> MenuAction {
        MenuAction(id, id, group: group, isPrimary: primary, isEnabled: enabled, isDestructive: destructive, children: children)
    }

    private func topLevel(_ tree: MenuTree) -> [String] {
        tree.outline.filter { !$0.hasPrefix(" ") }
    }

    private func group(_ n: Int) -> MenuGroupID {
        MenuGroupID(id: "g\(n)", title: "G\(n)", symbol: "circle", rank: 200 + n)
    }

    @Test
    func `three actions stay inline and four fold behind the primary`() {
        let inline = MenuComposer.compose([action("a1", .open), action("a2", .open), action("a3", .open)])
        #expect(inline.outline == ["a1", "a2", "a3"])
        #expect(inline.rowCount == 3)

        let folded = MenuComposer.compose([
            action("a1", .open), action("a2", .open, primary: true), action("a3", .open), action("a4", .open), action("b1", .copy),
        ])
        #expect(folded.outline == ["a2", "Open ▸ (3)", "  a1", "  a3", "  a4", "——", "b1"])
        #expect(folded.rowCount == 3)
        #expect(folded.ids == ["a2", "group.open", "b1"])
    }

    @Test
    func `a folded group without a primary is one submenu row`() {
        let tree = MenuComposer.compose((1...4).map { action("a\($0)", .open) })
        #expect(tree.outline == ["Open ▸ (4)", "  a1", "  a2", "  a3", "  a4"])
        #expect(tree.rowCount == 1)
    }

    @Test
    func `the first primary wins and destructive actions sink to the end of their group`() {
        let tree = MenuComposer.compose([
            action("a1", .open, primary: true, destructive: true), action("a2", .open, primary: true), action("a3", .open), action("a4", .open),
        ])
        #expect(tree.outline == ["a1", "Open ▸ (3)", "  a2", "  a3", "  a4"])

        let inline = MenuComposer.compose([action("x", .close, destructive: true), action("y", .close), action("z", .close)])
        #expect(inline.outline == ["y", "z", "x"])
    }

    @Test
    func `disabled actions keep their row`() {
        let tree = MenuComposer.compose([action("a1", .open, enabled: false), action("a2", .open)])
        #expect(tree.outline == ["a1", "a2"])
    }

    @Test
    func `groups come out by rank, or in the order the site passes`() {
        let actions = [action("x1", .close), action("c1", .copy), action("t1", .tab), action("t2", .tab)]
        #expect(MenuComposer.compose(actions).outline == ["t1", "t2", "——", "c1", "x1"])
        #expect(MenuComposer.compose(actions, groupOrder: [.copy, .tab]).outline == ["c1", "——", "t1", "t2", "——", "x1"])
    }

    @Test
    func `consecutive singleton groups share a section`() {
        let tree = MenuComposer.compose([
            action("t1", .tab), action("t2", .tab), action("o1", .open), action("g1", .go), action("m1", .move), action("m2", .move),
        ])
        #expect(tree.outline == ["t1", "t2", "——", "o1", "g1", "——", "m1", "m2"])
        #expect(tree.sections.count == 3)
    }

    @Test
    func `children make a submenu that counts as one row, sectioned by consecutive group`() {
        let move = action("move.group", .move, children: [action("g1", .move), action("g2", .move), action("s1", .sort)])
        let tree = MenuComposer.compose([move, action("m2", .move)])
        #expect(tree.outline == ["move.group ▸ (3)", "  g1", "  g2", "  ——", "  s1", "m2"])
        #expect(tree.rowCount == 2)
    }

    @Test
    func `under height pressure the largest inline group folds first`() {
        var actions: [MenuAction] = []
        for group in [MenuGroupID.tab, .go, .reload, .move, .copy, .share, .read] {
            actions += ["1", "2"].map { action("\(group.id)\($0)", group) }
        }
        actions += ["1", "2", "3"].map { action("open\($0)", .open) }
        #expect(actions.count == 17)
        let tree = MenuComposer.compose(actions)
        #expect(tree.rowCount == 15)
        #expect(topLevel(tree).contains("Open ▸ (3)"))
        #expect(topLevel(tree).contains("tab1"))
    }

    @Test
    func `a fold tie goes to the group closest to the bottom`() {
        var actions: [MenuAction] = []
        for group in [MenuGroupID.tab, .open, .go, .reload, .move, .copy] {
            actions += ["1", "2", "3"].map { action("\(group.id)\($0)", group) }
        }
        let tree = MenuComposer.compose(actions)
        #expect(tree.rowCount == 16)
        #expect(Array(topLevel(tree).suffix(1)) == ["Copy ▸ (3)"])
        #expect(Array(topLevel(tree).prefix(3)) == ["tab1", "tab2", "tab3"])
    }

    @Test
    func `a group nobody can click folds before any other`() {
        var actions = (1...11).map { action("s\($0)", group($0)) }
        actions += ["1", "2", "3"].map { action("open\($0)", .open, enabled: false) }
        actions += ["1", "2", "3"].map { action("copy\($0)", .copy) }
        let tree = MenuComposer.compose(actions)
        #expect(tree.rowCount == 15)
        #expect(topLevel(tree).contains("Open ▸ (3)"))
        #expect(topLevel(tree).contains("copy1"))
    }

    @Test
    func `when every group is folded, primaries are demoted from the bottom up and close last`() {
        var actions: [MenuAction] = []
        for group in [MenuGroupID.tab, .open, .go, .reload, .move, .copy, .share, .read, .close] {
            actions += (1...4).map { action("\(group.id)\($0)", group, primary: $0 == 1) }
        }
        let tree = MenuComposer.compose(actions)
        #expect(tree.rowCount == 16)
        #expect(topLevel(tree) == [
            "tab1", "Tab ▸ (3)", "——", "open1", "Open ▸ (3)", "——", "go1", "Go ▸ (3)", "——", "reload1", "Reload ▸ (3)", "——",
            "move1", "Move ▸ (3)", "——", "copy1", "Copy ▸ (3)", "——", "Share ▸ (4)", "Read ▸ (4)", "——", "close1", "Close ▸ (3)",
        ])
    }

    @Test
    func `close gives up its primary only when nothing else can`() {
        var actions = (1...15).map { action("s\($0)", group($0)) }
        actions += (1...4).map { action("close\($0)", .close, primary: $0 == 1) }
        let tree = MenuComposer.compose(actions)
        #expect(tree.rowCount == 16)
        #expect(Array(topLevel(tree).suffix(3)) == ["s15", "——", "Close ▸ (4)"])
    }

    @Test
    func `the web page worst case is sixteen rows with every group one line`() {
        let page = MenuGroupID(id: "page", title: "Page", symbol: "doc", rank: 105)
        var actions = [
            action("Look at Link", .open, primary: true), action("Open Link in New Tab", .open), action("Open Link", .open),
            action("Open Link in New Window", .open), action("Open Image in New Window", .open),
            action("Copy Link", .copy, primary: true), action("Copy Image Address", .copy), action("Copy Image", .copy), action("Copy Subject", .copy),
            action("Download Image", .save, primary: true), action("Save Image to Photos", .save),
            action("Save Image to Album", .save, children: [action("Trips", .save), action("Recipes", .save)]), action("Download Linked File", .save),
            action("Download Video", .video, primary: true), action("Download Video Only", .video), action("Download Audio Only", .video),
            action("Save to Photos", .video),
        ]
        let phone = MenuGroupID.detected("+33 6 12 34 56 78")
        actions += ["Call", "FaceTime Audio", "Send Message", "Copy Phone Number"].map { action($0, phone) }
        let date = MenuGroupID.detected("October 14")
        actions += ["Create Calendar Event", "Show in Calendar", "Copy Date"].map { action($0, date) }
        actions += [
            action("Look Up", .read, primary: true), action("Translate", .read), action("Search with Google", .read), action("Speed Read Selection", .read),
            action("Remind Me About This Page…", page), action("Inspect Element", .develop),
        ]
        let tree = MenuComposer.compose(actions)
        #expect(tree.rowCount == 16)
        #expect(topLevel(tree) == [
            "Look at Link", "Open ▸ (4)", "——", "Copy Link", "Copy ▸ (3)", "——", "Download Image", "Save ▸ (3)", "——",
            "Download Video", "Video ▸ (3)", "——", "+33 6 12 34 56 78 ▸ (4)", "——", "Create Calendar Event", "Show in Calendar", "Copy Date", "——",
            "Look Up", "Read ▸ (3)", "——", "Remind Me About This Page…", "Inspect Element",
        ])

        let email = MenuGroupID.detected("ely@example.com")
        let withEmail = MenuComposer.compose(actions + [action("Send Email", email), action("Copy Email", email)])
        #expect(withEmail.rowCount == 16)
        #expect(topLevel(withEmail).contains("October 14 ▸ (3)"))
        #expect(topLevel(withEmail).contains("Send Email"))
    }

    @Test
    func `the sidebar tab row is fifteen rows`() {
        let groups = [action("Work", .move), action("Reading", .move)]
        let spaces = [action("Home", .move), action("Research", .move)]
        let sort = TabSortCriterion.Category.allCases.flatMap { category in
            category.criteria.map { action($0.displayName, .sort(category.displayName)) }
        }
        let actions = [
            action("Rename", .tab, primary: true), action("Get Info", .tab), action("Preview", .tab), action("Pin", .tab),
            action("Move to Favorites", .tab), action("Mark as Unread", .tab),
            action("Go to Home", .go), action("Set Current Page as Home", .go),
            action("Reload", .reload), action("Duplicate", .reload),
            action("Remove from Group", .move), action("Move to Group", .move, primary: true, children: groups), action("Add to New Group…", .move),
            action("Move to Space", .move, children: spaces), action("Move to Reference Pane", .move),
            action("Copy URL", .copy), action("Copy URL as Markdown", .copy),
            action("Share…", .share),
            action("Sort Tabs", .sort, children: sort),
            action("Open Reflected Window", .window),
            action("Archive Tab", .close, primary: true), action("Delete Immediately", .close, destructive: true),
            action("Archive Other", .close), action("Archive Above", .close), action("Archive Below", .close),
            action("Delete Other", .close, destructive: true), action("Delete Above", .close, destructive: true), action("Delete Below", .close, destructive: true),
        ]
        let tree = MenuComposer.compose(actions)
        #expect(tree.rowCount == 15)
        #expect(topLevel(tree) == [
            "Rename", "Tab ▸ (5)", "——", "Go to Home", "Set Current Page as Home", "——", "Reload", "Duplicate", "——",
            "Move to Group ▸ (2)", "Move ▸ (4)", "——", "Copy URL", "Copy URL as Markdown", "——", "Share…", "Sort Tabs ▸ (8)", "Open Reflected Window", "——",
            "Archive Tab", "Close ▸ (7)",
        ])
        let close = tree.outline.drop { $0 != "Close ▸ (7)" }.dropFirst().prefix(7)
        #expect(Array(close) == [
            "  Archive Other", "  Archive Above", "  Archive Below", "  Delete Immediately", "  Delete Other", "  Delete Above", "  Delete Below",
        ])
        let sortRows = tree.outline.drop { $0 != "Sort Tabs ▸ (8)" }.dropFirst().prefix(11)
        #expect(sortRows.filter { $0 == "  ——" }.count == 3)
    }
}
