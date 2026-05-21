import WebKit

// MARK: - Web Content Display Capture State

/// State of web content's own getDisplayMedia() capture sessions.
///
/// This represents whether JavaScript on the page is actively capturing
/// screen/window content via `navigator.mediaDevices.getDisplayMedia()`.
///
/// ## Important Distinction
///
/// This tracks the **page's own capture** (web content capturing something),
/// NOT external apps capturing the browser window. For detecting when external
/// apps like Zoom or Discord are capturing this window, use
/// `NSWindow.hasActiveWindowSharingSession` (see NSWindowPrivate.h).
///
/// ## WKWebView Audio and External Screen Capture
///
/// WKWebView audio runs in a separate process (WebContent/GPU process) with
/// its own AVAudioSession. This means:
/// - ScreenCaptureKit captures audio at the app level
/// - WKWebView's audio comes from a different process
/// - External apps cannot capture WKWebView audio regardless of these settings
///
/// This is a known WebKit limitation (see Apple Developer Forums thread 670482).
enum WebContentCaptureState: Sendable {
    /// The page is not capturing any screen/window content.
    case none

    /// The page is capturing screen/window with audio enabled.
    case activeWithAudio

    /// The page is capturing screen/window but audio is muted.
    case activeButMuted

    /// Initializes from the WebKit `WKDisplayCaptureState` enum.
    @available(macOS 13.0, *)
    init(from captureState: WKDisplayCaptureState) {
        switch captureState {
        case .none: self = .none
        case .active: self = .activeWithAudio
        case .muted: self = .activeButMuted
        @unknown default: self = .none
        }
    }
}

extension WKWebView {
    // MARK: - Web Content Capture Control

    /// The current state of web content's getDisplayMedia() capture.
    ///
    /// Returns the state of any screen/window capture initiated by JavaScript
    /// on this page via `navigator.mediaDevices.getDisplayMedia()`.
    ///
    /// - Returns: `.none` if page isn't capturing, `.activeWithAudio` if capturing
    ///   with audio, `.activeButMuted` if capturing without audio.
    ///
    /// ## Important
    /// This does NOT indicate whether external apps are capturing this browser window.
    
    @available(macOS 13.0, *)
    var webContentCaptureState: WebContentCaptureState {
        WebContentCaptureState(from: _displayCaptureState)
    }

    /// Controls audio in the page's own getDisplayMedia() capture stream.
    ///
    /// When web content uses getDisplayMedia() to capture screen content,
    /// this enables or mutes audio in that capture stream.
    ///
    /// - Parameters:
    ///   - enabled: Whether audio should be included in the capture stream.
    ///   - completion: Called when the state change is complete.
    ///
    /// ## Important
    /// This does NOT enable audio capture by external apps (Zoom, Discord, etc.).
    /// WKWebView audio is fundamentally not capturable by ScreenCaptureKit.
    
    @available(macOS 13.0, *)
    func setWebContentCaptureAudioEnabled(_ enabled: Bool, completion: (@Sendable () -> Void)? = nil) {
        let state: WKDisplayCaptureState = enabled ? .active : .muted
        _setDisplayCaptureState(state, completionHandler: completion)
    }

    // MARK: - Media Mute State

    /// Whether capture devices (camera/microphone) are muted.
    ///
    /// When true, getUserMedia() streams send no data while still appearing active.
    
    var areCaptureDevicesMuted: Bool {
        (_mediaMutedState.rawValue & _WKMediaMutedState.captureDevicesMuted.rawValue) != 0
    }

    /// Whether web content's screen capture audio is muted.
    ///
    /// When true, the page's getDisplayMedia() streams have muted audio tracks.
    /// This does NOT affect external screen capture.
    
    var isWebContentCaptureAudioMuted: Bool {
        (_mediaMutedState.rawValue & _WKMediaMutedState.screenCaptureMuted.rawValue) != 0
    }

    /// Unmutes audio in web content's own getDisplayMedia() capture.
    ///
    /// Removes the screen capture mute flag, enabling audio in the page's
    /// capture streams.
    ///
    /// ## Important
    /// This does NOT enable external apps to capture WKWebView audio.
    /// That's a fundamental WebKit architecture limitation.
    
    func unmuteWebContentCapture() {
        // Remove the screen capture mute flag, preserving other flags
        let newState = _WKMediaMutedState(
            rawValue: _mediaMutedState.rawValue & ~_WKMediaMutedState.screenCaptureMuted.rawValue,
        )
        _setPageMuted(newState)
    }
}
