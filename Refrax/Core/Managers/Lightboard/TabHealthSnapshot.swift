import Foundation
import SwiftUI
import WebKit

// MARK: - Tab Health Snapshot

/// Snapshot of tab state for the Lightboard dashboard.
///
/// Captures all relevant health metrics for a single tab page at a point in time.
/// Used by `TabHealthProvider` to provide live-updating views of tab status.
struct TabHealthSnapshot: Identifiable {
    // MARK: - Identity

    /// Unique identifier (matches TabPage.id).
    let id: UUID

    /// Reference to the underlying TabPage.
    let tabPage: TabPage

    /// Reference to the WebPage if currently instantiated.
    let webPage: WebPage?

    /// Name of the space containing this tab.
    let spaceName: String

    // MARK: - Process State

    /// Current process state.
    let processState: TabProcessState

    /// Reason for last termination, if any.
    let lastTerminationReason: _WKProcessTerminationReason?

    /// Whether the tab has crashed and not yet been reloaded.
    let hasCrashed: Bool

    // MARK: - Activity

    /// Whether the tab is currently playing audio.
    let isPlayingAudio: Bool

    /// Camera capture state.
    let cameraCaptureState: WKMediaCaptureState

    /// Microphone capture state.
    let microphoneCaptureState: WKMediaCaptureState

    /// Whether the tab has unsaved form data.
    let hasUnsavedFormData: Bool

    // MARK: - Memory

    /// PID of the web content process hosting this tab, or 0 if not running.
    let processPID: pid_t

    /// Physical memory of the entire process hosting this tab (bytes).
    let processMemoryBytes: UInt64

    /// Estimated memory attributed to this tab (bytes).
    /// If the process hosts multiple tabs, this is processMemory / tabCount.
    let estimatedTabMemoryBytes: UInt64

    /// Number of tabs sharing this tab's process.
    let tabsInProcess: Int

    /// Human-friendly process name (e.g. "Process 1").
    let processName: String

    // MARK: - Status

    /// Whether this tab is the currently active (foreground) tab.
    let isActiveTab: Bool

    // MARK: - Importance

    /// Calculated importance score.
    let importanceScore: Int

    /// Breakdown of factors contributing to importance score.
    let importanceFactors: [ImportanceFactor]

    // MARK: - Timestamps

    /// When the tab was last visible/active.
    let lastVisibleAt: Date?

    /// When the tab was created.
    let createdAt: Date
}

// MARK: - Computed Properties

extension TabHealthSnapshot {
    /// Display title for the tab.
    var title: String {
        let pageTitle = tabPage.title
        if pageTitle.isEmpty {
            return tabPage.url.host ?? "Untitled"
        }
        return pageTitle
    }

    /// URL of the tab.
    var url: URL {
        tabPage.url
    }

    /// Domain for display.
    var domain: String {
        tabPage.url.host ?? ""
    }

    /// Whether this tab is protected from eviction.
    var isProtected: Bool {
        importanceScore >= PageImportanceScorer.Weight.playingMedia
    }

    /// Whether any media capture is active.
    var hasActiveMediaCapture: Bool {
        cameraCaptureState == .active || microphoneCaptureState == .active
    }

    /// Whether this tab has any activity indicators.
    var hasActivityIndicators: Bool {
        isPlayingAudio || hasActiveMediaCapture || hasUnsavedFormData
    }

    /// Whether this tab is pinned.
    var isPinned: Bool {
        tabPage.tab?.isPinned ?? false
    }

    /// Whether this tab shares its process with other tabs.
    var sharesProcess: Bool {
        tabsInProcess > 1
    }

    /// Formatted estimated tab memory string (e.g. "64 MB").
    ///
    /// Shows "Inactive" for tabs whose process is not running or suspended,
    /// "< 1 MB" for running tabs with sub-megabyte memory.
    var formattedMemory: String {
        if processState == .notRunning || processState == .suspended {
            return "Inactive"
        }
        let mb = estimatedTabMemoryBytes / 1_024 / 1_024
        if mb == 0 {
            return "< 1 MB"
        }
        return "\(mb) MB"
    }

    /// Formatted process memory with shared indicator.
    var formattedProcessMemory: String {
        let mb = processMemoryBytes / 1_024 / 1_024
        if sharesProcess {
            return "\(mb) MB (shared with \(tabsInProcess - 1) other tab\(tabsInProcess > 2 ? "s" : ""))"
        }
        return "\(mb) MB"
    }
}

// MARK: - Tab Process State

/// Unified process state for display purposes.
///
/// Maps WebKit's `_WKWebProcessState` to user-friendly states,
/// with additional handling for crashed and not-instantiated tabs.
enum TabProcessState: String, CaseIterable, Identifiable {
    case running = "Running"
    case background = "Background"
    case suspended = "Suspended"
    case notRunning = "Not Running"
    case crashed = "Crashed"

    var id: String { rawValue }

    /// Color for the state indicator.
    var color: Color {
        switch self {
        case .running: .green
        case .background: .yellow
        case .suspended: .blue
        case .notRunning: .secondary
        case .crashed: .red
        }
    }

    /// SF Symbol for the state indicator.
    var icon: String {
        switch self {
        case .running: "circle.fill"
        case .background: "circle.bottomhalf.filled"
        case .suspended: "pause.circle.fill"
        case .notRunning: "circle"
        case .crashed: "exclamationmark.circle.fill"
        }
    }

    /// Priority for sorting (higher = shown first).
    var sortPriority: Int {
        switch self {
        case .crashed: 5
        case .running: 4
        case .background: 3
        case .suspended: 2
        case .notRunning: 1
        }
    }

    /// Creates a process state from WebKit's internal state.
    static func from(
        webProcessState: _WKWebProcessState?,
        hasCrashed: Bool,
    ) -> TabProcessState {
        if hasCrashed {
            return .crashed
        }

        guard let state = webProcessState else {
            return .notRunning
        }

        switch state {
        case .foreground: return .running
        case .background: return .background
        case .suspended: return .suspended
        case .notRunning: return .notRunning
        @unknown default: return .notRunning
        }
    }
}

// MARK: - Importance Factor

/// A single factor contributing to a tab's importance score.
struct ImportanceFactor: Identifiable, Equatable {
    let id = UUID()

    /// Human-readable name for the factor.
    let name: String

    /// Points contributed to the total score.
    let points: Int

    /// SF Symbol for the factor.
    let icon: String

    static func == (lhs: ImportanceFactor, rhs: ImportanceFactor) -> Bool {
        lhs.name == rhs.name && lhs.points == rhs.points && lhs.icon == rhs.icon
    }
}
