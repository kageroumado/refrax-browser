import Foundation

/// How much anonymous telemetry the user agreed to share.
///
/// Raw values match Digoxin's `ConsentTier`, so wiring the library maps one
/// to the other by raw value.
nonisolated enum TelemetryTier: String, CaseIterable, Codable, Sendable {
    /// Nothing is sent.
    case off
    /// A daily anonymous check-in with basic info.
    case counting
    /// The daily check-in, plus crash reports after a crash.
    case crashReports

    /// The tier preselected in onboarding.
    static let recommended: TelemetryTier = .crashReports

    /// Whether the daily check-in is sent.
    var sendsCounting: Bool {
        self != .off
    }

    /// Whether a crash report is sent automatically after the app crashes.
    var sendsCrashReports: Bool {
        self == .crashReports
    }

    /// Short name for pickers.
    var title: String {
        switch self {
        case .off: "No telemetry"
        case .counting: "Count me"
        case .crashReports: "Count me and send crash reports"
        }
    }

    /// One-sentence explanation shown under each choice.
    var summary: String {
        switch self {
        case .off:
            "Nothing is sent."
        case .counting:
            "Once a day, Refrax checks in anonymously with basic info. It\u{2019}s how I measure public interest."
        case .crashReports:
            "Also sends a crash report after a crash. Personal details like file paths, names, and URLs are removed before it leaves your Mac."
        }
    }

    /// Whether to ask for a tier once after launch: onboarding, which asks
    /// new installs, is done and no tier was ever chosen.
    static func needsPrompt(hasCompletedOnboarding: Bool, chosenTier: String?) -> Bool {
        hasCompletedOnboarding && chosenTier == nil
    }
}

/// The exact fields each tier shares, shown in onboarding and Settings.
nonisolated enum TelemetryDisclosure: Sendable {
    /// Fields in the daily check-in (``TelemetryTier/counting`` and above).
    static let checkInFields: [String] = [
        "A random install ID, unlinkable to your Mac or Apple account",
        "Refrax version and build",
        "macOS version",
        "Mac chip family (M1, M2, …) and memory size",
        "Language (e.g. \u{201C}en\u{201D})",
        "How many of the last 7 days you used Refrax",
        "Whether the Chromium engine is installed, and whether you used it this week",
        "Whether Refrax is your default browser",
    ]

    /// Fields added by crash reports (``TelemetryTier/crashReports``).
    static let crashReportFields: [String] = [
        "The macOS crash log, with your user name, Mac name, home folder, and machine IDs removed",
        "Recent internal errors, with web addresses cut down to the site\u{2019}s domain",
        "Where Refrax is installed (Applications or elsewhere)",
        "The version you updated from, and how long Refrax ran before crashing",
        "How many launches in a row ended in a crash",
        "Installed engines and their versions",
    ]
}
