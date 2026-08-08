import Foundation

/// Sends anonymous telemetry to the Refrax backend.
///
/// Telemetry is opt-in by default, but forced on when the release channel
/// requires it (see ``Constants.ReleaseChannel.forceTelemetry``).
/// Fire-and-forget — failures are silently ignored.
///
/// ## Co-located Description
///
/// The `heartbeatDescription` and `crashReportDescription` constants below
/// are the single source of truth for what's collected. The onboarding alpha
/// info screen reads them directly. If a field is added to a payload, update
/// the matching description here.
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

    /// Description of what a web-process crash report collects.
    /// Displayed verbatim in the analytics disclosure screen.
    static let crashReportDescription = """
    When a web page's process crashes:
    \u{2022} Anonymous device identifier and app version
    \u{2022} Crash reason (e.g., "crash", "oom")
    \u{2022} The site's domain only (e.g., "example.com" — never the full URL)
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

    // MARK: - Crash Reports

    /// Matches `crashReportDescription` fields exactly.
    /// Field names match the server's expected JSON schema.
    private struct CrashPayload: Encodable {
        let deviceHash: String
        let appVersion: String
        let crashReason: String
        let crashCount: Int
        let domain: String
    }

    /// Reports a web content process crash if telemetry is enabled.
    ///
    /// One report per crash event with `crashCount` 1 — the server aggregates
    /// by summing counts per domain and reason. Fire-and-forget.
    ///
    /// - Parameters:
    ///   - reason: Stable slug for the termination reason (e.g., "crash", "oom").
    ///   - domain: The crashing site's registrable domain (eTLD+1), never a full URL.
    ///   - settings: Settings to check the telemetry consent gate.
    @MainActor
    static func sendCrashReport(reason: String, domain: String, settings: BrowserSettings) {
        let forceTelemetry = Constants.App.releaseChannel.forceTelemetry
        guard forceTelemetry || settings.telemetryEnabled else { return }
        guard let telemetryCrash = Constants.API.telemetryCrash else { return }

        let payload = CrashPayload(
            deviceHash: DeviceIdentifier.value,
            appVersion: Constants.App.version,
            crashReason: reason,
            crashCount: 1,
            domain: domain,
        )

        Task.detached(priority: .utility) {
            try? await HTTPClient.post(telemetryCrash, body: payload)
        }
    }
}
