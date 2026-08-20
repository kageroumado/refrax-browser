import Foundation
import WebKit

// MARK: - Picture-in-Picture

/// PiP-relevant video state observed from page JavaScript.
struct PiPState: Decodable {
    /// Whether a video on the page is presenting in Picture-in-Picture.
    let active: Bool
    /// Whether any video on the page is playing.
    let playing: Bool
    /// Whether any video on the page supports Picture-in-Picture.
    let eligible: Bool

    static let unknown = PiPState(active: false, playing: false, eligible: false)
}

extension WebPage {
    /// Whether WebKit's playback-controls session reports PiP as toggleable.
    ///
    /// Advisory only: the underlying `canTogglePictureInPicture()` requires the
    /// video to be the current playback-controls-manager element and reads
    /// `false` for many pages where PiP works (measured on YouTube). Use
    /// ``pipState()`` for an authoritative answer.
    var canTogglePiP: Bool {
        backingWebView._canTogglePictureInPicture
    }

    /// Whether the playback-controls session reports PiP as active.
    ///
    /// Advisory only, same gate as ``canTogglePiP`` — it can read `false`
    /// while a PiP panel is on screen. Use ``pipState()`` for an
    /// authoritative answer.
    var isPiPActive: Bool {
        backingWebView._isPictureInPictureActive
    }

    /// Reads the page's PiP state via JavaScript.
    ///
    /// This is the authoritative signal — the native properties above
    /// false-negative whenever the playback-controls session is absent.
    /// Cross-origin iframe videos are invisible to this probe.
    func pipState() async -> PiPState {
        guard let json = try? await evaluateJavaScriptWithoutUserGesture(JavaScriptSnippets.pictureInPictureState) as? String,
              let data = json.data(using: .utf8),
              let state = try? JSONDecoder().decode(PiPState.self, from: data)
        else {
            return .unknown
        }
        return state
    }

    /// Enters Picture-in-Picture for the page's predominant video.
    ///
    /// Uses the native `_togglePictureInPicture` SPI when its playback session
    /// reports capability (this also covers cross-origin iframe videos), and
    /// otherwise drives `webkitSetPresentationMode` on the best candidate
    /// video via JavaScript. The evaluation is deliberately gesture-forced:
    /// PiP entry is gated on `mediaSession().fullscreenPermitted()`.
    func enterPiP() async {
        if backingWebView._canTogglePictureInPicture, !backingWebView._isPictureInPictureActive {
            backingWebView._togglePictureInPicture()
            return
        }
        _ = try? await evaluateJavaScript(JavaScriptSnippets.enterPictureInPicture)
    }

    /// Exits Picture-in-Picture if active.
    func exitPiP() async {
        if backingWebView._isPictureInPictureActive {
            backingWebView._togglePictureInPicture()
            return
        }
        _ = try? await evaluateJavaScriptWithoutUserGesture(JavaScriptSnippets.exitPictureInPicture)
    }

    /// Toggles Picture-in-Picture for the page's predominant video.
    func togglePiP() async {
        if await pipState().active {
            await exitPiP()
        } else {
            await enterPiP()
        }
    }
}
