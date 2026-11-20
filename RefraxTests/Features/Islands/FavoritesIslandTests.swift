import AppKit
import Foundation
import Testing
@testable import Refrax

/// The favorites are an island: the favorites that have a tab as its rows, the same in every
/// space, icons only and kept on screen until it is told otherwise.
@Suite("Favorites island", .serialized)
@MainActor
struct FavoritesIslandTests {
    /// Favorites `tab` and rebuilds the islands.
    private func favorite(_ tab: Refrax.Tab, in fixture: IslandFixture) throws {
        try #require(fixture.env.tabManager.makeFavorite(tab, in: fixture.window) != nil)
        fixture.islands.refresh()
    }

    private func favorites(_ fixture: IslandFixture) throws -> Island {
        try #require(fixture.islands.island(Island.favoritesID))
    }

    @Test
    func `A favorited tab leaves its island for the Favorites island`() throws {
        let fixture = try IslandFixture()
        let mail = fixture.tab("Mail")
        let news = fixture.tab("News")

        try favorite(mail, in: fixture)

        let island = try favorites(fixture)
        #expect(island.isFavorites)
        #expect(island.title == "Favorites")
        #expect(island.tabIDs == [mail.id])
        #expect(fixture.islands.island(holding: news.id)?.isDefault == true)
        #expect(fixture.islands.islands.count(where: { $0.allTabIDs.contains(mail.id) }) == 1)
    }

    @Test
    func `It shows icons only and stays on screen with the reveal key up`() throws {
        let fixture = try IslandFixture()
        try favorite(fixture.tab("Mail"), in: fixture)

        let island = try favorites(fixture)

        #expect(island.placement.iconsOnly)
        #expect(island.placement.isPinned)
        #expect(!fixture.canvas.floatingVisibility.isRevealed)
        #expect(fixture.islands.visibleIslands.map(\.id) == [Island.favoritesID])
    }

    @Test
    func `As an icon rail it has no header, and its options are on a favorite's menu`() throws {
        let fixture = try IslandFixture()
        let mail = fixture.tab("Mail")
        try favorite(mail, in: fixture)
        let rail = try favorites(fixture)

        #expect(!rail.hasHeader)
        #expect(fixture.islands.fullFrame(of: rail) == fixture.islands.frame(of: rail))
        let menu = try fixture.rowMenu(mail)
        #expect(menu.contains("Show Favorites with Titles"))
        #expect(menu.contains("Keep Favorites on Screen"))
        #expect(menu.contains("All Favorites"))

        fixture.islands.setIconsOnly(false, for: Island.favoritesID)
        let titled = try favorites(fixture)
        #expect(titled.hasHeader)
        #expect(fixture.islands.fullFrame(of: titled).height == fixture.islands.frame(of: titled).height + IslandGeometry.headerReserve)
    }

    @Test
    func `There is no Favorites island while no favorite has a tab`() throws {
        let fixture = try IslandFixture()
        _ = fixture.tab("Mail")

        #expect(fixture.islands.island(Island.favoritesID) == nil)
    }

    @Test
    func `Another space shows the same rows in the same place`() async throws {
        let fixture = try IslandFixture()
        let mail = fixture.tab("Mail")
        try favorite(mail, in: fixture)
        fixture.islands.togglePin(Island.favoritesID)
        let here = try favorites(fixture)

        let other = fixture.env.makeSpace(name: "Other")
        await fixture.env.spaceManager.switchToSpace(other, for: fixture.window)
        fixture.islands.refresh()

        let there = try favorites(fixture)
        #expect(there.tabIDs == [mail.id])
        #expect(there.placement == here.placement)
        #expect(!there.placement.isPinned)
    }

    @Test
    func `Its place is kept for the next window`() throws {
        let first = try IslandFixture()
        try favorite(first.tab("Mail"), in: first)
        first.islands.setIconsOnly(false, for: Island.favoritesID)

        let second = try IslandFixture(defaults: first.defaults)
        try favorite(second.tab("Chat"), in: second)

        #expect(try !favorites(second).placement.iconsOnly)
    }

