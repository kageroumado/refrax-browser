import Foundation
import Testing
@testable import Refrax

struct FavoriteMigrationTests {
    private let current = URL(string: "https://example.com/inbox")!
    private let pinHome = URL(string: "https://example.com/")!

    private func candidate(
        status: TabStatus,
        isInSpace: Bool = true,
        isInGroup: Bool = false,
        spaceIsShared: Bool = true,
        showsInEverySpace: Bool = false,
        originURL: URL? = nil,
    ) -> FavoriteMigration.Candidate {
        FavoriteMigration.Candidate(
            status: status,
            isInSpace: isInSpace,
            isInGroup: isInGroup,
            spaceIsShared: spaceIsShared,
            showsInEverySpace: showsInEverySpace,
            originURL: originURL,
            currentURL: current,
        )
    }

    // MARK: - Stored status

    @Test(arguments: ["liveFavorite", "pinned", "favorite"])
    func `stored favorites and pins read as favorites`(stored: String) {
        #expect(TabStatus(rawValue: stored) == .favorite)
    }

    @Test
    func `regular reads as regular and unknown values are rejected`() {
        #expect(TabStatus(rawValue: "regular") == .regular)
        #expect(TabStatus(rawValue: "archived") == nil)
    }

    @Test
    func `statuses are written under their own names`() throws {
        #expect(TabStatus.favorite.rawValue == "favorite")
        let data = try JSONEncoder().encode([TabStatus.regular, .favorite])
        #expect(String(data: data, encoding: .utf8) == #"["regular","favorite"]"#)
        #expect(try JSONDecoder().decode([TabStatus].self, from: Data(#"["pinned","liveFavorite"]"#.utf8)) == [.favorite, .favorite])
    }

    // MARK: - Mapping

    @Test
    func `a pin in a shared space becomes a favorite at its pin address`() {
        let outcome = FavoriteMigration.outcome(for: candidate(status: .favorite, originURL: pinHome))
        #expect(outcome == .favorite(home: pinHome))
    }

    @Test
    func `a pin without a pin address becomes a favorite at its current address`() {
        #expect(FavoriteMigration.outcome(for: candidate(status: .favorite)) == .favorite(home: current))
    }

    @Test
    func `a pinned group's tab stays in its group as a regular tab`() {
        let outcome = FavoriteMigration.outcome(for: candidate(status: .favorite, isInGroup: true, originURL: pinHome))
        #expect(outcome == .regular)
    }

    @Test
    func `a pin in a private or locked space stays there as a regular tab`() {
        let outcome = FavoriteMigration.outcome(for: candidate(status: .favorite, spaceIsShared: false, originURL: pinHome))
        #expect(outcome == .regular)
    }

    @Test
    func `an existing favorite is left alone`() {
        #expect(FavoriteMigration.outcome(for: candidate(status: .favorite, isInSpace: false)) == .unchanged)
    }

    @Test
    func `a card shown in every space becomes a favorite at its current address`() {
        let outcome = FavoriteMigration.outcome(for: candidate(status: .regular, isInGroup: true, showsInEverySpace: true))
        #expect(outcome == .favorite(home: current))
    }

    @Test
    func `a card shown in every space from a private or locked space stays put`() {
        let outcome = FavoriteMigration.outcome(for: candidate(status: .regular, spaceIsShared: false, showsInEverySpace: true))
        #expect(outcome == .unchanged)
    }

    @Test
    func `a regular tab is left alone`() {
        #expect(FavoriteMigration.outcome(for: candidate(status: .regular)) == .unchanged)
    }

    // MARK: - Stored board data

    @Test
    func `a kept-visible card marked for every space is detected`() {
        let data = Data(#"{"x":0,"y":0,"width":0,"height":0,"floating":{"x":0.5,"y":0.5,"shape":"live","isPinned":true,"showsInEverySpace":true}}"#.utf8)
        #expect(FavoriteMigration.showsInEverySpace(data))
    }

    @Test
    func `a card hidden or shown in one space is not`() {
        let hidden = Data(#"{"x":0,"y":0,"width":0,"height":0,"floating":{"x":0,"y":0,"shape":"tab","isPinned":false,"showsInEverySpace":true}}"#.utf8)
        let oneSpace = Data(#"{"x":0,"y":0,"width":0,"height":0,"floating":{"x":0,"y":0,"shape":"live","isPinned":true}}"#.utf8)
        #expect(!FavoriteMigration.showsInEverySpace(hidden))
        #expect(!FavoriteMigration.showsInEverySpace(oneSpace))
        #expect(!FavoriteMigration.showsInEverySpace(nil))
        #expect(!FavoriteMigration.showsInEverySpace(Data("not json".utf8)))
    }

    @Test
    func `re-encoding a placement drops the every-space flag`() throws {
        let data = Data(#"{"x":0,"y":0,"width":0,"height":0,"hasDeskFrame":false,"floating":{"x":0.5,"y":0.5,"shape":"live","isPinned":true,"showsInEverySpace":true}}"#.utf8)
        let placement = try #require(BoardFrame.value(data)?.floating)
        let rewritten = BoardFrame.updating(frame: nil, isCompact: false, floating: placement)
        #expect(!FavoriteMigration.showsInEverySpace(rewritten))
        #expect(BoardFrame.value(rewritten)?.floating == placement)
    }
}
