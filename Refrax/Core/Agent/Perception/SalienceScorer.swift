import CoreGraphics
import Foundation

/// Heuristic scoring of page complexity to determine optimal perception strategy.
///
/// Evaluates a ``PageContentTree`` to produce a salience score from 1-10:
///
/// | Score | Meaning | Perception Strategy |
/// |-------|---------|---------------------|
/// | 1-3 | Text-heavy, simple layout | Text extraction sufficient |
/// | 4-6 | Mixed content, some visual elements | Text + key image descriptions |
/// | 7-10 | Visual-heavy, complex layout | Screenshot needed |
///
/// Scoring is fast (<1ms) and based on already-extracted content tree,
/// not a DOM walk.
///
/// ## Usage
///
/// ```swift
/// let tree = try await PageContentExtractor.extract(from: webView, url: url, title: title)
/// let score = SalienceScorer.score(tree)
///
/// switch score.strategy {
/// case .textOnly:
///     // Use formatted text
/// case .textAndImages:
///     // Include image descriptions
/// case .screenshot:
///     // Capture and send screenshot
/// }
/// ```
nonisolated enum SalienceScorer: Sendable {
    /// The result of a salience scoring pass.
    struct Score: Sendable, Equatable {
        /// Numeric score from 1 (text-only) to 10 (highly visual).
        let value: Int

        /// Recommended perception strategy.
        let strategy: PerceptionStrategy

        /// Brief explanation of why this score was assigned.
        let reasoning: String
    }

    /// Perception strategy recommended by the salience scorer.
    enum PerceptionStrategy: String, Sendable, Equatable {
        /// Page is text-heavy; structured text extraction is sufficient.
        case textOnly

        /// Page has meaningful images; include image descriptions.
        case textAndImages

        /// Page is visually complex; screenshot is needed for full understanding.
        case screenshot
    }

    // MARK: - Scoring

    /// Scores a page content tree's visual complexity.
    ///
    /// - Parameter tree: The extracted content tree to evaluate.
    /// - Returns: A ``Score`` with the numeric value, strategy, and reasoning.
    static func score(_ tree: PageContentTree) -> Score {
        var stats = TreeStats()
        collectStats(from: tree.root, stats: &stats)

        var points = 0
        var reasons: [String] = []

        // Factor 1: Image density
        let meaningfulImages = stats.imageCount - stats.decorativeImageCount
        if meaningfulImages >= 10 {
            points += 4
            reasons.append("\(meaningfulImages) meaningful images")
        } else if meaningfulImages >= 5 {
            points += 3
            reasons.append("\(meaningfulImages) meaningful images")
        } else if meaningfulImages >= 2 {
            points += 1
            reasons.append("\(meaningfulImages) images")
        }

        // Factor 2: Large images (likely primary content, >= 400x300)
        if stats.largeImageCount >= 3 {
            points += 2
            reasons.append("\(stats.largeImageCount) large images (likely content)")
        } else if stats.largeImageCount >= 1 {
            points += 1
        }

        // Factor 3: Text-to-image ratio
        if stats.wordCount < 100, meaningfulImages > 0 {
            points += 2
            reasons.append("very little text with images — visual page")
        } else if stats.wordCount > 1_000, meaningfulImages <= 2 {
            points -= 1
            reasons.append("text-heavy article")
        }

        // Factor 4: Structural complexity
        if stats.sectionCount > 20 {
            points += 1
            reasons.append("complex layout (\(stats.sectionCount) sections)")
        }

        // Factor 5: Canvas elements (charts, graphs, interactive visuals)
        if stats.canvasCount > 0 {
            points += 2
            reasons.append("\(stats.canvasCount) canvas elements")
        }

        // Factor 6: Overlay ratio (modals, popups — indicate cluttered page)
        if stats.overlayCount > 2 {
            points += 1
            reasons.append("multiple overlays — cluttered layout")
        }

        // Factor 7: Images without alt text (need visual inspection)
        if stats.noAltImageCount >= 3 {
            points += 1
            reasons.append("\(stats.noAltImageCount) images without descriptions")
        }

        // Clamp to 1-10
        let clampedScore = max(1, min(10, points))

        let strategy: PerceptionStrategy = if clampedScore <= 3 {
            .textOnly
        } else if clampedScore <= 6 {
            .textAndImages
        } else {
            .screenshot
        }

        let reasoning = reasons.isEmpty ? "Standard page" : reasons.joined(separator: "; ")

        return Score(value: clampedScore, strategy: strategy, reasoning: reasoning)
    }

    // MARK: - Quick Assessment from Metadata Only

    /// Quick salience assessment using only a URL, without full structure.
    ///
    /// Useful when you have URL info but haven't run full extraction.
    /// Less accurate than ``score(_:)`` but essentially free.
    ///
    /// - Parameter url: The page URL.
    /// - Returns: An estimated ``PerceptionStrategy``.
    static func quickAssessment(url: URL) -> PerceptionStrategy {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()

        // Known visual-heavy domains
        let visualDomains = [
            "instagram.com",
            "pinterest.com",
            "flickr.com",
            "dribbble.com",
            "behance.net",
            "unsplash.com",
            "maps.google.com",
            "maps.apple.com",
        ]
        if visualDomains.contains(where: { host.contains($0) }) {
            return .screenshot
        }

        // Known text-heavy domains
        let textDomains = [
            "wikipedia.org",
            "arxiv.org",
            "news.ycombinator.com",
            "reddit.com",
            "stackoverflow.com",
            "github.com",
        ]
        if textDomains.contains(where: { host.contains($0) }) {
            return .textOnly
        }

        // Path heuristics
        if path.contains("/search") || path.contains("/results") {
            return .textOnly
        }
        if path.contains("/gallery") || path.contains("/photos") || path.contains("/images") {
            return .screenshot
        }

        // Shopping pages often need visual context
        let shoppingDomains = ["amazon.", "ebay.", "etsy.", "shopify."]
        if shoppingDomains.contains(where: { host.contains($0) }) {
            return .textAndImages
        }

        return .textOnly
    }

    // MARK: - Helpers

    private struct TreeStats {
        var imageCount = 0
        var decorativeImageCount = 0
        var largeImageCount = 0
        var noAltImageCount = 0
        var wordCount = 0
        var sectionCount = 0
        var canvasCount = 0
        var overlayCount = 0
    }

    private static func collectStats(from node: PageContentNode, stats: inout TreeStats) {
        switch node.type {
        case let .image(alt):
            stats.imageCount += 1
            if alt?.isEmpty == true {
                stats.decorativeImageCount += 1
            }
            if alt == nil || (alt?.isEmpty == true) {
                stats.noAltImageCount += 1
            }
            if node.rect.width >= 400, node.rect.height >= 300 {
                stats.largeImageCount += 1
            }

        case let .text(content):
            stats.wordCount += content.split(whereSeparator: \.isWhitespace).count

        case .section, .article, .navigation, .form:
            stats.sectionCount += 1

        case .canvas:
            stats.canvasCount += 1

        case .overlay:
            stats.overlayCount += 1

        default:
            break
        }

        for child in node.children {
            collectStats(from: child, stats: &stats)
        }
    }
}
