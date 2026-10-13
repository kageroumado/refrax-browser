import Foundation

/// One piece of a tab's live state that is shown on the tab itself, with the action a click takes.
nonisolated enum TabStateSymbol: Hashable, Identifiable {
    /// A page plays sound while it captures: the call's sound, muted or not. Click mutes it.
    case call(isMuted: Bool)
    /// The camera, or the microphone when the camera is off, in use or muted. Click toggles it.
    case capture(Capture)
    /// Sound plays, or the tab is muted. Click mutes or unmutes; ⌥-click pauses.
    case audio(isMuted: Bool)
    /// The page crashed or stopped responding. Click reloads.
    case crashed
    /// The page was unloaded to save memory. Click wakes it.
    case suspended
    /// The tab changed while unseen. Click marks it read.
    case unread

    nonisolated enum Capture: Hashable {
        case camera(isMuted: Bool)
        case microphone(isMuted: Bool)
    }

    /// The most symbols a tab carries; more would crowd the title.
    static let maximumCount = 2

    var id: String {
        switch self {
        case .call: "call"
        case .capture: "capture"
        case .audio: "audio"
        case .crashed: "crashed"
        case .suspended: "suspended"
        case .unread: "unread"
        }
    }

    /// The symbols a tab shows, in priority order: call, capture, sound, crash, suspension,
    /// unread. Sound inside a call is the call's own.
    static func symbols(
        for state: TabMediaState, isSuspended: Bool, isUnread: Bool,
    ) -> [Self] {
        symbols(
            call: state.isInCall ? state.isCallAudioMuted : nil,
            capture: capture(for: state),
            audio: !state.isInCall && (state.isPlayingAudio || state.isTabMuted) ? (state.isTabMuted || state.isAudioMuted) : nil,
            isCrashed: state.recentlyCrashed || state.isUnresponsive,
            isSuspended: isSuspended,
            isUnread: isUnread,
        )
    }

    /// The priority rule on its own: `nil` means the state is absent.
    static func symbols(
        call: Bool?, capture: Capture?, audio: Bool?, isCrashed: Bool, isSuspended: Bool, isUnread: Bool,
    ) -> [Self] {
        var symbols: [Self] = []
        if let call {
            symbols.append(.call(isMuted: call))
        }
        if let capture {
            symbols.append(.capture(capture))
        }
        if let audio {
            symbols.append(.audio(isMuted: audio))
        }
        if isCrashed {
            symbols.append(.crashed)
        }
        if isSuspended {
            symbols.append(.suspended)
        }
        if isUnread {
            symbols.append(.unread)
        }
        return Array(symbols.prefix(maximumCount))
    }

    private static func capture(for state: TabMediaState) -> Capture? {
        if state.hasCamera {
            return .camera(isMuted: !state.isCameraActive)
        }
        if state.hasMicrophone {
            return .microphone(isMuted: !state.isMicrophoneActive)
        }
        return nil
    }

    /// The SF Symbol; `optionIsDown` turns playing sound into the pause it offers.
    func systemImage(optionIsDown: Bool = false) -> String {
        switch self {
        case let .call(isMuted): isMuted ? "speaker.slash.fill" : "phone.fill"
        case .capture(.camera(isMuted: false)): "video.fill"
        case .capture(.camera(isMuted: true)): "video.slash.fill"
        case .capture(.microphone(isMuted: false)): "mic.fill"
        case .capture(.microphone(isMuted: true)): "mic.slash.fill"
        case .audio(isMuted: false): optionIsDown ? "pause.fill" : "speaker.wave.2.fill"
        case .audio(isMuted: true): "speaker.slash.fill"
        case .crashed: "exclamationmark.triangle.fill"
        case .suspended: "moon.zzz.fill"
        case .unread: "circlebadge.fill"
        }
    }

    /// What the symbol says the tab is doing.
    var label: String {
        switch self {
        case let .call(isMuted): isMuted ? "In a call, sound muted" : "In a call"
        case .capture(.camera(isMuted: false)): "Camera in use"
        case .capture(.camera(isMuted: true)): "Camera off"
        case .capture(.microphone(isMuted: false)): "Microphone in use"
        case .capture(.microphone(isMuted: true)): "Microphone muted"
        case .audio(isMuted: false): "Playing sound"
        case .audio(isMuted: true): "Muted"
        case .crashed: "Page stopped working"
        case .suspended: "Suspended"
        case .unread: "Unread"
        }
    }

    /// The tooltip: the action, then the key. Keys act on the current tab, so only its symbols name them.
    func help(optionIsDown: Bool = false, isCurrentTab: Bool = false) -> String {
        let muteKey = isCurrentTab ? " · ⌃M" : ""
        return switch self {
        case let .call(isMuted): isMuted ? "Unmute call" : "Mute call"
        case .capture(.camera(isMuted: false)): "Turn off camera"
        case .capture(.camera(isMuted: true)): "Turn on camera"
        case .capture(.microphone(isMuted: false)): "Mute microphone"
        case .capture(.microphone(isMuted: true)): "Unmute microphone"
        case .audio(isMuted: false): optionIsDown ? "Pause media" : "Mute\(muteKey) · ⌥-click to pause"
        case .audio(isMuted: true): "Unmute\(muteKey)"
        case .crashed: isCurrentTab ? "Reload · ⌘R" : "Reload"
        case .suspended: "Wake"
        case .unread: "Mark as read"
        }
    }
}
