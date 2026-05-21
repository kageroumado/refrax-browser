import AudioToolbox
import CoreAudio
import Foundation
import SwiftUI

extension Sidebar {
    /// Manages media controls panel state and aggregates media activity across all tabs.
    ///
    /// The manager observes all active WebPages via WebPagePool and maintains a list
    /// of tabs with media activity (playing audio, active calls, or recently active).
    ///
    /// ## Architecture
    ///
    /// ```
    /// WebPagePool (all active pages)
    ///       │
    ///       ▼
    /// MediaControlsManager
    ///   - activeSections: [MediaSection]  (aggregated view)
    ///   - isExpanded: Bool
    ///   - isPinned: Bool
    ///       │
    ///       ▼
    /// MediaControlsPanel (UI)
    /// ```
    ///
    /// ## Section Types
    ///
    /// - `.call` — Tab is in a video call (domain + capture state)
    /// - `.media` — Tab is playing audio/video
    /// - `.both` — Tab is in a call AND has background media
    ///
    /// ## Recently Active
    ///
    /// Tabs remain visible for 5 minutes after media pauses to allow quick resume.
    @Observable
    final class MediaControlsManager {
        // MARK: - Dependencies

        /// Access to the page pool for iterating active pages.
        @ObservationIgnored
        weak var pagePool: WebPagePool?

        /// Tab lookup closure provided during initialization.
        @ObservationIgnored
        var tabLookup: ((TabPage.ID) -> Tab?)?

        /// Active space ID lookup for cross-space detection.
        @ObservationIgnored
        var activeSpaceIDLookup: (() -> UUID?)?

        /// Registry for detecting call domains.
        let callDomainRegistry = CallDomainRegistry()

        // MARK: - Panel State

        /// Whether the media controls panel is currently expanded.
        var isExpanded: Bool = false {
            didSet {
                if isExpanded {
                    if !isPinned, hasActiveMedia {
                        startCollapseTimer()
                    }
                } else {
                    cancelCollapseTimer()
                }
            }
        }

        /// Whether the panel is pinned (auto-reopens when media starts).
        ///
        /// When pinned:
        /// - Panel closes when empty (like normal)
        /// - Panel automatically reopens when new media starts playing
        /// - No auto-collapse timer runs
        ///
        /// Session-only persistence (resets on app restart).
        var isPinned: Bool = false {
            didSet {
                if isPinned {
                    cancelCollapseTimer()
                } else if isExpanded, hasActiveMedia {
                    startCollapseTimer()
                }
            }
        }

        /// Pages that were manually paused by the user.
        ///
        /// These pages remain visible in the panel until the tab is closed
        /// or the user explicitly dismisses them.
        @ObservationIgnored
        private var manuallyPausedPages: Set<TabPage.ID> = []

        /// Pages where the user has adjusted volume via the media panel.
        ///
        /// These pages remain visible even if volume is 0 (which causes
        /// `isPlayingAudio` to be false). Cleared when dismissed or tab closed.
        @ObservationIgnored
        private var volumeControlledPages: Set<TabPage.ID> = []

        /// Auto-collapse timer task.
        @ObservationIgnored
        private var collapseTask: Task<Void, any Error>?

        // MARK: - Computed Properties

        /// All tabs with active or recently-active media/calls.
        ///
        /// Sorted by: calls first, then by last activity time (most recent first).
        var activeSections: [MediaSection] {
            guard let pagePool, let tabLookup else { return [] }

            var sections: [MediaSection] = []
            let activeSpaceID = activeSpaceIDLookup?()

            // Collect all pages with media activity
            for (pageID, webPage) in pagePool.activePages {
                guard let tab = tabLookup(pageID) else { continue }

                // Check for media activity
                let isPlaying = webPage.isPlayingAudio
                let isSuspended = webPage.isMediaSuspended
                let isInCall = webPage.isInCall(using: callDomainRegistry)
                let hasRecentActivity = isRecentlyActive(webPage)
                let wasManuallyPaused = isManuallyPaused(pageID)
                let hasVolumeControl = isVolumeControlled(pageID)

                // Skip if no relevant activity
                guard isPlaying || isSuspended || isInCall || hasRecentActivity || wasManuallyPaused || hasVolumeControl else { continue }

                // Determine section type
                let type: MediaType = if isInCall, isPlaying {
                    .both
                } else if isInCall {
                    .call
                } else {
                    .media
                }

                // Determine if from current space
                let isFromCurrentSpace = tab.space?.id == activeSpaceID

                let section = MediaSection(
                    id: pageID,
                    tab: tab,
                    webPage: webPage,
                    type: type,
                    isFromCurrentSpace: isFromCurrentSpace,
                )
                sections.append(section)
            }

            // Sort: calls first, then by last activity (most recent first)
            sections.sort { a, b in
                // Calls before media
                if a.type.isCall != b.type.isCall {
                    return a.type.isCall
                }
                // Then by last activity (most recent first)
                let aTime = a.webPage.lastMediaActivity ?? .distantPast
                let bTime = b.webPage.lastMediaActivity ?? .distantPast
                return aTime > bTime
            }

            return sections
        }

