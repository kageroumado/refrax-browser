import Foundation

/// What a filter reads of a tab: its unread mark and what its pages are doing now.
nonisolated struct IslandRowFacts: Equatable, Sendable {
    var isUnread = false
    var isPlayingAudio = false
    /// The microphone is live, or muted in a page still holding it.
    var usesMicrophone = false
    /// The camera is live, or turned off in a page still holding it.
    var usesCamera = false

    init(isUnread: Bool = false, isPlayingAudio: Bool = false, usesMicrophone: Bool = false, usesCamera: Bool = false) {
        self.isUnread = isUnread
        self.isPlayingAudio = isPlayingAudio
        self.usesMicrophone = usesMicrophone
        self.usesCamera = usesCamera
    }

    init(state: TabMediaState, isUnread: Bool) {
        self.init(isUnread: isUnread, isPlayingAudio: state.isPlayingAudio, usesMicrophone: state.hasMicrophone, usesCamera: state.hasCamera)
    }
}

/// A quick filter on the islands: only the tabs it matches keep their rows, with the current
/// tab's always kept, so the page on screen never loses its place. Sections and islands left
/// with no row fold away.
nonisolated enum IslandFilter: String, CaseIterable, Identifiable, Sendable {
    case unread
    case playingAudio
    case microphone
    case camera

    var id: Self {
        self
    }

    /// The menu item and lens command that turns it on.
    var title: String {
        switch self {
        case .unread: "Unread Tabs"
        case .playingAudio: "Tabs Playing Sound"
        case .microphone: "Tabs Using the Microphone"
        case .camera: "Tabs Using the Camera"
        }
    }

    /// What the islands say while it is on.
    var description: String {
        "Showing \(title.prefix(1).lowercased() + title.dropFirst())"
    }

    /// What the islands say while it matches nothing.
    var emptyDescription: String {
        switch self {
        case .unread: "No unread tabs"
        case .playingAudio: "No tab is playing sound"
        case .microphone: "No tab is using the microphone"
        case .camera: "No tab is using the camera"
        }
    }

    var symbol: String {
        switch self {
        case .unread: "circlebadge.fill"
        case .playingAudio: "speaker.wave.2.fill"
        case .microphone: "mic.fill"
        case .camera: "video.fill"
        }
    }

    /// Words that find it in Command Lens.
    var terms: [String] {
        switch self {
        case .unread: ["unread", "unread tabs", "show unread", "new tabs", "filter unread"]
        case .playingAudio: ["playing", "audio", "sound", "audible", "music", "noisy tab", "playing sound", "filter audio"]
        case .microphone: ["microphone", "mic", "using microphone", "recording", "filter microphone"]
        case .camera: ["camera", "video", "using camera", "webcam", "filter camera"]
        }
    }

    func matches(_ facts: IslandRowFacts) -> Bool {
        switch self {
        case .unread: facts.isUnread
        case .playingAudio: facts.isPlayingAudio
        case .microphone: facts.usesMicrophone
        case .camera: facts.usesCamera
        }
    }

    /// The tabs of `tabs` whose rows stay: those it matches, and `current`.
    func shown(_ tabs: [(id: UUID, facts: IslandRowFacts)], current: UUID?) -> Set<UUID> {
        Set(tabs.filter { $0.id == current || matches($0.facts) }.map(\.id))
    }
}
