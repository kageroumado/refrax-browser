import Foundation

/// A tab's live media, capture and process state, consolidated across its pages in one pass.
///
/// Activity flags are the OR of the pages; muted states are the AND. Read it inside a view's
/// body so observation tracks the underlying `@Observable` page properties.
nonisolated struct TabMediaState {
    /// One page that plays sound while it captures the microphone or camera: a call.
    ///
    /// A call is a property of a single page; sound on one page and capture on another is not one.
    nonisolated struct CallPage {
        let pageIndex: Int
        let hasAudio: Bool
        let isAudioMuted: Bool
        let hasMic: Bool
        let isMicMuted: Bool
        let hasCamera: Bool
        let isCameraMuted: Bool
    }

    var isPlayingAudio = false
    /// Every page that plays sound is muted.
    var isAudioMuted = false
    /// Every live page is muted, whether or not it plays sound now.
    var isTabMuted = false
    var isInFullscreen = false
    var isMediaSuspended = false
    var isCameraActive = false
    /// The camera was muted and nothing has turned it back on.
    var isCameraMuted = false
    var isMicrophoneActive = false
    /// The microphone was muted and nothing has turned it back on.
    var isMicrophoneMuted = false
    var needsReload = false
    var isUnresponsive = false
    var recentlyCrashed = false
    var hasReflectedWindows = false
    var isLoading = false
    var callPages: [CallPage] = []

    @MainActor
    init(pages: [WebPage]) {
        guard !pages.isEmpty else { return }
        var allPlayingMuted = true
        var allMuted = true
        var cameraMuted = false
        var micMuted = false
        for (index, page) in pages.enumerated() {
            let audio = page.audioState
            let hasMic = page.isMicrophoneActive || page.isMicrophoneMuted
            let hasCamera = page.isCameraActive || page.isCameraMuted
            self.isPlayingAudio = isPlayingAudio || audio.isPlayingAudio
            allPlayingMuted = allPlayingMuted && audio.isMuted
            allMuted = allMuted && page.isAudioMuted
            self.isInFullscreen = isInFullscreen || page.isInFullscreen
            self.isMediaSuspended = isMediaSuspended || page.isMediaSuspended
            self.isCameraActive = isCameraActive || page.isCameraActive
            cameraMuted = cameraMuted || page.isCameraMuted
            self.isMicrophoneActive = isMicrophoneActive || page.isMicrophoneActive
            micMuted = micMuted || page.isMicrophoneMuted
            self.needsReload = needsReload || page.needsReload
            self.isUnresponsive = isUnresponsive || page.isUnresponsive
            self.recentlyCrashed = recentlyCrashed || page.recentlyCrashed
            self.hasReflectedWindows = hasReflectedWindows || page.hasReflectedWindows
            self.isLoading = isLoading || page.isLoading
            if audio.isPlayingAudio, hasMic || hasCamera {
                callPages.append(CallPage(
                    pageIndex: index,
                    hasAudio: true,
                    isAudioMuted: audio.isMuted,
                    hasMic: hasMic,
                    isMicMuted: page.isMicrophoneMuted,
                    hasCamera: hasCamera,
                    isCameraMuted: page.isCameraMuted,
                ))
            }
        }
        self.isAudioMuted = allPlayingMuted
        self.isTabMuted = allMuted
        self.isCameraMuted = !isCameraActive && cameraMuted
        self.isMicrophoneMuted = !isMicrophoneActive && micMuted
    }

    var isInCall: Bool {
        !callPages.isEmpty
    }

    var hasCamera: Bool {
        isCameraActive || isCameraMuted
    }

    var hasMicrophone: Bool {
        isMicrophoneActive || isMicrophoneMuted
    }

    /// Every page in the call has muted its sound.
    var isCallAudioMuted: Bool {
        callPages.allSatisfy(\.isAudioMuted)
    }

    /// The tab's pages were unloaded to save memory and wait to be woken. A page that is still
    /// being created also reports `needsReload`, so a tab younger than half a second never counts.
    func isSuspended(createdAt: Date, now: Date = .now) -> Bool {
        needsReload && !isLoading && now.timeIntervalSince(createdAt) > Self.suspensionSettle
    }

    static let suspensionSettle: TimeInterval = 0.5
}
