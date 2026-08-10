import Foundation

/// Generates JavaScript for the per-site "Calm This Page" energy saver.
///
/// Infinite CSS/SVG animations force the compositor to render every display
/// refresh for as long as the page is visible — the dominant energy cost of
/// decorative pages. Calming a page pauses every animation in place:
///
/// 1. A `<style>` rule sets `animation-play-state: paused` on everything
/// 2. Every `<svg>` gets `pauseAnimations()` for SMIL content
///
/// Removal restores both, and animations resume mid-cycle. JS-driven
/// `requestAnimationFrame` loops and `<canvas>` repaints are untouched; they
/// cost page-process CPU but stop forcing compositor frames once declarative
/// animation is frozen.
enum CalmPageScript {
    private static let styleID = "refrax-calm-page"

    /// Pauses all declarative animation. Idempotent.
    static let applyScript = """
    (function() {
        'use strict';
        if (!document.getElementById('\(styleID)')) {
            const style = document.createElement('style');
            style.id = '\(styleID)';
            style.textContent = '*, *::before, *::after { animation-play-state: paused !important; }';
            (document.head || document.documentElement).appendChild(style);
        }
        document.querySelectorAll('svg').forEach(svg => {
            try { svg.pauseAnimations(); } catch (_) {}
        });
    })();
    """

    /// Resumes animation by removing the pause rule. Idempotent.
    static let removeScript = """
    (function() {
        'use strict';
        const style = document.getElementById('\(styleID)');
        if (style) style.remove();
        document.querySelectorAll('svg').forEach(svg => {
            try { svg.unpauseAnimations(); } catch (_) {}
        });
    })();
    """
}
