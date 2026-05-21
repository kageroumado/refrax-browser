import Foundation
import Testing

@testable import Refrax

// MARK: - Helper: Create Tab for Handler Testing (No SwiftData)

@MainActor
private func makePinnedTab(origin: URL) -> Tab {
    let tab = Tab(space: nil, url: origin, title: origin.host ?? "Pinned", status: .pinned)
    tab.originURL = origin
    return tab
}

// MARK: - PinnedTabContainmentHandler Tests

@Suite("PinnedTabContainmentHandler", .tags(.navigation))
@MainActor
struct PinnedTabContainmentHandlerTests {

    // MARK: - Regular Tabs (No Containment)

    @Test("Regular tab allows all navigations")
    func regularTabNoContainment() async {
        let tab = Tab(space: nil, url: URL(string: "https://example.com")!, title: "Example", status: .regular)
        let handler = PinnedTabContainmentHandler(tab: tab)
        let action = MockNavigationAction.mainFrame(url: URL(string: "https://different-domain.com")!)

        let policy = await handler.evaluate(action)
        #expect(policy == .next, "Regular tabs should not be contained")
    }

    // MARK: - Pinned Tabs: Main Frame

    @Test("Pinned tab allows same-domain navigation")
    func pinnedTabSameDomain() async {
        let tab = makePinnedTab(origin: URL(string: "https://github.com")!)
        let handler = PinnedTabContainmentHandler(tab: tab)
        let action = MockNavigationAction.mainFrame(url: URL(string: "https://github.com/anthropics/claude-code")!)

        let policy = await handler.evaluate(action)
        #expect(policy == .next)
    }

    @Test("Pinned tab shows preview for cross-domain navigation")
    func pinnedTabCrossDomain() async {
        let tab = makePinnedTab(origin: URL(string: "https://github.com")!)
        let handler = PinnedTabContainmentHandler(tab: tab)
        let crossURL = URL(string: "https://stackoverflow.com/questions/123")!
        let action = MockNavigationAction.mainFrame(url: crossURL)

        let policy = await handler.evaluate(action)
        #expect(policy == .showPreview(crossURL))
    }

    // MARK: - target="_blank" Links (New Window Requests)

    @Test("Pinned tab shows preview for cross-domain target=_blank link")
    func pinnedTabCrossDomainPopup() async {
        let tab = makePinnedTab(origin: URL(string: "https://x.com")!)
        let handler = PinnedTabContainmentHandler(tab: tab)
        let targetURL = URL(string: "https://github.com/some-repo")!
        let action = MockNavigationAction.popup(url: targetURL)

        let policy = await handler.evaluate(action)
        #expect(policy == .showPreview(targetURL), "Cross-domain target=_blank should show preview")
    }

    @Test("Pinned tab allows same-domain target=_blank link")
    func pinnedTabSameDomainPopup() async {
        let tab = makePinnedTab(origin: URL(string: "https://github.com")!)
        let handler = PinnedTabContainmentHandler(tab: tab)
        let action = MockNavigationAction.popup(url: URL(string: "https://github.com/settings/profile")!)

        let policy = await handler.evaluate(action)
        #expect(policy == .next, "Same-domain target=_blank should pass through")
    }

    // MARK: - Edge Cases

    @Test("Containment ignores subframe navigations")
    func subframeIgnored() async {
        let tab = makePinnedTab(origin: URL(string: "https://github.com")!)
        let handler = PinnedTabContainmentHandler(tab: tab)
        let action = MockNavigationAction.subframe(url: URL(string: "https://cdn.example.com/embed")!)

        let policy = await handler.evaluate(action)
        #expect(policy == .next)
    }

    @Test("Containment ignores non-HTTP URLs")
    func nonHTTPIgnored() async {
        let tab = makePinnedTab(origin: URL(string: "https://mail.google.com")!)
        let handler = PinnedTabContainmentHandler(tab: tab)
        let action = MockNavigationAction(url: URL(string: "mailto:user@example.com")!)

        let policy = await handler.evaluate(action)
        #expect(policy == .next)
    }

