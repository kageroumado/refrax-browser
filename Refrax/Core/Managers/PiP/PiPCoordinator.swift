import Foundation

/// Coordinates Picture-in-Picture behavior across tabs.
///
/// Handles auto-PiP on tab switch when enabled in settings. When the user
/// switches away from a tab with playing video, this coordinator automatically
/// triggers PiP mode for that video. When returning to the source tab, PiP
/// automatically exits.
///
/// ## Usage
///
/// The coordinator should be notified when tabs change:
/// ```swift
/// pipCoordinator.onTabDeactivated(previousTab, in: browserState)
/// pipCoordinator.onTabActivated(newTab, in: browserState)
/// ```

final class PiPCoordinator {
    // MARK: - Properties

    private weak var settings: BrowserSettings?

    /// The tab ID that triggered auto-PiP, if any.
    ///
    /// Used to auto-exit PiP when returning to the source tab.
    private(set) var activePiPSourceTabID: UUID?

    /// Whether the current PiP was triggered automatically (vs manually by user).
    private(set) var isAutoPiP: Bool = false

    // MARK: - Initialization

    /// Creates a new PiP coordinator.
    ///
    /// - Parameter settings: Browser settings to check auto-PiP preference.
    init(settings: BrowserSettings?) {
        self.settings = settings
    }

    // MARK: - Tab Activation

    /// Called when a tab is activated (user switched to this tab).
    ///
    /// If the activated tab is the source of an auto-PiP session,
    /// this method automatically exits PiP.
    ///
    /// - Parameters:
    ///   - tab: The tab being activated.
    ///   - browserState: The browser state to access WebPage instances.
    func onTabActivated(_ tab: Tab, in browserState: BrowserState) {
        // Check if this is the tab that triggered auto-PiP
        guard let sourceID = activePiPSourceTabID,
              sourceID == tab.id,
              isAutoPiP else {
            return
        }

        // Get the WebPage and exit PiP
        let activePage = tab.activePage
        guard let webPage = browserState.webPage(for: activePage.id) else {
            return
        }

        // Exit PiP since user returned to the source tab
        Task(name: "Auto-PiP exit") {
            await webPage.exitPiP()
        }
        clearPiPState()
    }

    // MARK: - Tab Deactivation

    /// Called when a tab is deactivated (user switched to another tab).
    ///
    /// If auto-PiP is enabled and the deactivated tab has playing video,
    /// this method triggers PiP for that video.
    ///
    /// - Parameters:
    ///   - tab: The tab being deactivated.
    ///   - browserState: The browser state to access WebPage instances.
    func onTabDeactivated(_ tab: Tab, in browserState: BrowserState) {
        // Get the active page's WebPage
        let activePage = tab.activePage
        guard let webPage = browserState.webPage(for: activePage.id) else {
            return
        }

        // Check per-site PiP preference
        let sitePreference: PiPPreference = if let url = webPage.url {
            browserState.siteSettingsManager.settings(for: url)?.pipPreference ?? .system
        } else {
            .system
        }

        // Determine if auto-PiP should trigger
        let shouldAutoPiP: Bool = switch sitePreference {
        case .always:
            // Site setting forces auto-PiP even if global is off
            true
        case .never:
            // Site setting prevents auto-PiP
            false
        case .system:
            // Fall back to global setting
            settings?.autoPiPOnTabSwitch ?? false
        }

        guard shouldAutoPiP else { return }

        // Gate on the JS-observed page state: a playing, PiP-eligible video.
        // The native canTogglePiP is advisory only (false-negatives whenever
        // the playback-controls session is absent). We don't check
        // isPlayingAudio because videos may be muted or have no audio track.
        Task(name: "Auto-PiP enter") { [weak self] in
            let state = await webPage.pipState()
            guard state.playing, state.eligible, !state.active else { return }

            await webPage.enterPiP()
            guard let self else { return }
            self.activePiPSourceTabID = tab.id
            self.isAutoPiP = true
        }
    }

    // MARK: - Manual PiP Control

    /// Called when the user manually exits PiP (via the PiP window controls).
    ///
    /// Clears the auto-PiP tracking state so we don't incorrectly
    /// auto-exit when the user later visits the source tab.
    func onManualPiPExit() {
        clearPiPState()
    }

    /// Called when PiP ends for any reason (manual exit, video ended, tab closed, etc.).
    func onPiPDidEnd() {
        clearPiPState()
    }

    // MARK: - Tab Close

    /// Called when a tab is closed.
    ///
    /// If the closed tab was the source of auto-PiP, clears the state.
    func onTabClosed(_ tabID: UUID) {
        if activePiPSourceTabID == tabID {
            clearPiPState()
        }
    }

    // MARK: - Private

    private func clearPiPState() {
        activePiPSourceTabID = nil
        isAutoPiP = false
    }
}
