import Foundation
import Testing

@testable import Refrax

// MARK: - Wire

@Suite("Engine navigation requests", .tags(.engines, .navigation))
struct EngineNavigationWireTests {
    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    @Test("A navigation request decodes with its kind and initiator")
    func decodesNavigation() throws {
        let request = try EngineWire.decodeRequest(data(
            #"{"navigation":{"url":"https://a.example/x","kind":"link","initiatorOrigin":"https://b.example"}}"#,
        ))
        #expect(request == .navigation(url: URL(string: "https://a.example/x")!, kind: .link, initiatorOrigin: "https://b.example"))
    }

    @Test("A navigation Refrax started carries no initiator")
    func decodesWithoutInitiator() throws {
        let request = try EngineWire.decodeRequest(data(#"{"navigation":{"url":"https://a.example/","kind":"other"}}"#))
        #expect(request == .navigation(url: URL(string: "https://a.example/")!, kind: .other, initiatorOrigin: nil))
    }

    @Test("A navigation to a scheme engines may not report is rejected")
    func rejectsScheme() {
        #expect(throws: EngineError.self) {
            try EngineWire.decodeRequest(data(#"{"navigation":{"url":"javascript:alert(1)","kind":"link"}}"#))
        }
    }

    @Test("openURL from a 1.1 engine decodes without isNewWindowRequest")
    func openURLWithoutNewWindowField() throws {
        let request = try EngineWire.decodeRequest(data(
            #"{"openURL":{"url":"https://a.example/","disposition":"backgroundTab","userGesture":true}}"#,
        ))
        #expect(request == .openURL(url: URL(string: "https://a.example/")!, disposition: .backgroundTab, userGesture: true, isNewWindowRequest: nil))
    }
}

// MARK: - Handlers

@Suite("Engine navigations through the handler chain", .tags(.engines, .navigation))
@MainActor
struct EngineNavigationHandlerTests {
    private let home = URL(string: "https://github.com")!
    private let elsewhere = URL(string: "https://kagerou.glass/phosphene/")!

    private func pinnedTab() -> Tab {
        let tab = Tab(space: nil, url: home, title: "GitHub", status: .pinned)
        tab.originURL = home
        return tab
    }

    private func link(_ url: URL, kind: NavigationKind = .link) -> EngineNavigationAction {
        EngineNavigationAction(url: url, kind: kind, initiatorOrigin: "https://github.com")
    }

    private func open(
        _ url: URL,
        _ disposition: OpenDisposition,
        isNewWindowRequest: Bool?,
        userGesture: Bool = true,
    ) -> EngineNavigationAction {
        EngineNavigationAction(
            url: url,
            disposition: disposition,
            userGesture: userGesture,
            isNewWindowRequest: isNewWindowRequest,
            sourceURL: home,
        )
    }

    @Test("A pinned tab's cross-domain link opens in a preview")
    func containsLink() async {
        let policy = await PinnedTabContainmentHandler(tab: pinnedTab()).evaluate(link(elsewhere))
        #expect(policy == .showPreview(elsewhere))
    }

    @Test("A pinned tab's script or redirect navigation moves the tab")
    func passesOtherKinds() async {
        let handler = PinnedTabContainmentHandler(tab: pinnedTab())
        for kind in [NavigationKind.other, .formSubmission, .reload, .backForward] {
            #expect(await handler.evaluate(link(elsewhere, kind: kind)) == .next, "\(kind)")
        }
    }

    @Test("A pinned tab's target=_blank link opens in a preview")
    func containsNewWindow() async {
        let action = open(elsewhere, .foregroundTab, isNewWindowRequest: true)
        #expect(await PinnedTabContainmentHandler(tab: pinnedTab()).evaluate(action) == .showPreview(elsewhere))
    }

    @Test("⌘-click opens a background tab; ⌘⇧-click a foreground one")
    func modifierClicks() async {
        let handler = ModifierClickHandler()
        let background = open(elsewhere, .backgroundTab, isNewWindowRequest: false)
        #expect(await handler.evaluate(background) == .openInNewTab(elsewhere, activate: false))
        let foreground = open(elsewhere, .foregroundTab, isNewWindowRequest: false)
        #expect(await handler.evaluate(foreground) == .openInNewTab(elsewhere, activate: true))
    }

    @Test("Without the field, only a background tab reads as a modifier click")
    func infersFromDisposition() {
        #expect(open(elsewhere, .backgroundTab, isNewWindowRequest: nil).isCommandClick)
        #expect(open(elsewhere, .popup, isNewWindowRequest: nil).isNewWindowRequest)
    }

    @Test("A script popup without a gesture is not user-initiated")
    func scriptPopup() {
        let action = open(elsewhere, .popup, isNewWindowRequest: true, userGesture: false)
        #expect(!action.isUserInitiated)
        #expect(!action.isLinkActivated)
    }

    @Test("Tracking parameters are stripped from an engine navigation")
    func stripsTrackers() async {
        let url = URL(string: "https://engine-strip.example/page?id=7&utm_source=newsletter")!
        let policy = await LinkProtectionHandler().evaluate(link(url))
        guard case let .redirect(cleaned) = policy else {
            Issue.record("Expected .redirect, got \(policy)")
            return
        }
        #expect(cleaned.absoluteString == "https://engine-strip.example/page?id=7")
    }

    @Test("A web page cannot script its way to a file URL")
    func blocksScriptedFileNavigation() async {
        let action = EngineNavigationAction(url: URL(string: "file:///etc/hosts")!, kind: .other, initiatorOrigin: "https://evil.example")
        #expect(await FileSchemeHandler().evaluate(action) == .cancel)
        let opaque = EngineNavigationAction(url: URL(string: "file:///etc/hosts")!, kind: .other, initiatorOrigin: "null")
        #expect(await FileSchemeHandler().evaluate(opaque) == .cancel)
    }

    @Test("Refrax's own file load goes through")
    func allowsRefraxFileLoad() async {
        let action = EngineNavigationAction(url: URL(string: "file:///tmp/a.html")!, kind: .other, initiatorOrigin: nil)
        #expect(await FileSchemeHandler().evaluate(action) == .next)
    }
}

// MARK: - Site Settings Policy

@Suite("Engine site settings policy", .tags(.engines))
@MainActor
struct EngineSiteSettingsPolicyTests {
    let environment: SettingsApplierTestEnvironment
    let coordinator: SiteSettingsCoordinator

    init() throws {
        environment = try SettingsApplierTestEnvironment()
        coordinator = SiteSettingsCoordinator(
            siteSettingsManager: environment.siteSettingsManager,
            browserSettings: environment.settings,
        )
    }

    private func site(_ domain: String, _ change: (SiteSettings) -> Void) {
        let settings = environment.siteSettingsManager.settingsOrCreate(for: domain)
        change(settings)
        environment.siteSettingsManager.save(settings)
    }

    @Test("Only sites that differ from the defaults get rules")
    func rulesForOverridesOnly() {
        environment.settings.enableJavaScript = true
        site("plain.example") { $0.pageZoom = 125 }
        site("nojs.example") { $0.allowJavaScript = false }
        site("unblocked.example") { $0.enableContentBlockers = false }
        site("loud.example") { $0.autoPlayPolicy = .allowAll }

        let policy = coordinator.enginePolicy
        #expect(policy.javaScriptEnabled)
        #expect(policy.rules == [
            SiteSettingsRule(host: "loud.example", autoplayWithSound: true),
            SiteSettingsRule(host: "nojs.example", javaScriptEnabled: false),
            SiteSettingsRule(host: "unblocked.example", contentBlockingEnabled: false),
        ])
    }

    @Test("With JavaScript off by default, allowlisted sites get it back")
    func javaScriptAllowlist() {
        environment.settings.enableJavaScript = false
        environment.settings.allowJavaScriptWhitelist = true
        site("trusted.example") { $0.allowJavaScript = true }

        let policy = coordinator.enginePolicy
        #expect(!policy.javaScriptEnabled)
        #expect(policy.rules == [SiteSettingsRule(host: "trusted.example", javaScriptEnabled: true)])
    }

    @Test("Saving a site setting publishes the policy")
    func publishesOnSave() {
        var published: [SiteSettingsPolicy] = []
        coordinator.onEnginePolicyChange = { published.append($0) }
        site("nojs.example") { $0.allowJavaScript = false }
        #expect(published.last?.rules == [SiteSettingsRule(host: "nojs.example", javaScriptEnabled: false)])
        environment.siteSettingsManager.delete(for: "nojs.example")
        #expect(published.last?.rules == [])
    }

    @Test("The policy uses the contract's wire form")
    func wireForm() throws {
        let update = PolicyUpdate.siteSettings(policy: SiteSettingsPolicy(
            javaScriptEnabled: false,
            rules: [SiteSettingsRule(host: "a.example", autoplayWithSound: true)],
        ))
        let json = String(decoding: try EngineWire.encode(update), as: UTF8.self)
        #expect(json == #"{"siteSettings":{"policy":{"javaScriptEnabled":false,"rules":[{"autoplayWithSound":true,"host":"a.example"}]}}}"#)
    }
}