        /// Whether there are any active media sections.
        var hasActiveMedia: Bool {
            !activeSections.isEmpty
        }

        /// Whether there are any active calls.
        var hasActiveCalls: Bool {
            activeSections.contains { $0.type.isCall }
        }

        /// Whether there is media playback (non-call).
        var hasMediaPlayback: Bool {
            activeSections.contains { $0.type == .media || $0.type == .both }
        }

        /// Whether the system output volume is effectively muted (zero or muted).
        ///
        /// When true and there's an active call, we show a warning to the user
        /// that they won't be able to hear anything.
        var isSystemOutputMuted: Bool {
            Self.checkSystemOutputMuted()
        }

        /// Checks if the system's default output device is muted or at zero volume.
        private static func checkSystemOutputMuted() -> Bool {
            var defaultOutputID = AudioDeviceID()
            var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)

            // Get the default output device
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain,
            )

            let status = AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &propertySize,
                &defaultOutputID,
            )

            guard status == noErr else { return false }

            // Check if device is muted
            var isMuted: UInt32 = 0
            propertySize = UInt32(MemoryLayout<UInt32>.size)
            address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain,
            )

            let muteStatus = AudioObjectGetPropertyData(
                defaultOutputID,
                &address,
                0,
                nil,
                &propertySize,
                &isMuted,
            )

            if muteStatus == noErr, isMuted != 0 {
                return true
            }

            // Check volume level
            var volume: Float32 = 0
            propertySize = UInt32(MemoryLayout<Float32>.size)
            address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain,
            )

            let volumeStatus = AudioObjectGetPropertyData(
                defaultOutputID,
                &address,
                0,
                nil,
                &propertySize,
                &volume,
            )

            // Consider muted if volume is essentially zero
            if volumeStatus == noErr, volume < 0.01 {
                return true
            }

            return false
        }

        // MARK: - Constants

        /// Duration to keep paused media visible in the panel (5 minutes).
        private static let recentlyActiveDuration: TimeInterval = 5 * 60

        /// Duration before auto-collapsing the panel (15 seconds).
        private static let autoCollapseDuration: TimeInterval = 15

        // MARK: - Panel Actions

        /// Toggles the panel expansion state.
        func togglePanel() {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                isExpanded.toggle()
            }
        }

        /// Expands the panel.
        func expandPanel() {
            guard !isExpanded else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                isExpanded = true
            }
        }

        /// Collapses the panel (unless pinned).
        func collapsePanel() {
            guard isExpanded, !isPinned else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                isExpanded = false
            }
        }

        /// Toggles the pinned state.
        func togglePinned() {
            isPinned.toggle()
        }

        /// Resets the auto-collapse timer.
        ///
        /// Call this when the user interacts with the panel to keep it open.
        func resetCollapseTimer() {
            guard isExpanded, !isPinned else { return }
            startCollapseTimer()
        }

        /// Records that a page was manually paused by the user.
        ///
        /// The page will remain visible in the panel until the tab is closed
        /// or the user explicitly dismisses it.
        func recordManualPause(for pageID: TabPage.ID) {
            manuallyPausedPages.insert(pageID)
        }

        /// Clears the manual pause record for a page.
        ///
        /// Called when the user resumes playback on a manually paused page.
        func clearManualPause(for pageID: TabPage.ID) {
            manuallyPausedPages.remove(pageID)
        }

        /// Records that a page's volume was adjusted via the media panel.
        ///
        /// The page will remain visible even if volume is 0 (which causes
        /// `isPlayingAudio` to become false). This prevents the jarring
        /// disappearance of tabs when using the volume slider.
        func recordVolumeControl(for pageID: TabPage.ID) {
            volumeControlledPages.insert(pageID)
        }

        /// Clears the volume control record for a page.
        func clearVolumeControl(for pageID: TabPage.ID) {
            volumeControlledPages.remove(pageID)
        }

        /// Checks if a page has been volume-controlled via the panel.
        private func isVolumeControlled(_ pageID: TabPage.ID) -> Bool {
            volumeControlledPages.contains(pageID)
        }

        /// Closes the panel immediately if there's no active media.
        ///
        /// This closes unconditionally, even if pinned. Pinned just means
        /// the panel will auto-reopen when new media starts.
        func closeIfNoActiveMedia() {
            guard isExpanded, !hasActiveMedia else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                isExpanded = false
            }
        }

        /// Opens the panel automatically if pinned and media becomes available.
        ///
        /// Called when media state changes to implement pinned auto-reopen behavior.
        func expandIfPinnedAndHasMedia() {
            guard isPinned, !isExpanded, hasActiveMedia else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                isExpanded = true
            }
        }

        // MARK: - Timer Management

        private func startCollapseTimer() {
            cancelCollapseTimer()

            collapseTask = Task {
                try await Task.sleep(for: .seconds(Self.autoCollapseDuration))

                // Re-check conditions before collapsing
                await MainActor.run {
                    if !isPinned, isExpanded, hasActiveMedia {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            isExpanded = false
                        }
                    }
                }
            }
        }

        private func cancelCollapseTimer() {
            collapseTask?.cancel()
            collapseTask = nil
        }

        // MARK: - Recently Active Check

        private func isRecentlyActive(_ webPage: WebPage) -> Bool {
            guard let lastActivity = webPage.lastMediaActivity else { return false }
            let elapsed = Date().timeIntervalSince(lastActivity)
            return elapsed < Self.recentlyActiveDuration
        }

        /// Checks if a page was manually paused by the user.
        private func isManuallyPaused(_ pageID: TabPage.ID) -> Bool {
            manuallyPausedPages.contains(pageID)
        }
    }
}

