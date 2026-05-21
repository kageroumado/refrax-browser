/**
 * WKWebViewPrivate+Media.h
 * Refrax Browser
 *
 * Private WebKit APIs for media playback and capture control.
 *
 * This header provides comprehensive media management capabilities:
 * - Audio playback state observation and muting
 * - Media capture (camera, microphone, screen) control
 * - Picture-in-Picture management
 * - In-window video viewer (Safari-style)
 * - Media session control (Now Playing integration)
 * - Fullscreen management
 *
 * ## Important: Scope of Capture APIs
 *
 * The display/screen capture APIs in this header control **web content's own
 * getDisplayMedia() capture sessions** - i.e., when JavaScript on a page calls
 * `navigator.mediaDevices.getDisplayMedia()` to capture screen/window content.
 *
 * These APIs do **NOT** affect external apps capturing the browser window
 * (e.g., Zoom, Discord, ScreenCaptureKit-based apps). That's a separate issue:
 *
 * - WKWebView runs audio in a separate process (WebContent/GPU process)
 * - This audio uses its own AVAudioSession, not the main app's
 * - ScreenCaptureKit captures audio at the app level, missing WKWebView audio
 * - This is a known WebKit limitation (see Apple Developer Forums thread 670482)
 *
 * ## KVO Compliance
 * Properties marked as KVO-compliant can be observed using standard NSKeyValueObserving:
 * - `_isPlayingAudio`
 * - `_mediaMutedState`
 * - `_displayCaptureState`
 * - `_systemAudioCaptureState`
 *
 * ## Thread Safety
 * All APIs must be called on the main thread.
 *
 * ## Source Reference
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebViewPrivate.h
 *
 * Last verified: WebKit trunk (January 2025)
 */

#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Media Mute State

/**
 * Media mute state flags for WKWebView.
 *
 * These flags control which types of media are muted in the web view.
 * Multiple flags can be combined using bitwise OR.
 *
 * ## Usage
 * @code
 * // Mute audio playback only
 * [webView _setPageMuted:_WKMediaAudioMuted];
 *
 * // Mute audio and capture devices
 * [webView _setPageMuted:_WKMediaAudioMuted | _WKMediaCaptureDevicesMuted];
 *
 * // Unmute everything
 * [webView _setPageMuted:_WKMediaNoneMuted];
 * @endcode
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebViewPrivate.h
 *
 * ## Availability
 * macOS 10.13+, iOS 11.0+
 */
typedef NS_OPTIONS(NSUInteger, _WKMediaMutedState) {
    /** No media is muted - all audio is allowed. */
    _WKMediaNoneMuted = 0,

    /**
     * Audio playback is muted.
     *
     * Affects `<audio>` and `<video>` element playback.
     * Video continues playing; only audio output is silenced.
     */
    _WKMediaAudioMuted = 1 << 0,

    /**
     * Capture devices (microphone, camera) are muted.
     *
     * Affects getUserMedia() streams. The page still believes capture is active,
     * but no data is sent. Use this to implement a global mute without revoking
     * permissions.
     */
    _WKMediaCaptureDevicesMuted = 1 << 1,

    /**
     * Screen capture audio is muted (for web content's own getDisplayMedia()).
     *
     * When set, audio tracks in the page's getDisplayMedia() streams are muted.
     * This controls what audio the *web page* captures when it uses the Screen
     * Capture API - NOT what external apps capture when screen sharing the browser.
     *
     * Internally maps to three WebCore flags:
     * - ScreenCaptureIsMuted
     * - WindowCaptureIsMuted
     * - SystemAudioCaptureIsMuted
     *
     * ## Important
     * This flag does NOT affect ScreenCaptureKit/ReplayKit audio capture by
     * external applications. WKWebView audio runs in a separate process and
     * is not capturable by external apps regardless of this flag's state.
     */
    _WKMediaScreenCaptureMuted = 1 << 2,
} API_AVAILABLE(macos(10.13), ios(11.0));

#pragma mark - Display Capture State

/**
 * Display capture state for web content's getDisplayMedia() sessions.
 *
 * Represents whether the page is currently capturing screen/window content
 * via the JavaScript getDisplayMedia() API, and whether audio is included.
 *
 * ## Important Distinction
 * This tracks the page's OWN capture sessions (when web content captures
 * something). It does NOT indicate whether external apps are capturing
 * the browser window.
 *
 * ## Implementation Details
 * - `_displayCaptureState` reads from `_page->reportedMediaState()`
 * - `_setDisplayCaptureState:` modifies `_page->mutedStateFlags()` and calls `setMuted()`
 * - Setting to `.active` removes ScreenCaptureIsMuted and WindowCaptureIsMuted
 * - Setting to `.muted` adds those flags back
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebViewPrivate.h
 *
 * ## Availability
 * macOS 13.0+, iOS 16.0+
 */
