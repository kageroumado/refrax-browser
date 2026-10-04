import Foundation

/// Sends anonymous telemetry to the Refrax backend.
///
/// Sends only while the user's ``TelemetryTier`` shares counts.
/// Fire-and-forget — failures are silently ignored.
nonisolated enum TelemetryService: Sendable {
    // MARK: - Payload

    private struct HeartbeatPayload: Encodable {
        let deviceHash: String
        let appVersion: String
        let buildNumber: String
        let macOSVersion: String
        let locale: String
    }

    // MARK: - Heartbeat

    /// Sends a daily heartbeat if the tier shares counts and >24h since last ping.
    ///
    /// Called from `RefraxAppDelegate` during deferred maintenance.
    /// Reads and writes `BrowserSettings.lastHeartbeatDate`.
    @MainActor
    static func sendHeartbeatIfNeeded(settings: BrowserSettings) {
        guard settings.telemetryTier.sendsCounting else { return }

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

    /// Field names match the server's expected JSON schema.
    private struct CrashPayload: Encodable {
        let deviceHash: String
        let appVersion: String
        let crashReason: String
        let crashCount: Int
        let domain: String
    }

    /// Reports a web content process crash if the tier shares counts.
    ///
    /// One report per crash event with `crashCount` 1 — the server aggregates
    /// by summing counts per domain and reason. Fire-and-forget.
    ///
    /// - Parameters:
    ///   - reason: Stable slug for the termination reason (e.g., "crash", "oom").
    ///   - domain: The crashing site's registrable domain (eTLD+1), never a full URL.
    ///   - settings: Settings holding the user's ``TelemetryTier``.
    @MainActor
    static func sendCrashReport(reason: String, domain: String, settings: BrowserSettings) {
        guard settings.telemetryTier.sendsCounting else { return }
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
