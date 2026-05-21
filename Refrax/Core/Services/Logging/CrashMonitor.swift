import Foundation

/// Detects previous crashes via a sentinel file.
///
/// A sentinel file is written on launch and removed on clean shutdown.
/// If the sentinel exists at the start of the next session, the previous
/// session terminated abnormally (crash, force quit, or power loss).
///
/// ## Integration Points
///
/// - `applicationDidFinishLaunching`: call ``markLaunched()``
/// - `applicationWillTerminate`: call ``markCleanShutdown()``
/// - `startDeferredMaintenance`: check ``didCrashPreviously()``
nonisolated enum CrashMonitor: Sendable {
    private static let sentinelURL = Directories.appStorage
        .appendingPathComponent("crash_sentinel")

    private static let sentReportsURL = Directories.appStorage
        .appendingPathComponent("sent_crash_reports.json")

    /// Writes the sentinel file, marking the session as in-progress.
    static func markLaunched() {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        try? timestamp.write(to: sentinelURL, atomically: true, encoding: .utf8)
    }

    /// Removes the sentinel file, indicating a clean shutdown.
    static func markCleanShutdown() {
        try? FileManager.default.removeItem(at: sentinelURL)
    }

    /// Returns `true` if the sentinel exists, indicating the previous session did not shut down cleanly.
    static func didCrashPreviously() -> Bool {
        FileManager.default.fileExists(atPath: sentinelURL.path)
    }

    /// Removes the sentinel file without implying a clean shutdown.
    ///
    /// Call this after acknowledging a previous crash to prevent
    /// repeated crash detection on subsequent launches.
    static func clearSentinel() {
        try? FileManager.default.removeItem(at: sentinelURL)
    }

    /// Records crash report filenames as sent so they aren't re-submitted.
    static func markReportsSent(_ urls: [URL]) {
        var existing = loadSentReportNames()
        for url in urls {
            existing.insert(url.lastPathComponent)
        }
        if let data = try? JSONEncoder().encode(Array(existing)) {
            try? data.write(to: sentReportsURL)
        }
    }

    /// Collects crash reports from `~/Library/Logs/DiagnosticReports/` that
    /// match "Refrax" in the filename, were created within the last 7 days,
    /// and haven't been sent already.
    ///
    /// - Returns: URLs of matching crash report files, sorted most recent first.
    static func collectCrashReports() -> [URL] {
        let fm = FileManager.default
        let homeDir = fm.homeDirectoryForCurrentUser
        let diagnosticsURL = homeDir
            .appendingPathComponent("Library/Logs/DiagnosticReports", isDirectory: true)

        guard let contents = try? fm.contentsOfDirectory(
            at: diagnosticsURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles],
        ) else {
            return []
        }

        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let alreadySent = loadSentReportNames()

        return contents
            .filter { url in
                let name = url.lastPathComponent
                guard name.localizedCaseInsensitiveContains("Refrax") else { return false }
                guard !alreadySent.contains(name) else { return false }

                guard let values = try? url.resourceValues(forKeys: [.creationDateKey]),
                      let created = values.creationDate
                else {
                    return false
                }
                return created >= cutoff
            }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
                return lhsDate > rhsDate
            }
    }

    private static func loadSentReportNames() -> Set<String> {
        guard let data = try? Data(contentsOf: sentReportsURL),
              let names = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return Set(names)
    }
}
