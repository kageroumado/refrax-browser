import WebKit

// MARK: - Audio State

extension WKWebView {
    /// Audio playback and mute state for a web view.
    enum AudioState: Equatable, Sendable {
        /// No audio is currently playing.
        case idle

        /// Audio is playing and audible.
        case playing

        /// Audio is playing but muted.
        case muted

        /// Whether audio is currently playing (muted or unmuted).
        var isPlayingAudio: Bool {
            self != .idle
        }

        /// Whether audio output is muted.
        var isMuted: Bool {
            self == .muted
        }
    }
}

// MARK: - Audio State Access

extension WKWebView {
    /// Whether the web view is currently playing audio.
    ///
    /// This is a Swift-friendly wrapper around the private `_isPlayingAudio` property,
    /// now properly declared in `WKWebViewPrivate+Media.h`.
    ///
    /// - Note: This property is KVO-observable via `_isPlayingAudio`.
    @objc dynamic var isPlayingAudio: Bool {
        // Use the header-declared property directly (getter is _isPlayingAudio)
        _isPlayingAudio
    }

    /// Whether the web view's audio output is muted.
    ///
    /// Uses the `_mediaMutedState` property declared in `WKWebViewPrivate+Media.h`.
    ///
    /// - Note: This property is KVO-observable.
    @objc dynamic var isAudioMuted: Bool {
        (_mediaMutedState.rawValue & _WKMediaMutedState.audioMuted.rawValue) != 0
    }

    /// The current audio state combining playback and mute status.
    var audioState: AudioState {
        guard isPlayingAudio else {
            return .idle
        }
        return isAudioMuted ? .muted : .playing
    }

    /// Sets whether the web view's audio output is muted.
    ///
    /// Uses the `_setPageMuted:` method declared in `WKWebViewPrivate+Media.h`.
    /// Unlike pausing media, muting silences audio while allowing video to continue playing.
    ///
    /// - Parameter muted: Whether to mute audio output.
    ///
    /// - Important: This method does NOT trigger KVO notifications for `_mediaMutedState`.
    ///   Call your observer's `refresh()` method after setting.
    func setAudioMuted(_ muted: Bool) {
        // Calculate the new state, preserving other mute flags
        var currentState = _mediaMutedState
        if muted {
            currentState = _WKMediaMutedState(rawValue: currentState.rawValue | _WKMediaMutedState.audioMuted.rawValue)
        } else {
            currentState = _WKMediaMutedState(rawValue: currentState.rawValue & ~_WKMediaMutedState.audioMuted.rawValue)
        }

        // Use the header-declared method directly
        _setPageMuted(currentState)
    }

    /// Toggles the audio mute state.
    func toggleAudioMute() {
        setAudioMuted(!isAudioMuted)
    }
}

// MARK: - KVO Support

extension WKWebView {
    /// Key paths that affect `isPlayingAudio` for KVO dependency.
    @objc
    class func keyPathsForValuesAffectingIsPlayingAudio() -> Set<String> {
        ["_isPlayingAudio"]
    }

    /// Key paths that affect `isAudioMuted` for KVO dependency.
    @objc
    class func keyPathsForValuesAffectingIsAudioMuted() -> Set<String> {
        ["_mediaMutedState"]
    }
}
