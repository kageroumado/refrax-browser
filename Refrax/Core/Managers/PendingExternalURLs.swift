import Foundation

/// Holds URLs from other applications until the browser can open them.
///
/// AppKit delivers the URL that launched Refrax between `applicationWillFinishLaunching`
/// and `applicationDidFinishLaunching`. At that point restored windows may already exist,
/// but spaces load from persistence one run loop later, so a tab has nowhere to go. The
/// app delegate admits every external URL through this gate, and opens the gate once
/// spaces and windows are in place (after onboarding, when it runs).
struct PendingExternalURLs {
    /// A URL to open, with the application that sent it.
    struct Request: Equatable {
        let url: URL
        let sourceAppBundleID: String?
    }

    /// Whether requests pass straight through.
    private(set) var isOpen = false

    private var held: [Request] = []

    /// Admits a request.
    ///
    /// - Returns: The request to open now, or `nil` when it is held for ``open()``.
    mutating func admit(_ request: Request) -> Request? {
        guard isOpen else {
            held.append(request)
            return nil
        }
        return request
    }

    /// Opens the gate.
    ///
    /// - Returns: The held requests in arrival order. Later calls return an empty array.
    mutating func open() -> [Request] {
        isOpen = true
        defer { held.removeAll() }
        return held
    }
}