typedef NS_ENUM(NSInteger, WKDisplayCaptureState) {
    /** No getDisplayMedia() capture is active on this page. */
    WKDisplayCaptureStateNone,

    /** Page is capturing screen/window with audio enabled. */
    WKDisplayCaptureStateActive,

    /** Page is capturing screen/window but audio is muted. */
    WKDisplayCaptureStateMuted,
} API_AVAILABLE(macos(13.0), ios(16.0));

#pragma mark - System Audio Capture State

/**
 * System audio capture state for web content's audio capture.
 *
 * Represents whether the page is capturing system audio (e.g., via
 * getDisplayMedia() with audio:true for system audio, or future APIs
 * that allow web content to capture system audio output).
 *
 * ## Implementation Details
 * - Tracks `HasActiveSystemAudioCaptureDevice` / `HasMutedSystemAudioCaptureDevice`
 *   flags in the page's media state
 * - `_setSystemAudioCaptureState:` modifies `WindowCaptureIsMuted` flag
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebViewPrivate.h
 *
 * ## Availability
 * macOS 13.0+, iOS 16.0+
 */
typedef NS_ENUM(NSInteger, WKSystemAudioCaptureState) {
    /** Page is not capturing system audio. */
    WKSystemAudioCaptureStateNone,

    /** Page is capturing system audio and streaming it. */
    WKSystemAudioCaptureStateActive,

    /** Page is capturing system audio but it's muted. */
    WKSystemAudioCaptureStateMuted,
} API_AVAILABLE(macos(13.0), ios(16.0));

#pragma mark - Display Capture Surfaces

/**
 * Types of display surfaces being captured.
 *
 * Used to identify what kind of content is being shared via getDisplayMedia().
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebViewPrivate.h
 *
 * ## Availability
 * macOS 13.0+, iOS 16.0+
 */
typedef NS_OPTIONS(NSUInteger, WKDisplayCaptureSurfaces) {
    /** No display capture is active. */
    WKDisplayCaptureSurfaceNone = 0,

    /** Entire screen is being captured. */
    WKDisplayCaptureSurfaceScreen = 1 << 0,

    /** A specific window is being captured. */
    WKDisplayCaptureSurfaceWindow = 1 << 1,
} API_AVAILABLE(macos(13.0), ios(16.0));

#pragma mark - Capture Devices

/**
 * Capture device types for permission requests.
 *
 * Used with media capture permission delegate methods.
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebViewPrivate.h
 *
 * ## Availability
 * macOS 10.13+, iOS 11.0+
 */
typedef NS_OPTIONS(NSUInteger, _WKCaptureDevices) {
    /** Microphone access requested. */
    _WKCaptureDeviceMicrophone = 1 << 0,

    /** Camera access requested. */
    _WKCaptureDeviceCamera = 1 << 1,

    /** Display/screen capture access requested. */
    _WKCaptureDeviceDisplay = 1 << 2,
} API_AVAILABLE(macos(10.13), ios(11.0));

#pragma mark - Autoplay Events

/**
 * Autoplay events reported by WebKit.
 *
 * These events help track how media autoplay behaves on the page,
 * useful for implementing autoplay UI and policies.
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKUIDelegatePrivate.h
 *
 * ## Availability
 * macOS 10.13.4+, iOS 11.3+
 */
typedef NS_ENUM(NSInteger, _WKAutoplayEvent) {
    /** Media was prevented from autoplaying due to policy. */
    _WKAutoplayEventDidPreventFromAutoplaying,

    /** Media started playing with user gesture (click/tap). */
    _WKAutoplayEventDidPlayMediaWithUserGesture,

    /** Media autoplayed past a threshold without user interference. */
    _WKAutoplayEventDidAutoplayMediaPastThresholdWithoutUserInterference,

    /** User interacted with playback (pause, seek, etc.). */
    _WKAutoplayEventUserDidInterfereWithPlayback,
} API_AVAILABLE(macos(10.13.4), ios(11.3));

/**
 * Flags providing additional context for autoplay events.
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKUIDelegatePrivate.h
 *
 * ## Availability
 * macOS 10.13.4+, iOS 11.3+
 */
