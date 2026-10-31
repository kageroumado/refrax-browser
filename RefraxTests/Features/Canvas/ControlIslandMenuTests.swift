import Testing
@testable import Refrax

struct ControlIslandMenuTests {
    @Test
    func `the rail's own menu holds Favorites, then its setup`() {
        #expect(ControlIslandRailMenuItem.allCases.map(\.title) == ["Favorites…", "Customize…", "Reset Control Position"])
        #expect(ControlIslandRailMenuItem.allCases.map(\.symbol) == ["star", "slider.horizontal.3", "arrow.counterclockwise"])
    }

    @Test
    func `the optional destinations keep their rail controls`() {
        let additional = ControlIslandItem.allCases.filter { $0.section == .additional }
        #expect(additional == [.reload, .copyLink, .favorites, .history, .bookmarks, .settings, .nowPlaying, .updates, .extensions])
        #expect(Set(ControlIslandItem.defaultOrder) == Set(ControlIslandItem.allCases))
    }
}
