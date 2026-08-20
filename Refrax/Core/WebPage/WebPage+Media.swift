import Foundation
import WebKit

extension WebPage {
    /// Pauses playback of all media in the page.
    func pauseAllMediaPlayback() async {
        await backingWebView.pauseAllMediaPlayback()
    }

    /// Determines the playback status of media in the page.
    func mediaPlaybackState() async -> WKMediaPlaybackState {
        await backingWebView.requestMediaPlaybackState()
    }

    /// Refreshes the cached playback state.
    ///
    /// Call this to update `cachedPlaybackState` which reflects actual media
    /// playback status (playing/paused/suspended) regardless of mute state.
    /// This is more accurate than `isPlayingAudio` which only reflects audio output.
    func refreshPlaybackState() async {
        let state = await mediaPlaybackState()
        updateCachedPlaybackState(state)
    }

    /// Whether media is actually playing (regardless of mute state).
    ///
    /// Unlike `isPlayingAudio` which returns false when audio is muted (even from
    /// the webpage's own controls), this returns true if the media element is
    /// actively playing content.
    ///
    /// - Note: Call `refreshPlaybackState()` to update this value.
    var isMediaPlaying: Bool {
        cachedPlaybackState == .playing
    }

    /// Changes whether the page suspends media playback.
    func setAllMediaPlaybackSuspended(_ suspended: Bool) async {
        await backingWebView.setAllMediaPlaybackSuspended(suspended)
    }

    /// Closes all media presentations (picture-in-picture, fullscreen).
    func closeAllMediaPresentations() async {
        await backingWebView.closeAllMediaPresentations()
    }

    /// Changes the camera capture state.
    func setCameraCaptureState(_ state: WKMediaCaptureState) async {
        await backingWebView.setCameraCaptureState(state)
    }

    /// Changes the microphone capture state.
    func setMicrophoneCaptureState(_ state: WKMediaCaptureState) async {
        await backingWebView.setMicrophoneCaptureState(state)
    }

    /// Toggles media playback suspension.
    func toggleMediaSuspension() async {
        isMediaSuspended.toggle()
        await setAllMediaPlaybackSuspended(isMediaSuspended)
    }

    /// Sets whether all media playback should be suspended.
    func setMediaSuspended(_ suspended: Bool) async {
        guard isMediaSuspended != suspended else { return }
        isMediaSuspended = suspended
        await setAllMediaPlaybackSuspended(suspended)
    }

    /// Plays the predominant media session or resumes Now Playing.
    func playPredominantMedia() async -> Bool {
        await withCheckedContinuation { continuation in
            backingWebView._playPredominantOrNowPlayingMediaSession { success in
                continuation.resume(returning: success)
            }
        }
    }

    /// Pauses the current Now Playing media session.
    func pauseNowPlayingMedia() async -> Bool {
        await withCheckedContinuation { continuation in
            backingWebView._pauseNowPlayingMediaSession { success in
                continuation.resume(returning: success)
            }
        }
    }
}

// MARK: - Media Capture Control

extension WebPage {
    /// Toggles the microphone capture state between active and muted.
    func toggleMicrophoneMute() async {
        let newState: WKMediaCaptureState = isMicrophoneActive ? .muted : .active
        await setMicrophoneCaptureState(newState)
    }

    /// Sets the microphone capture state.
    func setMicrophoneMuted(_ muted: Bool) async {
        let newState: WKMediaCaptureState = muted ? .muted : .active
        await setMicrophoneCaptureState(newState)
    }

    /// Toggles the camera capture state between active and muted.
    func toggleCameraMute() async {
        let newState: WKMediaCaptureState = isCameraActive ? .muted : .active
        await setCameraCaptureState(newState)
    }

    /// Sets the camera capture state.
    func setCameraMuted(_ muted: Bool) async {
        let newState: WKMediaCaptureState = muted ? .muted : .active
        await setCameraCaptureState(newState)
    }

