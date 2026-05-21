import Foundation
import WebKit

// MARK: - Picture-in-Picture

extension WebPage {
    /// Whether PiP can currently be toggled for this page.
    ///
    /// Returns `true` when the page has an active video element that supports PiP.
    /// This checks WebKit's internal state via the private `_canTogglePictureInPicture` API.
    var canTogglePiP: Bool {
        backingWebView._canTogglePictureInPicture
    }

    /// Whether PiP is currently active for this page.
    var isPiPActive: Bool {
        backingWebView._isPictureInPictureActive
    }

    /// Toggles Picture-in-Picture for the predominant video element.
    ///
    /// If PiP is inactive and can be toggled, enters PiP mode.
    /// If PiP is active, exits PiP mode.
    func togglePiP() {
        guard canTogglePiP else { return }
        backingWebView._togglePictureInPicture()
    }

    /// Enters Picture-in-Picture mode if available.
    ///
    /// Does nothing if PiP cannot be toggled or is already active.
    func enterPiP() {
        guard canTogglePiP, !isPiPActive else { return }
        backingWebView._togglePictureInPicture()
    }

    /// Exits Picture-in-Picture mode if active.
    ///
    /// Does nothing if PiP is not currently active.
    func exitPiP() {
        guard isPiPActive else { return }
        backingWebView._togglePictureInPicture()
    }
}
