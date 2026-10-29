import Testing
@testable import Refrax

@MainActor
private struct BackgroundTabFixture {
    let env: TabManagerTestEnvironment
    let space: Space
    let window: WindowState
    let source: Tab
    let presenter: BrowserDialogPresenter
    let decider: BrowserNavigationDecider

    init(grouped: Bool = false) throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let group = grouped ? try env.groupManager.createGroup(in: space, name: "References") : nil
        let source = env.createActiveTab(url: .blank, in: space, for: window, groupID: group?.id)
        let presenter = BrowserDialogPresenter(dialogState: env.browserState.dialogState)
        self.env = env
        self.space = space
        self.window = window
        self.source = source
        self.presenter = presenter
        self.decider = BrowserNavigationDecider(
            tabManager: env.tabManager,
            downloadManager: env.downloadManager,
            tabPage: source.activePage,
            tab: source,
            settings: env.settings,
            siteSettingsCoordinator: env.browserState.siteSettingsCoordinator,
            dialogPresenter: presenter,
        )
    }
}

@Suite("Background tab confirmation", .serialized)
@MainActor
struct BackgroundTabConfirmationTests {
    @Test(arguments: [false, true])
    func `A background link confirms its destination and Show Tab activates it`(grouped: Bool) throws {
        let fixture = try BackgroundTabFixture(grouped: grouped)
        defer { fixture.window.dismissToast() }
        fixture.decider.openInNewTab(url: .blank, activate: false)
        let created = try #require(fixture.space.mainTabs.first { $0.id != fixture.source.id })
        #expect(fixture.window.activeTabID == fixture.source.id)
        #expect(created.groupID == fixture.source.groupID)
        #expect(fixture.window.toastMessage == "Opened in background · \(grouped ? "References" : "Tabs")")
        let action = try #require(fixture.window.toastAction)
        #expect(action.title == "Show Tab")
        action.perform()
        #expect(fixture.window.activeTabID == created.id)
    }

    @Test
    func `Foreground navigation shows the new page directly`() throws {
        let fixture = try BackgroundTabFixture()
        fixture.decider.openInNewTab(url: .blank, activate: true)
        #expect(fixture.window.activeTabID != fixture.source.id)
        #expect(fixture.window.toastMessage == nil)
    }

    @Test
    func `Show Tab safely handles a tab closed before the notice expires`() throws {
        let fixture = try BackgroundTabFixture()
        defer { fixture.window.dismissToast() }
        fixture.decider.openInNewTab(url: .blank, activate: false)
        let created = try #require(fixture.space.mainTabs.first { $0.id != fixture.source.id })
        let action = try #require(fixture.window.toastAction)
        fixture.env.tabManager.closeTab(created)
        action.perform()
        #expect(fixture.window.activeTabID == fixture.source.id)
    }
}