    /// Mutes both camera and microphone if they are active.
    func muteAllMediaCapture() async {
        if isCameraActive {
            await setCameraCaptureState(.muted)
        }
        if isMicrophoneActive {
            await setMicrophoneCaptureState(.muted)
        }
    }

    /// Unmutes both camera and microphone if they were muted.
    func unmuteAllMediaCapture() async {
        if isCameraMuted {
            await setCameraCaptureState(.active)
        }
        if isMicrophoneMuted {
            await setMicrophoneCaptureState(.active)
        }
    }
}

// MARK: - Audio Mute Control (Private API)

extension WebPage {
    /// Mutes or unmutes the tab's audio output.
    ///
    /// ## Volume/Mute Unification
    /// - Muting sets volume slider to 0
    /// - Unmuting restores volume to 1.0
    /// - This keeps the tab speaker icon and volume slider in sync
    func setAudioMuted(_ muted: Bool) {
        backingWebView.setAudioMuted(muted)
        refreshAudioMuteState()

        if muted {
            // Set volume to 0 so slider reflects muted state
            volume = 0
            backingWebView._setMediaVolume(forTesting: 0)
        } else {
            // Restore volume when unmuting
            volume = 1.0
            backingWebView._setMediaVolume(forTesting: 1.0)
        }
    }

    /// Toggles the tab's audio mute state.
    ///
    /// ## Volume/Mute Unification
    /// - Muting sets volume slider to 0
    /// - Unmuting restores volume to 1.0
    func toggleAudioMute() {
        let wasMuted = isAudioMuted
        backingWebView.toggleAudioMute()
        refreshAudioMuteState()

        if wasMuted {
            // Unmuting - restore volume
            volume = 1.0
            backingWebView._setMediaVolume(forTesting: 1.0)
        } else {
            // Muting - set volume to 0
            volume = 0
            backingWebView._setMediaVolume(forTesting: 0)
        }
    }
}

// MARK: - Document Type Detection

extension WebPage {
    /// Whether the page is displaying a PDF document.
    var isDisplayingPDF: Bool {
        backingWebView._isDisplayingPDF
    }

    /// Whether the page is displaying a standalone image.
    var isDisplayingStandaloneImage: Bool {
        backingWebView._isDisplayingStandaloneImageDocument
    }
}

// MARK: - In-Window Video Viewer

extension WebPage {
    /// Whether the in-window video viewer can be toggled right now.
    ///
    /// Advisory only: WebKit backs this with the playback-controls manager's
    /// PiP capability, so it can be `false` while `enterInWindowVideo()` still
    /// succeeds. Check `isInWindowVideoActive` after entering instead.
    var canToggleInWindowVideo: Bool {
        backingWebView._canToggleInWindow
    }

    /// Whether the in-window video viewer is currently active.
    var isInWindowVideoActive: Bool {
        backingWebView._isInWindowActive
    }

    /// Toggles the in-window video viewer.
    func toggleInWindowVideo() {
        backingWebView._toggleInWindow()
    }

    /// Enters in-window video viewer mode.
    func enterInWindowVideo() {
        backingWebView._enterInWindow()
    }

    /// Exits in-window video viewer mode.
    func exitInWindowVideo() {
        backingWebView._exitInWindow()
    }
}

// MARK: - Call Detection

extension WebPage {
    /// Whether this tab is currently in a call.
    ///
    /// Determined by:
    /// 1. User manually marked the tab as a call (`userMarkedAsCall`), OR
    /// 2. Domain is a known call domain AND mic or camera is active
    ///
    /// - Parameter registry: The call domain registry to check against.
    /// - Returns: `true` if the tab is in a call.
    func isInCall(using registry: CallDomainRegistry) -> Bool {
        if userMarkedAsCall {
            return true
        }

        guard let host = url?.host else { return false }

        let isCallDomain = registry.isCallDomain(host)
        let hasActiveCaptureForCall = isMicrophoneActive || isCameraActive || isMicrophoneMuted || isCameraMuted

        return isCallDomain && hasActiveCaptureForCall
    }

