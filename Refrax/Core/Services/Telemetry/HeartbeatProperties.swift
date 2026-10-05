import AppKit
import Digoxin

/// Refrax's app-specific fields for the daily check-in, sent as its
/// `properties` under the keys the server's Refrax allowlist expects.
nonisolated struct HeartbeatProperties: Equatable, Sendable {
    let chromiumInstalled: Bool
    let chromiumUsed7d: Bool
    let isDefaultBrowser: Bool

    /// The current values.
    @MainActor
    static func current(registry: EngineRegistry, now: Date = Date()) -> HeartbeatProperties {
        HeartbeatProperties(
            chromiumInstalled: registry.descriptor(for: .chromium) != nil,
            chromiumUsed7d: UsageLogStore.load().chromiumUsed7d(asOf: now),
            isDefaultBrowser: isDefaultBrowser(
                handler: NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!),
                app: Bundle.main.bundleURL,
            ),
        )
    }

    /// The fields keyed as the check-in sends them.
    var values: [String: TelemetryValue] {
        [
            "chromiumInstalled": .bool(chromiumInstalled),
            "chromiumUsed7d": .bool(chromiumUsed7d),
            "isDefaultBrowser": .bool(isDefaultBrowser),
        ]
    }

    /// Whether `handler`, the app macOS opens web links with, is `app`.
    static func isDefaultBrowser(handler: URL?, app: URL) -> Bool {
        guard let handler else { return false }
        return handler.standardizedFileURL.resolvingSymlinksInPath().pathComponents
            == app.standardizedFileURL.resolvingSymlinksInPath().pathComponents
    }
}