typedef NS_OPTIONS(NSUInteger, _WKAutoplayEventFlags) {
    /** No additional flags. */
    _WKAutoplayEventFlagsNone = 0,

    /** The media element has an audio track. */
    _WKAutoplayEventFlagsHasAudio = 1 << 0,

    /** Playback was prevented by autoplay policy. */
    _WKAutoplayEventFlagsPlaybackWasPrevented = 1 << 1,

    /** Media is the main content of the page. */
    _WKAutoplayEventFlagsMediaIsMainContent = 1 << 2,
} API_AVAILABLE(macos(10.13.4), ios(11.3));

#pragma mark - WKWebView Media Extensions

/**
 * Private WKWebView extensions for media control.
 */
@interface WKWebView (WKPrivateMedia)

#pragma mark - Audio State & Control

/**
 * Whether the web view is currently playing audio.
 *
 * ## KVO Compliance
 * This property is KVO-compliant. Observe changes to update audio indicators:
 *
 * @code
 * [webView addObserver:self
 *           forKeyPath:@"_isPlayingAudio"
 *              options:NSKeyValueObservingOptionNew
 *              context:nil];
 * @endcode
 *
 * ## Availability
 * macOS 10.13.4+, iOS 11.3+
 */
@property (nonatomic, readonly, getter=_isPlayingAudio) BOOL _playingAudio
    API_AVAILABLE(macos(10.13.4), ios(11.3));

/**
 * The current media mute state as a bitmask.
 *
 * Returns a combination of `_WKMediaMutedState` flags indicating which
 * media types are currently muted.
 *
 * ## KVO Compliance
 * This property is KVO-compliant.
 *
 * ## Usage
 * @code
 * _WKMediaMutedState state = webView._mediaMutedState;
 * BOOL isAudioMuted = (state & _WKMediaAudioMuted) != 0;
 * @endcode
 *
 * ## Availability
 * macOS 11.0+, iOS 14.0+
 */
@property (nonatomic, readonly) _WKMediaMutedState _mediaMutedState
    API_AVAILABLE(macos(11.0), ios(14.0));

/**
 * Sets the media mute state.
 *
 * @param mutedState A bitmask of `_WKMediaMutedState` flags.
 *
 * ## Important
 * This method does NOT trigger KVO notifications for `_mediaMutedState`.
 * If you're observing mute state changes, manually refresh your observer
 * after calling this method.
 *
 * ## Usage
 * @code
 * // Mute audio only (preserving other mute states)
 * _WKMediaMutedState current = webView._mediaMutedState;
 * [webView _setPageMuted:current | _WKMediaAudioMuted];
 *
 * // Unmute audio only
 * [webView _setPageMuted:current & ~_WKMediaAudioMuted];
 * @endcode
 *
 * ## Availability
 * macOS 10.13+, iOS 11.0+
 */
- (void)_setPageMuted:(_WKMediaMutedState)mutedState
    API_AVAILABLE(macos(10.13), ios(11.0));

#pragma mark - Display Capture Control

/**
 * The current display capture state for this page's getDisplayMedia() sessions.
 *
 * Returns whether the page is actively capturing screen/window content via
 * JavaScript getDisplayMedia() calls, and whether audio is included.
 *
 * ## KVO Compliance
 * This property is KVO-compliant. Observe to update screen sharing indicators
 * when web content starts/stops capturing.
 *
 * ## Important
 * This does NOT indicate whether external apps are capturing this browser window.
 * Use `NSWindow.hasActiveWindowSharingSession` for that (see NSWindowPrivate.h).
 *
 * ## Availability
 * macOS 13.0+, iOS 16.0+
 */
@property (nonatomic, readonly) WKDisplayCaptureState _displayCaptureState
    API_AVAILABLE(macos(13.0), ios(16.0));

/**
 * Controls audio for the page's own getDisplayMedia() capture sessions.
 *
 * When web content uses getDisplayMedia() to capture screen/window content,
 * this controls whether audio is included in that capture stream.
 *
 * @param state The desired display capture state.
 * @param completionHandler Called when the state change is complete (may be nil).
 *
 * ## Implementation
 * - Gets current mute flags via `_page->mutedStateFlags()`
 * - For `.active`: removes ScreenCaptureIsMuted and WindowCaptureIsMuted
 * - For `.muted`: adds those flags back
 * - For `.none`: stops the capture entirely via `stopMediaCapture()`
 *
 * ## Important
 * This does NOT enable audio capture by external apps (Zoom, Discord, etc.).
 * WKWebView audio runs in a separate process that ScreenCaptureKit cannot access.
 *
 * ## Usage
 * @code
 * // Enable audio in the page's screen capture stream
 * [webView _setDisplayCaptureState:WKDisplayCaptureStateActive
 *                completionHandler:nil];
 * @endcode
 *
 * ## Availability
 * macOS 13.0+, iOS 16.0+
 */
