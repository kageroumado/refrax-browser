import Foundation
import WebKit

/// Calculates importance scores for WebPage instances to determine eviction priority.
///
/// `PageImportanceScorer` evaluates multiple factors to determine which pages
/// are most valuable to keep active and which can be safely evicted when memory
/// pressure requires reducing active page count.
///
/// ## Scoring Factors
///
/// Higher scores indicate more important pages that should be kept:
///
/// | Factor | Score Impact | Rationale |
/// |--------|--------------|-----------|
/// | Playing media | +1000 | User is actively watching/listening |
/// | Camera/mic active | +1000 | Video call or recording |
/// | Fullscreen video | +800 | Likely watching content |
/// | Unsaved form data | +500 | Data loss risk |
/// | Pinned tab | +300 | User marked as important |
/// | Recently visible | +200 | Active use |
/// | Recency (decay) | +0-100 | More recent = higher |
///
/// ## State Access
///
/// Camera, microphone, and fullscreen state are read directly from WebKit's
/// native properties (always available synchronously). Media playback and form
/// data state require async queries and are only checked in `scoreAllWithRefresh`.
///
/// ## Usage
///
/// ```swift
/// let scorer = PageImportanceScorer()
///
/// // Score all pages (synchronous - uses native state)
/// let scores = scorer.scoreAll(pages: activePages.values)
///
/// // Score with full state refresh (async - queries form data and media)
/// let accurateScores = await scorer.scoreAllWithRefresh(pages: pages)
///
/// // Get pages sorted by eviction priority (lowest score first)
/// let evictionCandidates = scores.sorted { $0.score < $1.score }
/// ```
struct PageImportanceScorer {
    // MARK: - Score Weights

    /// Weights for different importance factors.
    enum Weight {
        /// The tab is currently active
        static let isActive: Int = 1_000

        /// Tab is playing media (audio/video)
        static let playingMedia: Int = 1_000

        /// Camera or microphone is actively capturing
        static let mediaCapture: Int = 1_000

        /// Content is in fullscreen mode (likely video)
        static let fullscreen: Int = 800

        /// Form has unsaved user input
        static let hasFormData: Int = 500

        /// Tab is pinned by user
        static let pinned: Int = 300

        /// Tab was visible within last 5 minutes
        static let recentlyVisible: Int = 200

        /// Maximum recency bonus (decays over time)
        static let maxRecencyBonus: Int = 100

        /// Tab is a reference tab (usually kept for context)
        static let referenceTab: Int = 150
    }

    // MARK: - Configuration

    /// How long until recency bonus fully decays (in seconds).
    let recencyDecayPeriod: TimeInterval = 3_600 // 1 hour

    /// How recently a tab must have been visible to get the "recently visible" bonus.
    let recentVisibilityThreshold: TimeInterval = 300 // 5 minutes

    // MARK: - Scoring

    /// Result of scoring a page.
    struct ScoredPage {
        let page: WebPage
        let score: Int
        let factors: [String]

        /// Whether this page should be protected from eviction.
        var isProtected: Bool {
            score >= Weight.playingMedia
        }
    }

    /// Scores all provided pages for eviction priority.
    ///
    /// This method is synchronous and uses only native WebKit state
    /// (camera, microphone, fullscreen). It does not check media playback
    /// or form data state.
    ///
    /// - Parameter pages: Pages to score.
    /// - Returns: Array of scored pages, unsorted.
    func scoreAll(pages: some Sequence<WebPage>) -> [ScoredPage] {
        pages.map { score(page: $0) }
    }

    /// Async version that queries media playback and form data state.
    ///
    /// Use this when you need full state accuracy, at the cost of
    /// async queries for each page.
    ///
    /// - Parameter pages: Pages to score.
    /// - Returns: Array of scored pages, unsorted.
    func scoreAllWithRefresh(pages: some Sequence<WebPage>) async -> [ScoredPage] {
        var results: [ScoredPage] = []

        for page in pages {
            await results.append(scoreWithRefresh(page: page))
        }

        return results
    }

