import Foundation
import Testing
@testable import Refrax

// MARK: - Helper: Create Tab for Handler Testing (No SwiftData)

@MainActor
private func makePinnedTab(origin: URL) -> Tab {
    Tab(space: nil, url: origin, title: origin.host ?? "Favorite", status: .favorite, linkedBookmark: Bookmark(url: origin))
}

// MARK: - PinnedTabContainmentHandler Tests

@Suite("PinnedTabContainmentHandler", .tags(.navigation))
@MainActor
struct PinnedTabContainmentHandlerTests {
    // MARK: - Regular Tabs (No Containment)

    @Test
    func `Regular tab allows all navigations`() async throws {
        let tab = try Tab(space: nil, url: #require(URL(string: "https://example.com")), title: "Example", status: .regular)
        let handler = PinnedTabContainmentHandler(tab: tab)
        let action = try MockNavigationAction.mainFrame(url: #require(URL(string: "https://different-domain.com")))

        let policy = await handler.evaluate(action)
        #expect(policy == .next, "Regular tabs should not be contained")
    }

    // MARK: - Pinned Tabs: Main Frame

    @Test
    func `Pinned tab allows same-domain link click`() async throws {
        let tab = try makePinnedTab(origin: #require(URL(string: "https://github.com")))
        let handler = PinnedTabContainmentHandler(tab: tab)
        let action = try MockNavigationAction.linkClick(url: #require(URL(string: "https://github.com/anthropics/claude-code")))

        let policy = await handler.evaluate(action)
        #expect(policy == .next)
    }

    @Test
    func `Pinned tab shows preview for cross-domain link click`() async throws {
        let tab = try makePinnedTab(origin: #require(URL(string: "https://github.com")))
        let handler = PinnedTabContainmentHandler(tab: tab)
        let crossURL = try #require(URL(string: "https://stackoverflow.com/questions/123"))
        let action = MockNavigationAction.linkClick(url: crossURL)

        let policy = await handler.evaluate(action)
        #expect(policy == .showPreview(crossURL))
    }

    // MARK: - Redirects & Programmatic Loads (Never Contained)

    @Test
    func `Cross-domain redirect of the tab's own load passes through`() async throws {
        // Regression: a cold pinned tab loads its home URL, which 302s to a
        // login host on another registrable domain. Containing that redirect
        // cancels the tab's only provisional navigation and leaves it blank.
        let tab = try makePinnedTab(origin: #require(URL(string: "https://netatmo.atlassian.net/jira/dashboards")))
        let handler = PinnedTabContainmentHandler(tab: tab)
        let loginURL = try #require(URL(string: "https://example-sso.example.com/login?continue=https%3A%2F%2Fnetatmo.atlassian.net"))
        let action = MockNavigationAction.scriptInitiated(url: loginURL)

        let policy = await handler.evaluate(action)
        #expect(policy == .next, "Redirects of the tab's own load must never be contained")
    }

    @Test
    func `Cross-domain back/forward navigation passes through`() async throws {
        let tab = try makePinnedTab(origin: #require(URL(string: "https://github.com")))
        let handler = PinnedTabContainmentHandler(tab: tab)
        let action = try MockNavigationAction.backForward(url: #require(URL(string: "https://stackoverflow.com/questions/123")))

        let policy = await handler.evaluate(action)
        #expect(policy == .next)
    }

    @Test
    func `Cross-domain reload passes through`() async throws {
        let tab = try makePinnedTab(origin: #require(URL(string: "https://github.com")))
        let handler = PinnedTabContainmentHandler(tab: tab)
        let action = try MockNavigationAction.reload(url: #require(URL(string: "https://stackoverflow.com/questions/123")))

        let policy = await handler.evaluate(action)
        #expect(policy == .next)
    }

    @Test
    func `Cross-domain form submission passes through`() async throws {
        // A preview panel cannot replay a POST body - containing a form
        // submission would silently re-request the URL as a GET.
        let tab = try makePinnedTab(origin: #require(URL(string: "https://github.com")))
        let handler = PinnedTabContainmentHandler(tab: tab)
        let action = try MockNavigationAction.formSubmission(url: #require(URL(string: "https://sso.example.com/session")))

        let policy = await handler.evaluate(action)
        #expect(policy == .next)
    }

    // MARK: - Authentication Flows (Never Contained)

    @Test
    func `Link click to an OAuth provider domain passes through`() async throws {
        let tab = try makePinnedTab(origin: #require(URL(string: "https://netatmo.atlassian.net")))
        let handler = PinnedTabContainmentHandler(tab: tab)
        let action = try MockNavigationAction.linkClick(url: #require(URL(string: "https://id.atlassian.com/login")))

        let policy = await handler.evaluate(action)
        #expect(policy == .next, "Auth flows must complete in the tab so cookies land in its session")
    }

    @Test
    func `Link click to a generic OAuth authorize URL passes through`() async throws {
        let tab = try makePinnedTab(origin: #require(URL(string: "https://example.com")))
        let handler = PinnedTabContainmentHandler(tab: tab)
        let action = MockNavigationAction.linkClick(url: TestURLs.oauth)

        let policy = await handler.evaluate(action)
        #expect(policy == .next)
    }

    @Test
    func `Navigation whose redirect chain crossed an OAuth URL passes through`() async throws {
        let tab = try makePinnedTab(origin: #require(URL(string: "https://example.com")))
        let handler = PinnedTabContainmentHandler(tab: tab)

        var chain = RedirectChain()
        try chain.append(#require(URL(string: "https://example.com/signin")))
        chain.append(TestURLs.oauth)

        let crossURL = try #require(URL(string: "https://tenant.example-idp.net/consent"))
        let action = MockNavigationAction(
            url: crossURL,
            redirectChain: chain,
            isUserInitiated: true,
            isLinkActivated: true,
        )

        let policy = await handler.evaluate(action)
        #expect(policy == .next)
    }

    // MARK: - target="_blank" Links (New Window Requests)

    @Test
    func `Pinned tab shows preview for cross-domain target=_blank link`() async throws {
        let tab = try makePinnedTab(origin: #require(URL(string: "https://x.com")))
        let handler = PinnedTabContainmentHandler(tab: tab)
        let targetURL = try #require(URL(string: "https://github.com/some-repo"))
        let action = MockNavigationAction.popup(url: targetURL)

        let policy = await handler.evaluate(action)
        #expect(policy == .showPreview(targetURL), "Cross-domain target=_blank should show preview")
    }

    @Test
    func `Pinned tab allows same-domain target=_blank link`() async throws {
        let tab = try makePinnedTab(origin: #require(URL(string: "https://github.com")))
        let handler = PinnedTabContainmentHandler(tab: tab)
        let action = try MockNavigationAction.popup(url: #require(URL(string: "https://github.com/settings/profile")))

        let policy = await handler.evaluate(action)
        #expect(policy == .next, "Same-domain target=_blank should pass through")
    }

    // MARK: - Edge Cases

    @Test
    func `Containment ignores subframe navigations`() async throws {
        let tab = try makePinnedTab(origin: #require(URL(string: "https://github.com")))
        let handler = PinnedTabContainmentHandler(tab: tab)
        let action = try MockNavigationAction.subframe(url: #require(URL(string: "https://cdn.example.com/embed")))

        let policy = await handler.evaluate(action)
        #expect(policy == .next)
    }

    @Test
    func `Containment ignores non-HTTP URLs`() async throws {
        let tab = try makePinnedTab(origin: #require(URL(string: "https://mail.google.com")))
        let handler = PinnedTabContainmentHandler(tab: tab)
        let action = try MockNavigationAction(url: #require(URL(string: "mailto:user@example.com")))

        let policy = await handler.evaluate(action)
        #expect(policy == .next)
    }

    @Test
    func `Containment with nil tab passes through`() async throws {
        let handler = PinnedTabContainmentHandler(tab: nil)
        let action = try MockNavigationAction.mainFrame(url: #require(URL(string: "https://example.com")))
        let policy = await handler.evaluate(action)
        #expect(policy == .next)
    }

    @Test
    func `Containment with nil URL passes through`() async throws {
        let tab = try makePinnedTab(origin: #require(URL(string: "https://github.com")))
        let handler = PinnedTabContainmentHandler(tab: tab)
        let action = MockNavigationAction(url: nil)
        let policy = await handler.evaluate(action)
        #expect(policy == .next)
    }

    @Test
    func `Subdomain treated as same domain`() async throws {
        let tab = try makePinnedTab(origin: #require(URL(string: "https://github.com")))
        let handler = PinnedTabContainmentHandler(tab: tab)
        let action = try MockNavigationAction.linkClick(url: #require(URL(string: "https://gist.github.com/user/abc")))
        let policy = await handler.evaluate(action)
        #expect(policy == .next)
    }
}

// MARK: - Handler Chain Integration Tests

@Suite("Handler Chain Order — Containment vs Popup", .tags(.navigation))
@MainActor
struct ContainmentChainOrderTests {
    @Test
    func `Modifier click bypasses containment (opens new tab directly)`() async throws {
        let modifierHandler = ModifierClickHandler()
        let url = try #require(URL(string: "https://stackoverflow.com"))
        let action = MockNavigationAction.commandClick(url: url)

        let policy = await modifierHandler.evaluate(action)
        #expect(policy == .openInNewTab(url, activate: false))
    }

    @Test
    func `Cross-domain popup on pinned tab hits containment before popup handler`() async throws {
        let tab = try makePinnedTab(origin: #require(URL(string: "https://x.com")))
        let containmentHandler = PinnedTabContainmentHandler(tab: tab)
        let targetURL = try #require(URL(string: "https://github.com/repo"))
        let action = MockNavigationAction.popup(url: targetURL)

        let containmentPolicy = await containmentHandler.evaluate(action)
        #expect(containmentPolicy == .showPreview(targetURL))
    }

    @Test
    func `Same-domain popup passes through containment to PopupHandler`() async throws {
        let tab = try makePinnedTab(origin: #require(URL(string: "https://github.com")))
        let containmentHandler = PinnedTabContainmentHandler(tab: tab)
        let sameDomainURL = try #require(URL(string: "https://github.com/settings"))
        let action = MockNavigationAction.popup(url: sameDomainURL)

        let policy = await containmentHandler.evaluate(action)
        #expect(policy == .next, "Same-domain popup should pass through to PopupHandler")

        let popupHandler = PopupHandler(policyProvider: MockPopUpPolicyProvider(), contentProbe: MockPopupContentProbe())
        let popupPolicy = await popupHandler.evaluate(action)
        #expect(popupPolicy == .openInNewTab(sameDomainURL, activate: true))
    }

    @Test
    func `Middle click always opens new tab directly`() async throws {
        let modifierHandler = ModifierClickHandler()
        let url = try #require(URL(string: "https://external-site.com"))
        let action = MockNavigationAction.middleClick(url: url)

        let policy = await modifierHandler.evaluate(action)
        #expect(policy == .openInNewTab(url, activate: false))
    }

    @Test
    func `Script-initiated popup on pinned tab with cross-domain shows preview`() async throws {
        let tab = try makePinnedTab(origin: #require(URL(string: "https://example.com")))
        let containmentHandler = PinnedTabContainmentHandler(tab: tab)
        let targetURL = try #require(URL(string: "https://ads.example.net/popup"))
        let action = MockNavigationAction.popup(url: targetURL, userInitiated: false)

        let policy = await containmentHandler.evaluate(action)
        #expect(policy == .showPreview(targetURL))
    }
}