// MARK: - MediaSection

/// Represents a tab's media/call section in the controls panel.
struct MediaSection: Identifiable {
    /// Unique identifier (matches TabPage.ID).
    let id: TabPage.ID

    /// The tab containing this media source.
    let tab: Tab

    /// The WebPage with media activity.
    let webPage: WebPage

    /// The type of media activity.
    let type: MediaType

    /// Whether this tab is in the currently active space.
    let isFromCurrentSpace: Bool

    /// The domain of the page (for display).
    var domain: String {
        webPage.url?.host ?? "Unknown"
    }

    /// Whether media is currently playing (not paused/suspended).
    ///
    /// Uses `isMediaPlaying` which reflects actual playback state, not audio output.
    /// A muted tab (even from webpage's own controls) shows as "playing".
    ///
    /// Falls back to `isPlayingAudio` if playback state hasn't been refreshed yet.
    var isPlaying: Bool {
        // Prefer actual playback state, fall back to audio output detection
        webPage.isMediaPlaying || webPage.isPlayingAudio
    }

    /// Whether audio is muted (tab-level mute).
    var isMuted: Bool {
        webPage.isAudioMuted
    }

    /// Whether audio is effectively muted (tab muted OR volume at 0).
    ///
    /// Use this for UI display since both conditions result in no audio.
    var effectivelyMuted: Bool {
        webPage.isAudioMuted || webPage.volume == 0
    }

    /// Current volume level (0.0 to 1.0).
    var volume: Double {
        webPage.volume
    }

    // MARK: - Media Session Metadata

    /// Media Session metadata from the page (title, artist, artwork).
    var mediaSession: MediaSessionMetadata? {
        webPage.mediaSessionMetadata
    }

    /// Display title: Media Session title, page title, or domain.
    var displayTitle: String {
        if let title = mediaSession?.title {
            return title
        }
        return webPage.title.isEmpty ? domain : webPage.title
    }

    /// Display subtitle: Artist name if available.
    var displaySubtitle: String? {
        mediaSession?.artist
    }

    /// Artwork URL from Media Session, if available.
    var artworkURL: URL? {
        mediaSession?.artworkURL
    }

    /// Whether we have Media Session artwork available.
    var hasArtwork: Bool {
        artworkURL != nil
    }
}

// MARK: - MediaType

/// The type of media activity in a section.
enum MediaType: Hashable {
    /// Audio/video playback only.
    case media

    /// Active call (mic/camera on known call domain).
    case call

    /// Call with background media playing.
    case both

    /// Whether this type represents a call.
    var isCall: Bool {
        self == .call || self == .both
    }

    /// Whether this type represents media playback.
    var isMedia: Bool {
        self == .media || self == .both
    }
}
