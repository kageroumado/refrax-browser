import Foundation

/// How element (video) fullscreen is presented.
///
/// Selected globally in Settings > Tabs; consulted by
/// `InWindowFullscreenController` when a page requests fullscreen.
enum FullscreenPresentationMode: String, Codable, CaseIterable, Sendable {
    /// WebKit's default: a separate macOS fullscreen Space.
    case system

    /// Fullscreen contained inside the tab — the page believes it is
    /// fullscreen at the web view's size while browser chrome stays visible.
    case inTab

    /// Fullscreen in a separate normal window (traffic lights only) that can
    /// be moved, resized, and taken to a real macOS fullscreen via the green
    /// button.
    case windowed

    var displayName: String {
        switch self {
        case .system: "macOS Fullscreen"
        case .inTab: "In Tab"
        case .windowed: "Floating Window"
        }
    }
}
