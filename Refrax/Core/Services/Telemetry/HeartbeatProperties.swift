import AppKit

/// Refrax's app-specific fields for the daily check-in.
///
/// `activeDays7` goes in the check-in's common fields; the rest go in its
/// `properties`, under the keys the server's Refrax allowlist expects.
nonisolated struct HeartbeatProperties: Codable, Equatable, Sendable {
    let chromiumInstalled: Bool
    let chromiumUsed7d: Bool
    let isDefaultBrowser: Bool
    let activeDays7: Int

    /// The current values.
    @MainActor
    static func current(registry: EngineRegistry, now: Date = Date()) -> HeartbeatProperties {
        let log = UsageLogStore.load()
        return HeartbeatProperties(
            chromiumInstalled: registry.descriptor(for: .chromium) != nil,
            chromiumUsed7d: log.chromiumUsed7d(asOf: now),
            isDefaultBrowser: isDefaultBrowser(
                handler: NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!),
                app: Bundle.main.bundleURL,
            ),
            activeDays7: log.activeDays7(asOf: now),
        )
    }

    /// Whether `handler`, the app macOS opens web links with, is `app`.
    static func isDefaultBrowser(handler: URL?, app: URL) -> Bool {
        guard let handler else { return false }
        return handler.standardizedFileURL.resolvingSymlinksInPath().pathComponents
            == app.standardizedFileURL.resolvingSymlinksInPath().pathComponents
    }
}
