import Foundation
@testable import Refrax
import Testing

@Suite("Page prompts")
@MainActor
struct PagePromptsTests {
    /// Starts `ask` and lets it reach the queue.
    private func asking(_ prompts: PagePrompts, _ question: PageQuestion) async -> Task<PageAnswer, Never> {
        let task = Task { await prompts.ask(question) }
        await Task.yield()
        return task
    }

    @Test("Questions are shown one at a time, in order, and answered once each")
    func order() async {
        let prompts = PagePrompts()
        let first = await asking(prompts, .alert(message: "one", origin: "a.example"))
        let second = await asking(prompts, .confirm(message: "two", origin: "a.example"))

        #expect(prompts.current?.question == .alert(message: "one", origin: "a.example"))
        prompts.answer(.accept)
        #expect(await first.value == .accept)
        #expect(prompts.current?.question == .confirm(message: "two", origin: "a.example"))
        prompts.answer(.decline)
        #expect(await second.value == .decline)
        #expect(prompts.current == nil)
    }

    @Test("Questions past the limit are declined without being shown")
    func limit() async {
        let prompts = PagePrompts()
        let pending = [
            await asking(prompts, .alert(message: "1", origin: "")),
            await asking(prompts, .alert(message: "2", origin: "")),
            await asking(prompts, .alert(message: "3", origin: "")),
        ]
        #expect(await prompts.ask(.alert(message: "4", origin: "")) == .decline)
        prompts.dismissAll()
        for task in pending {
            #expect(await task.value == .decline)
        }
    }

    @Test("Dismissing declines everything pending")
    func dismiss() async {
        let prompts = PagePrompts()
        let first = await asking(prompts, .permission(kind: .camera, origin: "a.example"))
        let second = await asking(prompts, .leavePage(origin: "a.example"))
        prompts.dismissAll()
        #expect(await first.value == .decline)
        #expect(await second.value == .decline)
        #expect(prompts.current == nil)
    }
}

@Suite("Page permissions")
@MainActor
struct PagePermissionsTests {
    @Test("Site settings answer without asking; Ask asks; Always Allow is remembered")
    func decisions() async throws {
        let env = try TabManagerTestEnvironment()
        let permissions = PagePermissions(siteSettingsManager: env.siteSettingsManager)
        let prompts = PagePrompts()

        let settings = env.siteSettingsManager.settingsOrCreate(for: "denied.example")
        settings.cameraPermission = .deny
        env.siteSettingsManager.save(settings)
        #expect(await permissions.decide(.camera, host: "denied.example", prompts: prompts) == false)
        #expect(prompts.current == nil)

        let asked = Task { await permissions.decide(.microphone, host: "new.example", prompts: prompts) }
        await Task.yield()
        #expect(prompts.current?.question == .permission(kind: .microphone, origin: "new.example"))
        prompts.answer(.acceptAndRemember)
        #expect(await asked.value)
        #expect(permissions.policy(for: .microphone, host: "new.example") == .allow)
        #expect(await permissions.decide(.microphone, host: "new.example", prompts: prompts))
    }

    @Test("Kinds without a site setting never ask to be remembered", arguments: [PermissionKind.screenCapture, .notifications, .clipboardRead])
    func unremembered(kind: PermissionKind) throws {
        let env = try TabManagerTestEnvironment()
        let permissions = PagePermissions(siteSettingsManager: env.siteSettingsManager)
        permissions.remember(kind, allowed: true, host: "a.example")
        #expect(env.siteSettingsManager.settings(for: "a.example") == nil)
        #expect(!kind.isRememberable)
    }

    @Test("Screen capture is allowed unless the site forbids it; notifications are denied")
    func fixedPolicies() throws {
        let env = try TabManagerTestEnvironment()
        let permissions = PagePermissions(siteSettingsManager: env.siteSettingsManager)
        #expect(permissions.policy(for: .screenCapture, host: "a.example") == .allow)
        #expect(permissions.policy(for: .notifications, host: "a.example") == .deny)
    }
}
