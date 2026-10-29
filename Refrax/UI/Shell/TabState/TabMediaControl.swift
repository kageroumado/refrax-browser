import Foundation

/// The sound, capture and process verbs of one tab, applied to every live page it holds.
///
/// The tab state symbols, the menus, the menu bar and Command Lens all act through this, so
/// a mute from any of them is the same mute.
struct TabMediaControl {
    let tab: Tab
    let pagePool: WebPagePool
    /// Records a manual pause so the paused page stays in Now Playing.
    var mediaControls: MediaControlsManager?

    var pages: [WebPage] {
        tab.pages.compactMap { pagePool.existingPage(for: $0) }
    }

    var state: TabMediaState {
        TabMediaState(pages: pages)
    }

    /// Every live page is muted; a tab without a live page is not.
    var isMuted: Bool {
        state.isTabMuted
    }

    func setMuted(_ muted: Bool) {
        for page in pages {
            page.setAudioMuted(muted)
        }
    }

    func toggleMute() {
        setMuted(!isMuted)
    }

    /// Pauses every page's media and keeps the paused pages in Now Playing.
    func pauseMedia() {
        let pages = tab.pages.compactMap { tabPage in pagePool.existingPage(for: tabPage).map { (tabPage.id, $0) } }
        for (id, _) in pages {
            mediaControls?.recordManualPause(for: id)
        }
        Task(name: "Pause tab media") {
            for (_, page) in pages {
                await page.pauseAllMediaPlayback()
                await page.refreshPlaybackState()
            }
        }
    }

    func setCameraMuted(_ muted: Bool) {
        let pages = pages
        Task(name: "Set tab camera muted") {
            for page in pages {
                await page.setCameraMuted(muted)
            }
        }
    }

    func setMicrophoneMuted(_ muted: Bool) {
        let pages = pages
        Task(name: "Set tab microphone muted") {
            for page in pages {
                await page.setMicrophoneMuted(muted)
            }
        }
    }

    func reload() {
        for page in pages {
            _ = page.reload()
        }
    }

    /// Reloads the pages that were unloaded to save memory.
    func wake() {
        for page in pages where page.needsReload {
            _ = page.reload()
        }
    }

    /// Mutes every page outside `tab` that plays sound, and returns how many it muted.
    @discardableResult
    static func muteOthers(than tab: Tab, in pagePool: WebPagePool) -> Int {
        let own = Set(tab.pages.map(\.id))
        let playing = pagePool.activePages.filter { id, page in
            !own.contains(id) && page.isPlayingAudio && !page.isAudioMuted
        }
        for page in playing.values {
            page.setAudioMuted(true)
        }
        return playing.count
    }

    /// Another tab plays sound that is not muted.
    static func othersPlay(than tab: Tab, in pagePool: WebPagePool) -> Bool {
        let own = Set(tab.pages.map(\.id))
        return pagePool.activePages.contains { id, page in
            !own.contains(id) && page.isPlayingAudio && !page.isAudioMuted
        }
    }
}