    /// Calculates the importance score for a single page.
    ///
    /// Uses only synchronously available state (native WebKit properties).
    /// Does not check media playback or form data state.
    ///
    /// - Parameter page: The page to score.
    /// - Returns: Scored page with breakdown of factors.
    func score(page: WebPage) -> ScoredPage {
        var score = 0
        var factors: [String] = []

        let tab = page.tabPage.tab

        // Media capture (camera/microphone) - from WebPage directly
        if page.cameraCaptureState == .active || page.microphoneCaptureState == .active {
            score += Weight.mediaCapture
            factors.append("media-capture")
        }

        // Fullscreen state - from WebPage directly
        if page.fullscreenState == .inFullscreen {
            score += Weight.fullscreen
            factors.append("fullscreen")
        }

        // Audio playing - from WebPage directly
        if page.isPlayingAudio {
            score += Weight.playingMedia
            factors.append("playing-audio")
        }

        // Pinned status
        if let tab, tab.isPinned {
            score += Weight.pinned
            factors.append("pinned")
        }

        // Reference tab
        if let tab, tab.isReferenceTab {
            score += Weight.referenceTab
            factors.append("reference")
        }

        // Recent visibility
        if let lastVisible = tab?.lastAccessed,
           Date().timeIntervalSince(lastVisible) < recentVisibilityThreshold {
            score += Weight.recentlyVisible
            factors.append("recently-visible")
        }

        // Recency bonus (decays over time)
        let recencyBonus = calculateRecencyBonus(for: page)
        if recencyBonus > 0 {
            score += recencyBonus
            factors.append("recency(\(recencyBonus))")
        }

        return ScoredPage(page: page, score: score, factors: factors)
    }

    /// Calculates the importance score for a single page with async state queries.
    ///
    /// Queries media playback state and form data state for full accuracy.
    ///
    /// - Parameter page: The page to score.
    /// - Returns: Scored page with breakdown of factors.
    func scoreWithRefresh(page: WebPage) async -> ScoredPage {
        var score = 0
        var factors: [String] = []

        let tab = page.tabPage.tab

        // Media capture (camera/microphone) - from WebPage directly
        if page.cameraCaptureState == .active || page.microphoneCaptureState == .active {
            score += Weight.mediaCapture
            factors.append("media-capture")
        }

        // Fullscreen state - from WebPage directly
        if page.fullscreenState == .inFullscreen {
            score += Weight.fullscreen
            factors.append("fullscreen")
        }

        // Media playback - requires async query
        let playbackState = await page.mediaPlaybackState()
        if playbackState == .playing {
            score += Weight.playingMedia
            factors.append("playing-media")
        }

        // Form data - requires async query
        await page.checkFormDataState()
        if page.hasUnsavedFormData {
            score += Weight.hasFormData
            factors.append("form-data")
        }

        // Pinned status
        if let tab, tab.isPinned {
            score += Weight.pinned
            factors.append("pinned")
        }

        // Reference tab
        if let tab, tab.isReferenceTab {
            score += Weight.referenceTab
            factors.append("reference")
        }

        // Recent visibility
        if let lastVisible = tab?.lastAccessed,
           Date().timeIntervalSince(lastVisible) < recentVisibilityThreshold {
            score += Weight.recentlyVisible
            factors.append("recently-visible")
        }

        // Recency bonus (decays over time)
        let recencyBonus = calculateRecencyBonus(for: page)
        if recencyBonus > 0 {
            score += recencyBonus
            factors.append("recency(\(recencyBonus))")
        }

        return ScoredPage(page: page, score: score, factors: factors)
    }

    // MARK: - Helpers

    /// Calculates recency bonus based on last activity time.
    private func calculateRecencyBonus(for page: WebPage) -> Int {
        // Use the tab's last visible time as proxy for activity
        // Never-accessed tabs get no recency bonus
        guard let tab = page.tabPage.tab,
              let lastAccessed = tab.lastAccessed else {
            return 0
        }

        let elapsed = Date().timeIntervalSince(lastAccessed)

        // If within decay period, calculate proportional bonus
        if elapsed < recencyDecayPeriod {
            let fraction = 1.0 - (elapsed / recencyDecayPeriod)
            return Int(Double(Weight.maxRecencyBonus) * fraction)
        }

        return 0
    }
}
