import Foundation

/// Information about a web content process crash that exceeded auto-recovery.
///
/// Set on ``WebPage/crashError`` when the crash threshold is exceeded or
/// auto-recovery is disabled. The view layer renders a ``CrashPageView``
/// when this is present, giving the user actionable information about what
/// happened and the ability to retry.
struct CrashError: Equatable {
    /// The termination reason reported by WebKit.
    let reason: _WKProcessTerminationReason

    /// Number of crashes within the tracking window.
    let crashCount: Int

    /// The URL that was loaded when the crash occurred.
    let url: URL

    /// When the crash (or final crash in a series) occurred.
    let timestamp: Date
}
