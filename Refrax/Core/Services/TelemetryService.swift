import Foundation

/// Sends anonymous telemetry to the Refrax backend.
///
/// Telemetry is opt-in by default, but forced on when the release channel
/// requires it (see ``Constants.ReleaseChannel.forceTelemetry``).
/// Fire-and-forget — failures are silently ignored.
///
/// ## Co-located Description
///
/// The `heartbeatDescription` constant below is the single source of truth
/// for what's collected. The onboarding alpha info screen reads it
/// directly. If a field is added to the payload, update the description here.
nonisolated enum TelemetryService: Sendable {
    // MARK: - User-Facing Description (read by onboarding UI)

    /// Description of what the daily heartbeat collects.
    /// Displayed verbatim in the analytics disclosure screen.
    static let heartbeatDescription = """
    Once daily on app launch:
    \u{2022} Anonymous device identifier (non-reversible hash)
    \u{2022} App version and build number
    \u{2022} macOS version
    \u{2022} Language (e.g., "en", "ja")
    """

    // MARK: - Payload

    /// Matches `heartbeatDescription` fields exactly.
    private struct HeartbeatPayload: Encodable {
        let deviceHash: String
        let appVersion: String
        let buildNumber: String
        let macOSVersion: String
        let locale: String
    }

    // MARK: - Heartbeat

    /// Sends a daily heartbeat if telemetry is enabled and >24h since last ping.
    ///
    /// Called from `RefraxAppDelegate` during deferred maintenance.
    /// Reads and writes `BrowserSettings.lastHeartbeatDate`.
    @MainActor
    static func sendHeartbeatIfNeeded(settings: BrowserSettings) {
        let forceTelemetry = Constants.App.releaseChannel.forceTelemetry
        guard forceTelemetry || settings.telemetryEnabled else { return }

        if let lastDate = settings.lastHeartbeatDate,
           Date().timeIntervalSince(lastDate) < 86_400 {
            return
        }

        settings.lastHeartbeatDate = Date()

        let payload = HeartbeatPayload(
            deviceHash: DeviceIdentifier.value,
            appVersion: Constants.App.version,
            buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0",
            macOSVersion: {
                let v = ProcessInfo.processInfo.operatingSystemVersion
                return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
            }(),
            locale: Locale.current.language.languageCode?.identifier ?? "unknown"
        )

        guard let telemetryHeartbeat = Constants.API.telemetryHeartbeat else { return }
        Task.detached(priority: .utility) {
            try? await HTTPClient.post(telemetryHeartbeat, body: payload)
        }
    }
}
