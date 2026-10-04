import Foundation

/// Refrax-specific context sent with an automatic crash report.
///
/// Common fields (app version, macOS version, chip, memory, language) come
/// from the sender; this type carries what only Refrax knows.
nonisolated struct CrashContext: Codable, Equatable, Sendable {
    /// Where the running app bundle lives.
    enum InstallLocation: String, Codable, Sendable {
        /// `/Applications` or `~/Applications`.
        case applications
        /// A Gatekeeper App Translocation mount: the app runs from a quarantined
        /// download it was never moved out of.
        case translocated
        /// Anywhere else, e.g. Downloads or a build folder.
        case other

        /// Classifies a bundle path.
        init(bundlePath: String, homeDirectory: String = NSHomeDirectory()) {
            let path = (bundlePath as NSString).standardizingPath
            if path.contains("/AppTranslocation/") {
                self = .translocated
            } else if path.hasPrefix("/Applications/")
                || path.hasPrefix((homeDirectory as NSString).appendingPathComponent("Applications") + "/") {
                self = .applications
            } else {
                self = .other
            }
        }
    }

    /// An installed engine other than system WebKit.
    struct Engine: Codable, Equatable, Sendable {
        let id: String
        /// The engine bundle's version, e.g. `155.0.8059.12-1`.
        let version: String
    }

    let installLocation: InstallLocation
    /// The Refrax version that ran before the current one, if it changed on this Mac.
    let previousVersion: String?
    /// Launches in a row, ending with the previous one, whose session ended abnormally.
    let consecutiveLaunchCrashes: Int
    /// How long the crashed process ran, from its crash log.
    let secondsSinceLaunch: Int?
    let engines: [Engine]

    /// Collects the context for crash logs found on this launch.
    ///
    /// - Parameter crashReports: The crash logs being sent, newest first.
    @MainActor
    static func collect(crashReports: [URL], registry: EngineRegistry) -> CrashContext {
        CrashContext(
            installLocation: InstallLocation(bundlePath: Bundle.main.bundlePath),
            previousVersion: LaunchHistory.previousVersion(),
            consecutiveLaunchCrashes: CrashMonitor.consecutiveLaunchCrashes,
            secondsSinceLaunch: crashReports.first
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap(secondsSinceLaunch(ips:)),
            engines: registry.descriptors
                .filter { $0.id != .systemWebKit }
                .map { Engine(id: $0.id.rawValue, version: $0.version) },
        )
    }

    /// Seconds between process launch and crash capture in a macOS `.ips` crash log.
    ///
    /// An `.ips` file is a one-line JSON header followed by a JSON body whose
    /// `procLaunch` and `captureTime` read like `2026-10-02 02:05:30.0761 +0200`.
    static func secondsSinceLaunch(ips: Data) -> Int? {
        guard let newline = ips.firstIndex(of: UInt8(ascii: "\n")),
              let body = try? JSONSerialization.jsonObject(with: ips[ips.index(after: newline)...]) as? [String: Any],
              let launch = (body["procLaunch"] as? String).flatMap(parseIPSDate),
              let capture = (body["captureTime"] as? String).flatMap(parseIPSDate),
              capture >= launch
        else {
            return nil
        }
        return Int(capture.timeIntervalSince(launch).rounded())
    }

    private static func parseIPSDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSS Z"
        return formatter.date(from: string)
    }
}

/// Remembers which Refrax version ran last, to report the version an update came from.
///
/// Tracks every way an update arrives (in-app, Homebrew, a dragged-in copy),
/// since it compares versions at launch.
nonisolated enum LaunchHistory {
    private static let lastVersionKey = "launchHistoryLastVersion"
    private static let previousVersionKey = "launchHistoryPreviousVersion"

    /// The version that ran before the current one; `nil` until the version changes once.
    static func previousVersion(defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: previousVersionKey)
    }

    /// Records this launch's version. Called once at launch.
    static func recordLaunch(version: String = Constants.App.version, defaults: UserDefaults = .standard) {
        let last = defaults.string(forKey: lastVersionKey)
        if let last, last != version {
            defaults.set(last, forKey: previousVersionKey)
        }
        defaults.set(version, forKey: lastVersionKey)
    }
}
