import Foundation
import SwiftData
import Testing
@testable import Refrax

@Suite("External URL settings")
@MainActor
struct ExternalURLSettingsTests {
    /// Held for the test's lifetime: a model whose container is gone traps on its next write.
    let container: ModelContainer
    let settings: ExternalURLSettings

    init() throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: schema, configurations: [config])
        settings = ExternalURLSettings()
        container.mainContext.insert(settings)
    }

    @Test("A new install opens links from other apps in a Glimpse")
    func newSettingsOpenInGlimpse() {
        let action = settings.resolve(url: URL(string: "https://example.com")!, sourceAppBundleID: "com.apple.mail")

        #expect(action == .openInGlimpse)
    }

    @Test("Turning custom handling off opens links in a tab")
    func disabledHandlingUsesDefault() {
        settings.enableCustomHandling = false

        let action = settings.resolve(url: URL(string: "https://example.com")!)

        #expect(action == .default)
    }
}
