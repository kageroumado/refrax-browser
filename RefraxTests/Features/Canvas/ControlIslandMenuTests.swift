import Testing
@testable import Refrax

struct ControlIslandMenuTests {
    @Test
    func `More holds browser destinations, then Settings, then Customize`() {
        #expect(ControlIslandMoreItem.sections.map { $0.map(\.title) } == [
            ["Favorites…", "History", "Downloads", "Bookmarks"],
            ["Settings…"],
            ["Customize Controls…"],
        ])
        #expect(ControlIslandMoreItem.sections.flatMap { $0 } == ControlIslandMoreItem.allCases)
    }

    @Test
    func `the rail's own items sit in its context menu`() {
        #expect(ControlIslandRailMenuItem.allCases.map(\.title) == ["Customize Controls…", "Reset Control Position", "Option-drag moves"])
        #expect(ControlIslandDragTarget.allCases.map(\.title) == ["Controls", "Window"])
    }
}
