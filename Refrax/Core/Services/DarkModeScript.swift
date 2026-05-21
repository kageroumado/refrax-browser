import Foundation

/// Generates CSS/JS for forcing dark mode on web pages.
///
/// Uses a hybrid approach:
/// 1. Set `color-scheme: dark` to trigger native dark mode support
/// 2. Check if page responded (background luminance)
/// 3. Fall back to CSS filter invert if page is still light
enum DarkModeScript {
    private static let styleID = "refrax-dark-mode"
    private static let forceDarkClass = "refrax-force-dark"

    /// JavaScript that detects page response and applies fallback if needed.
    ///
    /// Injected at document end after page renders.
    static func detectionScript(preserveMedia: Bool) -> String {
        let mediaCSS = preserveMedia ? mediaPreservationCSS : ""

        return """
        (function() {
            'use strict';
        
            document.documentElement.style.colorScheme = 'dark';
        
            let style = document.getElementById('\(styleID)');
            if (!style) {
                style = document.createElement('style');
                style.id = '\(styleID)';
                (document.head || document.documentElement).appendChild(style);
            }
        
            style.textContent = `
                html.\(forceDarkClass) {
                    filter: invert(1) hue-rotate(180deg);
                    background-color: #111 !important;
                }
                \(mediaCSS)
            `;
        
            requestAnimationFrame(() => {
                requestAnimationFrame(() => {
                    const body = document.body;
                    if (!body) return;
        
                    const bg = getComputedStyle(body).backgroundColor;
                    const rgb = bg.match(/\\d+/g)?.map(Number) || [255, 255, 255];
                    const luminance = (0.299 * rgb[0] + 0.587 * rgb[1] + 0.114 * rgb[2]) / 255;
        
                    if (luminance > 0.5) {
                        document.documentElement.classList.add('\(forceDarkClass)');
                    }
                });
            });
        })();
        """
    }

    /// CSS to preserve media element colors when using invert filter.
    private static let mediaPreservationCSS = """
    html.\(forceDarkClass) img,
    html.\(forceDarkClass) video,
    html.\(forceDarkClass) canvas,
    html.\(forceDarkClass) svg image,
    html.\(forceDarkClass) picture,
    html.\(forceDarkClass) iframe[src*="youtube"],
    html.\(forceDarkClass) iframe[src*="vimeo"],
    html.\(forceDarkClass) [style*="background-image"] {
        filter: invert(1) hue-rotate(180deg);
    }
    """

    /// Script to remove dark mode styling.
    static let removeScript = """
    (function() {
        document.documentElement.classList.remove('\(forceDarkClass)');
        document.documentElement.style.colorScheme = '';
        const style = document.getElementById('\(styleID)');
        if (style) style.remove();
    })();
    """
}
