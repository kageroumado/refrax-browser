import Foundation
import Testing
@testable import Refrax

/// What each quick filter matches.
@MainActor
struct IslandFilterPredicateTests {
    @Test(arguments: [
        (IslandFilter.unread, IslandRowFacts(isUnread: true)),
        (.playingAudio, IslandRowFacts(isPlayingAudio: true)),
        (.microphone, IslandRowFacts(usesMicrophone: true)),
        (.camera, IslandRowFacts(usesCamera: true)),
    ])
    func `Each filter matches its own state and nothing else`(filter: IslandFilter, facts: IslandRowFacts) {
        #expect(filter.matches(facts))
        #expect(!filter.matches(IslandRowFacts()))
        for other in IslandFilter.allCases where other != filter {
            #expect(!other.matches(facts), "\(other) matched \(filter)'s state")
        }
    }

    @Test
    func `A muted microphone or a turned-off camera still counts as in use`() {
        var state = TabMediaState(pages: [])
        state.isMicrophoneMuted = true
        state.isCameraMuted = true
        let facts = IslandRowFacts(state: state, isUnread: false)
        #expect(IslandFilter.microphone.matches(facts))
        #expect(IslandFilter.camera.matches(facts))
        #expect(!IslandFilter.playingAudio.matches(facts))
    }

    @Test
    func `The current tab keeps its row when the filter would hide it`() {
        let current = UUID()
        let unread = UUID()
        let read = UUID()
        let shown = IslandFilter.unread.shown(
            [(current, IslandRowFacts()), (unread, IslandRowFacts(isUnread: true)), (read, IslandRowFacts())], current: current,
        )
        #expect(shown == [current, unread])
    }

    @Test
    func `With no current tab and no match, nothing is shown`() {
        #expect(IslandFilter.camera.shown([(UUID(), IslandRowFacts())], current: nil).isEmpty)
    }
}

/// Quick filters on the islands of a window.
@Suite("Island quick filters", .serialized)
@MainActor
struct IslandFilterTests {
    @Test
    func `Only unread rows stay, the current tab's among them`() throws {
        let fixture = try IslandFixture()
        let current = fixture.tab("Current")
        let unread = fixture.tab("Unread")
        let read = fixture.tab("Read")
        current.isUnread = false
        unread.isUnread = true
        read.isUnread = false
        fixture.window.setActiveTabID(current.id, for: fixture.space.id)
        fixture.islands.setFilter(.unread)
        let island = try #require(fixture.islands.island(fixture.space.id))
        #expect(Set(island.tabIDs) == [current.id, unread.id])
        #expect(fixture.islands.island(holding: read.id) == nil)
        #expect(fixture.islands.currentTab?.id == current.id)
        fixture.islands.setFilter(nil)
        #expect(fixture.islands.island(fixture.space.id)?.tabIDs.count == 3)
    }

    @Test
    func `An island with no matching row folds away, and a section with none goes too`() throws {
        let fixture = try IslandFixture()
        let current = fixture.tab("Current")
        current.isUnread = false
        fixture.window.setActiveTabID(current.id, for: fixture.space.id)
        let parent = try fixture.env.groupManager.createGroup(in: fixture.space, name: "Reading")
        let child = try fixture.env.groupManager.createGroup(in: fixture.space, name: "Later")
        let fresh = fixture.tab("Fresh", group: parent)
        fresh.isUnread = true
        let old = fixture.tab("Old", group: child)
        old.isUnread = false
        try fixture.env.groupManager.nestGroup(child, in: parent)
        let quiet = try fixture.env.groupManager.createGroup(in: fixture.space, name: "Quiet")
        fixture.tab("Seen", group: quiet).isUnread = false
        fixture.islands.setFilter(.unread)
        #expect(fixture.islands.island(quiet.id) == nil)
        let reading = try #require(fixture.islands.island(parent.id))
        #expect(reading.rows == [.tab(fresh.id)])
        #expect(fixture.islands.island(fixture.space.id)?.tabIDs == [current.id])
    }

    @Test
    func `A tab read while the filter is on keeps its row only while it is current`() throws {
        let fixture = try IslandFixture()
        let a = fixture.tab("A")
        let b = fixture.tab("B")
        a.isUnread = true
        b.isUnread = true
        fixture.islands.setFilter(.unread)
        a.isUnread = false
        fixture.window.setActiveTabID(a.id, for: fixture.space.id)
        fixture.islands.refresh()
        #expect(fixture.islands.island(holding: a.id) != nil)
        fixture.window.setActiveTabID(b.id, for: fixture.space.id)
        fixture.islands.refresh()
        #expect(fixture.islands.island(holding: a.id) == nil)
    }

    @Test
    func `Switching spaces turns the filter off`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("A")
        fixture.islands.setFilter(.playingAudio)
        let other = fixture.env.makeSpace(name: "Other")
        fixture.env.tabManager.createTab(url: .blank, in: other, makeActive: false, loadImmediately: false)
        fixture.env.tabManager.spaceManager.switchToSpaceSync(other, for: fixture.window)
        fixture.islands.refresh()
        #expect(fixture.islands.filter == nil)
    }

    @Test
    func `The filter's word shows with the islands, beside the first one`() throws {
        let fixture = try IslandFixture()
        let tab = fixture.tab("A")
        tab.isUnread = true
        let size = CGSize(width: 200, height: 28)
        #expect(fixture.islands.filterBadgeOrigin(size: size, gap: 10) == nil)
        fixture.islands.setFilter(.unread)
        #expect(fixture.islands.filterBadgeOrigin(size: size, gap: 10) == nil)
        fixture.canvas.toggleFloatingTabs()
        let island = try #require(fixture.islands.visibleIslands.first)
        let origin = try #require(fixture.islands.filterBadgeOrigin(size: size, gap: 10))
        #expect(origin.x == fixture.islands.fullFrame(of: island).maxX + 10)
        // The start hint gives way to it.
        #expect(fixture.islands.startHintIsland == nil)
    }

    @Test
    func `With nothing matching and the islands up, the word still shows where they would be`() throws {
        let fixture = try IslandFixture()
        fixture.tab("A").isUnread = false
        fixture.islands.setFilter(.camera)
        fixture.canvas.toggleFloatingTabs()
        #expect(fixture.islands.visibleIslands.isEmpty)
        #expect(fixture.islands.filterBadgeOrigin(size: CGSize(width: 200, height: 28), gap: 10) != nil)
    }
}