- (void)_setDisplayCaptureState:(WKDisplayCaptureState)state
              completionHandler:(nullable void (^)(void))completionHandler
    API_AVAILABLE(macos(13.0), ios(16.0));

/**
 * The types of display surfaces currently being captured.
 *
 * ## KVO Compliance
 * This property is KVO-compliant.
 *
 * ## Availability
 * macOS 13.0+, iOS 16.0+
 */
@property (nonatomic, readonly) WKDisplayCaptureSurfaces _displayCaptureSurfaces
    API_AVAILABLE(macos(13.0), ios(16.0));

#pragma mark - System Audio Capture

/**
 * The current system audio capture state.
 *
 * ## KVO Compliance
 * This property is KVO-compliant.
 *
 * ## Availability
 * macOS 13.0+, iOS 16.0+
 */
@property (nonatomic, readonly) WKSystemAudioCaptureState _systemAudioCaptureState
    API_AVAILABLE(macos(13.0), ios(16.0));

/**
 * Sets the system audio capture state.
 *
 * @param state The desired system audio capture state.
 * @param completionHandler Called when the state change is complete (may be nil).
 *
 * ## Availability
 * macOS 13.0+, iOS 16.0+
 */
- (void)_setSystemAudioCaptureState:(WKSystemAudioCaptureState)state
                  completionHandler:(nullable void (^)(void))completionHandler
    API_AVAILABLE(macos(13.0), ios(16.0));

#pragma mark - Media Capture Control

/**
 * Whether media capture (camera, microphone) is enabled.
 *
 * When NO, getUserMedia() requests will be denied.
 *
 * ## Availability
 * macOS 10.13+, iOS 11.0+
 */
@property (nonatomic, setter=_setMediaCaptureEnabled:) BOOL _mediaCaptureEnabled
    API_AVAILABLE(macos(10.13), ios(11.0));

/**
 * Stops all active media capture (camera, microphone, screen).
 *
 * This immediately terminates all capture sessions without user interaction.
 *
 * ## Availability
 * macOS 10.15.4+, iOS 13.4+
 */
- (void)_stopMediaCapture
    API_AVAILABLE(macos(10.15.4), ios(13.4));

#pragma mark - Picture-in-Picture

/**
 * Whether Picture-in-Picture mode can be toggled.
 *
 * Check this before enabling PiP UI elements.
 */
@property (nonatomic, readonly) BOOL _canTogglePictureInPicture;

/**
 * Whether Picture-in-Picture is currently active.
 */
@property (nonatomic, readonly) BOOL _isPictureInPictureActive;

/**
 * Toggles Picture-in-Picture mode for the current video.
 *
 * If PiP is active, exits PiP. If not active, enters PiP for the
 * predominant video element.
 */
- (void)_togglePictureInPicture;

#pragma mark - In-Window Video Viewer

/**
 * Whether the in-window video viewer is currently active.
 *
 * The in-window viewer is Safari's alternative to true fullscreen,
 * where video fills the web view area but browser chrome remains visible.
 */
@property (nonatomic, readonly) BOOL _isInWindowActive;

/**
 * Toggles the in-window video viewer.
 *
 * If a video is playing, switches between normal and in-window mode.
 */
- (void)_toggleInWindow;

/**
 * Enters in-window video viewer mode.
 *
 * Expands the current video to fill the web view while keeping
 * browser chrome visible. Unlike true fullscreen, this:
 * - Doesn't hide the dock/menu bar
 * - Doesn't create a separate fullscreen space
 * - Allows tab switching while video plays
 */
- (void)_enterInWindow;

/**
 * Exits in-window video viewer mode.
 *
 * Returns the video to its original inline position.
 */
- (void)_exitInWindow;

#pragma mark - Fullscreen

/**
 * Whether the web view is currently in fullscreen mode.
 *
 * ## Availability
 * macOS 10.12.4+, iOS 10.3+
 */
@property (nonatomic, readonly) BOOL _isInFullscreen
    API_AVAILABLE(macos(10.12.4), ios(10.3));

/**
 * Whether the web view can enter fullscreen mode.
 *
 * ## Availability
 * macOS 15.0+, iOS 18.0+
 */
@property (nonatomic, readonly) BOOL _canEnterFullscreen
    API_AVAILABLE(macos(15.0), ios(18.0));

/**
 * Programmatically enters fullscreen mode.
 *
 * ## Availability
 * macOS 15.0+, iOS 18.0+
 */
