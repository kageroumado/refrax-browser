import Foundation

/// How Refrax reacts to a renderer ending, whichever engine it belongs to.
nonisolated extension RendererTerminationReason {
    /// Whether an automatic reload is appropriate. An intentional termination
    /// (memory-pressure unload, the user closing it) stays unloaded.
    var isRecoverable: Bool {
        switch self {
        case .crashed, .sharedProcessCrashed, .exceededMemoryLimit, .exceededCPULimit: true
        case .requestedByBrowser, .unknown: false
        }
    }

    /// Whether this counts toward the crash threshold and crash telemetry.
    var isCrash: Bool {
        self == .crashed || self == .sharedProcessCrashed
    }

    /// Whether the user should be told the page was reloaded.
    var shouldNotifyUser: Bool {
        isCrash
    }

    /// How long to wait before the automatic reload.
    var recoveryDelay: Duration {
        switch self {
        case .exceededMemoryLimit: .seconds(1)
        case .exceededCPULimit: .seconds(2)
        case .crashed, .sharedProcessCrashed, .unknown: .milliseconds(500)
        case .requestedByBrowser: .zero
        }
    }

    var logDescription: String {
        switch self {
        case .exceededMemoryLimit: "exceeded memory limit (OOM)"
        case .exceededCPULimit: "exceeded CPU limit"
        case .requestedByBrowser: "requested by the browser"
        case .crashed: "crashed"
        case .sharedProcessCrashed: "exceeded shared process crash limit"
        case .unknown: "unknown reason"
        }
    }

    /// Stable slug for the crash telemetry endpoint — the server aggregates by
    /// exact string, so these must not change between releases.
    var telemetryReason: String {
        switch self {
        case .exceededMemoryLimit: "oom"
        case .exceededCPULimit: "cpu_limit"
        case .requestedByBrowser: "requested_by_client"
        case .crashed: "crash"
        case .sharedProcessCrashed: "shared_process_crash_limit"
        case .unknown: "unknown"
        }
    }

    /// Completes "<page> … and was reloaded" in the recovery toast.
    var userDescription: String {
        switch self {
        case .exceededMemoryLimit: "ran out of memory"
        case .exceededCPULimit: "was using too much CPU"
        case .crashed, .sharedProcessCrashed: "crashed unexpectedly"
        case .requestedByBrowser: "was closed"
        case .unknown: "encountered an error"
        }
    }
}
