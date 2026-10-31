import AppKit
import Foundation
import Testing
@testable import Refrax

/// The pages a split tab shows stay alive while shown, and its panes clip at their corners.
@MainActor
struct PanePageLifetimeTests {
    private struct Candidate: EvictionCandidate, Equatable {
        let pageID: UUID
        let score: Int
        let isProtected: Bool
    }

    /// Eviction once weighed pages by score alone, so a pane on screen with a low score was
    /// closed under memory pressure while its adapter still showed it: a blank white pane.
    @Test
    func `A page on screen is never evicted, whatever its score`() {
        let shown = Candidate(pageID: UUID(), score: 0, isProtected: false)
        let hidden = Candidate(pageID: UUID(), score: 500, isProtected: false)
        let order = WebPagePool.evictionOrder([shown, hidden], shown: [shown.pageID], limit: 2)
        #expect(order == [hidden])
    }

    @Test
    func `Protected pages stay and the rest go lowest score first, up to the limit`() {
        let low = Candidate(pageID: UUID(), score: 10, isProtected: false)
        let middle = Candidate(pageID: UUID(), score: 50, isProtected: false)
        let high = Candidate(pageID: UUID(), score: 90, isProtected: false)
        let protected = Candidate(pageID: UUID(), score: 1, isProtected: true)
        #expect(WebPagePool.evictionOrder([high, protected, middle, low], shown: [], limit: 2) == [low, middle])
        #expect(WebPagePool.evictionOrder([low], shown: [], limit: 0).isEmpty)
    }

    /// The panes' rounded corners were a SwiftUI clip over WebKit's remote layers, which do
    /// not follow it, so the corners showed square under the rim.
    @Test
    func `A pane's corners are clipped on the adapter's own layer`() throws {
        let adapter = CocoaWebViewAdapter()
        adapter.setCornerRadius(8)
        let layer = try #require(adapter.layer)
        #expect(layer.cornerRadius == 8)
        #expect(layer.masksToBounds)
        #expect(layer.cornerCurve == .continuous)
        adapter.setCornerRadius(0)
        #expect(layer.masksToBounds == false)
    }

    @Test
    func `Activating a split tab makes every pane's page before the page view draws`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let tab = try env.tabManager.createTab(url: #require(URL(string: "https://one.example")), in: space, makeActive: false)
        try env.tabManager.addPageToTab(tab, url: #require(URL(string: "https://two.example")), at: .automatic)

        env.tabManager.setActiveTab(tab, in: window)

        for page in tab.pages {
            #expect(env.pagePool.existingPage(for: page) != nil)
        }
    }
}