- (void)_enterFullscreen
    API_AVAILABLE(macos(15.0), ios(18.0));

#pragma mark - Media Playback Control

/**
 * Stops all media playback in the web view.
 *
 * This is a hard stop - media cannot be resumed after this call.
 */
- (void)_stopAllMediaPlayback;

/**
 * Suspends all media playback (can be resumed).
 *
 * Media can be resumed later with `_resumeAllMediaPlayback`.
 */
- (void)_suspendAllMediaPlayback;

/**
 * Resumes all previously suspended media playback.
 */
- (void)_resumeAllMediaPlayback;

/**
 * Closes all media presentations (PiP, fullscreen video, etc.).
 */
- (void)_closeAllMediaPresentations;

#pragma mark - Media Session Control

/**
 * Plays the predominant media session or resumes Now Playing.
 *
 * This is the programmatic equivalent of pressing play:
 * 1. Resumes paused media if any
 * 2. Starts the predominant video/audio if multiple exist
 * 3. Activates Now Playing if registered
 *
 * @param completionHandler Called with YES if playback started successfully.
 *
 * ## Availability
 * macOS 15.0+, iOS 18.0+
 */
- (void)_playPredominantOrNowPlayingMediaSession:(void(^)(BOOL success))completionHandler
    API_AVAILABLE(macos(15.0), ios(18.0));

/**
 * Pauses the current Now Playing media session.
 *
 * @param completionHandler Called with YES if playback was paused.
 *
 * ## Availability
 * macOS 15.0+, iOS 18.0+
 */
- (void)_pauseNowPlayingMediaSession:(void(^)(BOOL success))completionHandler
    API_AVAILABLE(macos(15.0), ios(18.0));

/**
 * Gets the title and artist of the currently playing media.
 *
 * @param completionHandler Called with title and artist strings (may be nil).
 *
 * ## Usage
 * Display Now Playing information:
 * @code
 * [webView _nowPlayingMediaTitleAndArtist:^(NSString *title, NSString *artist) {
 *     if (title) {
 *         self.nowPlayingLabel.text = [NSString stringWithFormat:@"%@ - %@", title, artist ?: @"Unknown"];
 *     }
 * }];
 * @endcode
 */
- (void)_nowPlayingMediaTitleAndArtist:(void (^)(NSString * _Nullable title,
                                                  NSString * _Nullable artist))completionHandler;

#pragma mark - Animation Control

/**
 * Pauses all CSS animations and GIF animations on the page.
 *
 * @param completionHandler Called when animations are paused.
 *
 * ## Availability
 * macOS 13.3+, iOS 16.4+
 */
- (void)_pauseAllAnimationsWithCompletionHandler:(void(^)(void))completionHandler
    API_AVAILABLE(macos(13.3), ios(16.4));

/**
 * Resumes all paused animations.
 *
 * @param completionHandler Called when animations are resumed.
 *
 * ## Availability
 * macOS 13.3+, iOS 16.4+
 */
- (void)_playAllAnimationsWithCompletionHandler:(void(^)(void))completionHandler
    API_AVAILABLE(macos(13.3), ios(16.4));

/**
 * Whether any animations are currently playing.
 *
 * ## Availability
 * macOS 13.3+, iOS 16.4+
 */
@property (nonatomic, readonly) BOOL _allowsAnyAnimationToPlay
    API_AVAILABLE(macos(13.3), ios(16.4));

#pragma mark - Media Volume Control

/**
 * Sets the page-level media volume multiplier.
 *
 * This sets a volume multiplier that applies to ALL media elements on the page.
 * The effective volume of each element is: `element.volume × pageMediaVolume`.
 *
 * @param volume Volume multiplier from 0.0 (silent) to 1.0 (full volume).
 *
 * ## Behavior
 * - Applies to all `<audio>` and `<video>` elements, including cross-origin iframes
 * - Automatically affects dynamically created elements
 * - Does NOT affect Web Audio API sources
 * - Persists across the page's lifetime
 *
 * ## Note
 * Despite the "ForTesting" suffix, this is a production-ready API that calls
 * the same `WebPageProxy::setMediaVolume()` used internally by WebKit.
 *
 * ## Usage
 * @code
 * // Set volume to 50%
 * [webView _setMediaVolumeForTesting:0.5f];
 *
 * // Mute all media (alternative to _setPageMuted:)
 * [webView _setMediaVolumeForTesting:0.0f];
 * @endcode
 *
 * ## Availability
 * macOS 10.12+, iOS 10.0+
 */
- (void)_setMediaVolumeForTesting:(float)volume;

@end

NS_ASSUME_NONNULL_END