    /// Whether this page has any media-related activity (audio, video, or call).
    var hasMediaActivity: Bool {
        isPlayingAudio || hasActiveMediaCapture || hasMutedMediaCapture || isMediaSuspended
    }
}

// MARK: - Volume Control

extension WebPage {
    /// Sets the volume for all media elements in the page.
    ///
    /// Uses WebKit's native page-level volume multiplier API. The effective volume
    /// of each element is: `element.volume × pageMediaVolume`.
    ///
    /// ## Volume/Mute Unification
    /// - Setting volume to 0 also mutes the tab
    /// - Setting volume above 0 unmutes (if tab was auto-muted due to volume=0)
    /// - This keeps the tab speaker icon and volume slider in sync
    ///
    /// ## Advantages over JavaScript
    /// - Works on cross-origin iframes
    /// - Automatically applies to dynamically created elements
    /// - No JavaScript evaluation overhead
    ///
    /// - Note: Web Audio API sources cannot be controlled via this method.
    ///   For sites using only Web Audio (rare), use `setAudioMuted(_:)` instead.
    ///
    /// - Parameter newVolume: Volume level from 0.0 (silent) to 1.0 (full).
    func setVolume(_ newVolume: Double) {
        let clampedVolume = max(0.0, min(1.0, newVolume))
        volume = clampedVolume

        // Use native WebKit API for page-level volume multiplier
        backingWebView._setMediaVolume(forTesting: Float(clampedVolume))

        // Unify with mute state: volume 0 = muted, volume > 0 = unmuted
        if clampedVolume == 0 {
            if !isAudioMuted {
                backingWebView.setAudioMuted(true)
                refreshAudioMuteState()
            }
        } else {
            // Unmute if currently muted (user moved slider above 0)
            if isAudioMuted {
                backingWebView.setAudioMuted(false)
                refreshAudioMuteState()
            }
        }
    }

    /// Updates the last media activity timestamp.
    ///
    /// Called when media starts playing or capture becomes active.
    func updateMediaActivity() {
        lastMediaActivity = Date()
    }
}

// MARK: - Media Session Metadata

/// Metadata from the Media Session API.
///
/// Websites can provide rich media information through `navigator.mediaSession.metadata`,
/// including title, artist, album, and artwork. This struct captures that data.
struct MediaSessionMetadata: Sendable, Equatable {
    /// The title of the currently playing media.
    let title: String?

    /// The artist name.
    let artist: String?

    /// The album name.
    let album: String?

    /// URL to the artwork image.
    let artworkURL: URL?

    /// Whether this metadata has any meaningful content.
    var hasContent: Bool {
        title != nil || artist != nil || artworkURL != nil
    }
}

extension WebPage {
    /// Fetches Media Session metadata from the page via JavaScript.
    ///
    /// The Media Session API (`navigator.mediaSession.metadata`) allows websites
    /// to provide rich media information for system media controls. This method
    /// extracts that data and caches it in `mediaSessionMetadata`.
    ///
    /// - Returns: The fetched metadata, or `nil` if unavailable.
    @discardableResult
    func refreshMediaSessionMetadata() async -> MediaSessionMetadata? {
        do {
            let result = try await backingWebView.evaluateJavaScript(
                JavaScriptSnippets.mediaSessionMetadata,
            )

            guard let jsonString = result as? String,
                  let data = jsonString.data(using: .utf8) else {
                mediaSessionMetadata = nil
                return nil
            }

            struct MetadataJSON: Decodable {
                let title: String?
                let artist: String?
                let album: String?
                let artworkURL: String?
            }

            let decoded = try JSONDecoder().decode(MetadataJSON.self, from: data)
            let metadata = MediaSessionMetadata(
                title: decoded.title,
                artist: decoded.artist,
                album: decoded.album,
                artworkURL: decoded.artworkURL.flatMap { URL(string: $0) },
            )

            mediaSessionMetadata = metadata
            return metadata
        } catch {
            mediaSessionMetadata = nil
            return nil
        }
    }
}
