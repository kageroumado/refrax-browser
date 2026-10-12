import Testing
@testable import Refrax

struct PageActionsMenuTests {
    private let divider = "─"

    @Test
    func `a floating card's menu holds verbs and leaves the presentation to its header`() {
        var context = PageActionsMenuPlan.Context(host: .floatingCard)
        context.canGroup = true
        #expect(PageActionsMenuPlan.titles(for: context) == [
            "Copy Address", "Copy as Markdown Link", "Share…", "Look, then Return",
            divider, "Keep Visible",
            divider, "Select for Group",
            divider, "Duplicate Tab", "Close Tab",
        ])
    }

    @Test
    func `the current page's card keeps the presentation item after Keep Visible`() {
        var context = PageActionsMenuPlan.Context(host: .pageCard)
        context.isCurrentPage = true
        context.hasPage = true
        context.canGroup = true
        #expect(PageActionsMenuPlan.titles(for: context) == [
            "Copy Address", "Copy as Markdown Link", "Share…", "Find on Page…", "Reader",
            divider, "Keep Visible", "Show as Preview",
            divider, "Select for Group",
            divider, "Duplicate Tab", "Close Tab",
        ])
        context.isCompact = false
        #expect(PageActionsMenuPlan.titles(for: context).contains("Show as Compact Tab"))
    }

    @Test
    func `region and zoom items wait behind the flag`() {
        var context = PageActionsMenuPlan.Context(host: .floatingCard)
        context.hasRegion = true
        let hidden = PageActionsMenuPlan.titles(for: context)
        #expect(!hidden.contains("Adjust Region…"))
        #expect(!hidden.contains("Keep Part Visible… (Experimental)"))
        #expect(!hidden.contains("Preview Zoom"))

        context.regionsEnabled = true
        let shown = PageActionsMenuPlan.titles(for: context)
        #expect(shown.contains("Adjust Region…"))
        #expect(shown.contains("Preview Zoom"))
        #expect(shown.firstIndex(of: "Keep Visible").map { $0 + 1 } == shown.firstIndex(of: "Adjust Region…"))

        context.hasRegion = false
        let unselected = PageActionsMenuPlan.titles(for: context)
        #expect(unselected.contains("Keep Part Visible… (Experimental)"))
        #expect(!unselected.contains("Preview Zoom"))
    }

    @Test
    func `a kept preview offers Hide Preview and Show in Every Space, grouping follows the selection`() {
        var context = PageActionsMenuPlan.Context(host: .floatingCard)
        context.isPinned = true
        context.isCompact = false
        context.canShowInEverySpace = true
        context.canGroup = true
        context.isSelectedForGroup = true
        context.selectionCount = 2
        #expect(PageActionsMenuPlan.titles(for: context) == [
            "Copy Address", "Copy as Markdown Link", "Share…", "Look, then Return",
            divider, "Hide Preview",
            divider, "Deselect for Group", "Group Selected Tabs", "Show in Every Space",
            divider, "Duplicate Tab", "Close Tab",
        ])
        context.showsInEverySpace = true
        #expect(PageActionsMenuPlan.titles(for: context).contains("Show in This Space"))
    }

    @Test
    func `a page from another space or a live favorite has no grouping section`() {
        let context = PageActionsMenuPlan.Context(host: .recentList)
        #expect(PageActionsMenuPlan.titles(for: context) == [
            "Copy Address", "Copy as Markdown Link", "Share…", "Look, then Return",
            divider, "Keep Visible", "Show as Preview",
            divider, "Duplicate Tab", "Close Tab",
        ])
    }

    @Test
    func `the Look verb names the round trip wherever it is offered`() {
        #expect(PageVisitState.lookActionTitle == "Look, then Return")
        let context = PageActionsMenuPlan.Context(host: .floatingCard)
        #expect(PageActionsMenuPlan.title(of: .look, in: context) == PageVisitState.lookActionTitle)
        var current = context
        current.isCurrentPage = true
        #expect(!PageActionsMenuPlan.entries(for: current).contains(.look))
    }
}