    @Test
    func `A step down from a favorite reaches the next favorite`() throws {
        let fixture = try IslandFixture()
        let mail = fixture.tab("Mail")
        let chat = fixture.tab("Chat")
        try favorite(mail, in: fixture)
        try favorite(chat, in: fixture)

        fixture.env.tabManager.setActiveTab(mail, in: fixture.window)
        fixture.islands.refresh()

        #expect(fixture.islands.currentTab?.id == mail.id)
        #expect(fixture.islands.destination(toward: .down)?.id == chat.id)
    }

    @Test
    func `A row put on the Favorites island becomes a favorite at that place`() throws {
        let fixture = try IslandFixture()
        let mail = fixture.tab("Mail")
        let chat = fixture.tab("Chat")
        let docs = fixture.tab("Docs")
        try favorite(mail, in: fixture)
        try favorite(chat, in: fixture)

        fixture.edit { fixture.islands.moveTab(docs.id, to: 1, in: Island.favoritesID) }

        #expect(docs.isFavorite)
        #expect(try favorites(fixture).tabIDs == [mail.id, docs.id, chat.id])
        #expect(fixture.env.bookmarksManager.liveFavorites.compactMap(\.tab?.id) == [mail.id, docs.id, chat.id])
    }

    @Test
    func `A favorite dragged within the island takes its new place`() throws {
        let fixture = try IslandFixture()
        let mail = fixture.tab("Mail")
        let chat = fixture.tab("Chat")
        let docs = fixture.tab("Docs")
        for tab in [mail, chat, docs] {
            try favorite(tab, in: fixture)
        }

        fixture.edit { fixture.islands.moveTab(docs.id, to: 0, in: Island.favoritesID) }

        #expect(try favorites(fixture).tabIDs == [docs.id, mail.id, chat.id])
    }

    @Test
    func `A favorite put on another island leaves the favorites for this space`() throws {
        let fixture = try IslandFixture()
        let mail = fixture.tab("Mail")
        let news = fixture.tab("News")
        try favorite(mail, in: fixture)

        fixture.edit { fixture.islands.moveTab(mail.id, toEndOf: fixture.space.id) }

        #expect(!mail.isFavorite)
        #expect(mail.space?.id == fixture.space.id)
        #expect(fixture.islands.island(Island.favoritesID) == nil)
        #expect(fixture.islands.island(holding: mail.id)?.tabIDs.contains(news.id) == true)
    }

    @Test
    func `A favorite joins no tab as a pane, and no tab joins it`() throws {
        let fixture = try IslandFixture()
        let mail = fixture.tab("Mail")
        let news = fixture.tab("News")
        try favorite(mail, in: fixture)

        #expect(!fixture.islands.canJoin(mail.id, with: news.id))
        #expect(!fixture.islands.canJoin(news.id, with: mail.id))
    }

    @Test
    func `Its rows are chosen one at a time`() throws {
        let fixture = try IslandFixture()
        let mail = fixture.tab("Mail")
        let chat = fixture.tab("Chat")
        try favorite(mail, in: fixture)
        try favorite(chat, in: fixture)

        fixture.islands.select(mail.id, extending: false, toggling: true)
        fixture.islands.select(chat.id, extending: true, toggling: false)

        #expect(fixture.islands.selectedTabIDs.isEmpty)
    }

    @Test
    func `A favorite's row menu has the favorite's verbs, with the way home once it has left`() throws {
        let fixture = try IslandFixture()
        let mail = fixture.tab("Mail")
        try favorite(mail, in: fixture)

        let atHome = try fixture.rowMenu(mail)
        #expect(atHome.contains("Remove from Favorites"))
        #expect(!atHome.contains("Go to Home"))
        for absent in ["Open as Card", "Archive Tab", "Move to Island ▸", "Remove from Island", "New Island with This Tab"] {
            #expect(!atHome.contains { $0.hasPrefix(absent) }, "\(absent) is no verb of a favorite")
        }

        mail.activePage.url = try #require(URL(string: "https://elsewhere.test/inbox"))
        let away = try fixture.rowMenu(mail)
        #expect(away.contains("Go to Home"))
        #expect(away.contains("Set Current Page as Home"))
    }
}