    @Test("Containment with nil tab passes through")
    func nilTabPassesThrough() async {
        let handler = PinnedTabContainmentHandler(tab: nil)
        let action = MockNavigationAction.mainFrame(url: URL(string: "https://example.com")!)
        let policy = await handler.evaluate(action)
        #expect(policy == .next)
    }

    @Test("Containment with nil URL passes through")
    func nilURLPassesThrough() async {
        let tab = makePinnedTab(origin: URL(string: "https://github.com")!)
        let handler = PinnedTabContainmentHandler(tab: tab)
        let action = MockNavigationAction(url: nil)
        let policy = await handler.evaluate(action)
        #expect(policy == .next)
    }

    @Test("Subdomain treated as same domain")
    func subdomainSameDomain() async {
        let tab = makePinnedTab(origin: URL(string: "https://github.com")!)
        let handler = PinnedTabContainmentHandler(tab: tab)
        let action = MockNavigationAction.mainFrame(url: URL(string: "https://gist.github.com/user/abc")!)
        let policy = await handler.evaluate(action)
        #expect(policy == .next)
    }
}

// MARK: - Handler Chain Integration Tests

@Suite("Handler Chain Order — Containment vs Popup", .tags(.navigation))
@MainActor
struct ContainmentChainOrderTests {

    @Test("Modifier click bypasses containment (opens new tab directly)")
    func modifierClickBypassesContainment() async {
        let modifierHandler = ModifierClickHandler()
        let url = URL(string: "https://stackoverflow.com")!
        let action = MockNavigationAction.commandClick(url: url)

        let policy = await modifierHandler.evaluate(action)
        #expect(policy == .openInNewTab(url, activate: false))
    }

    @Test("Cross-domain popup on pinned tab hits containment before popup handler")
    func regularClickHitsContainment() async {
        let tab = makePinnedTab(origin: URL(string: "https://x.com")!)
        let containmentHandler = PinnedTabContainmentHandler(tab: tab)
        let targetURL = URL(string: "https://github.com/repo")!
        let action = MockNavigationAction.popup(url: targetURL)

        let containmentPolicy = await containmentHandler.evaluate(action)
        #expect(containmentPolicy == .showPreview(targetURL))
    }

    @Test("Same-domain popup passes through containment to PopupHandler")
    func sameDomainPopupPassesThrough() async {
        let tab = makePinnedTab(origin: URL(string: "https://github.com")!)
        let containmentHandler = PinnedTabContainmentHandler(tab: tab)
        let sameDomainURL = URL(string: "https://github.com/settings")!
        let action = MockNavigationAction.popup(url: sameDomainURL)

        let policy = await containmentHandler.evaluate(action)
        #expect(policy == .next, "Same-domain popup should pass through to PopupHandler")

        let popupHandler = PopupHandler(policyProvider: MockPopUpPolicyProvider(), contentProbe: MockPopupContentProbe())
        let popupPolicy = await popupHandler.evaluate(action)
        #expect(popupPolicy == .openInNewTab(sameDomainURL, activate: true))
    }

    @Test("Middle click always opens new tab directly")
    func middleClickBypassesContainment() async {
        let modifierHandler = ModifierClickHandler()
        let url = URL(string: "https://external-site.com")!
        let action = MockNavigationAction.middleClick(url: url)

        let policy = await modifierHandler.evaluate(action)
        #expect(policy == .openInNewTab(url, activate: false))
    }

    @Test("Script-initiated popup on pinned tab with cross-domain shows preview")
    func scriptPopupOnPinnedTab() async {
        let tab = makePinnedTab(origin: URL(string: "https://example.com")!)
        let containmentHandler = PinnedTabContainmentHandler(tab: tab)
        let targetURL = URL(string: "https://ads.example.net/popup")!
        let action = MockNavigationAction.popup(url: targetURL, userInitiated: false)

        let policy = await containmentHandler.evaluate(action)
        #expect(policy == .showPreview(targetURL))
    }
}
