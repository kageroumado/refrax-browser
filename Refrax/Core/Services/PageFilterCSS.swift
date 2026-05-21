import Foundation

/// Generates CSS filter rules for accessibility filters.
enum PageFilterCSS {
    /// Generate CSS for the given filter.
    ///
    /// - Parameters:
    ///   - filter: The page filter to apply.
    ///   - preserveMedia: Whether to re-invert media elements for invert filter.
    /// - Returns: CSS string to inject, or empty string for `.none`.
    static func css(for filter: PageFilter, preserveMedia: Bool) -> String {
        guard let filterValue = filter.cssFilterValue else { return "" }

        var css = """
        html {
            filter: \(filterValue) !important;
            -webkit-filter: \(filterValue) !important;
        }
        """

        if preserveMedia, filter == .invertColors {
            css += """
            
            img, video, picture, canvas, svg,
            iframe[src*="youtube"], iframe[src*="vimeo"],
            [style*="background-image"] {
                filter: invert(1) hue-rotate(180deg) !important;
            }
            """
        }

        return css
    }

    /// Generate JavaScript to inject the filter CSS.
    ///
    /// - Parameters:
    ///   - filter: The page filter to apply.
    ///   - preserveMedia: Whether to preserve media element colors.
    /// - Returns: JavaScript string that injects the CSS.
    static func injectionScript(for filter: PageFilter, preserveMedia: Bool) -> String {
        let filterCSS = css(for: filter, preserveMedia: preserveMedia)
        guard !filterCSS.isEmpty else { return "" }

        return CSSInjectionScript.create(
            id: "refrax-page-filter",
            css: filterCSS,
        )
    }

    /// Script to remove the page filter.
    static let removeScript = CSSInjectionScript.remove(id: "refrax-page-filter")
}

// MARK: - PageFilter CSS Values

extension PageFilter {
    /// CSS filter value for this filter type.
    ///
    /// Returns `nil` for `.none` since no filter should be applied.
    var cssFilterValue: String? {
        switch self {
        case .none:
            nil
        case .grayscale:
            "grayscale(100%)"
        case .highContrast:
            "contrast(1.4) saturate(1.2)"
        case .invertColors:
            "invert(1) hue-rotate(180deg)"
        case .reduceBrightness:
            "brightness(0.75)"
        case .sepia:
            "sepia(0.7)"
        case .protanopia:
            "url(#refrax-protanopia-filter)"
        case .deuteranopia:
            "url(#refrax-deuteranopia-filter)"
        case .tritanopia:
            "url(#refrax-tritanopia-filter)"
        }
    }
}

// MARK: - CSS Injection Script Helper

/// Shared helper for generating CSS injection JavaScript.
///
/// Provides consistent patterns for injecting and removing style elements.
enum CSSInjectionScript {
    /// Creates JavaScript that injects CSS into a style element.
    ///
    /// - Parameters:
    ///   - id: Unique ID for the style element.
    ///   - css: CSS content to inject.
    /// - Returns: JavaScript string that creates or updates the style element.
    static func create(id: String, css: String) -> String {
        let escapedCSS = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "${", with: "\\${")

        return """
        (function() {
            let style = document.getElementById('\(id)');
            if (!style) {
                style = document.createElement('style');
                style.id = '\(id)';
                (document.head || document.documentElement).appendChild(style);
            }
            style.textContent = `\(escapedCSS)`;
        })();
        """
    }

    /// Creates JavaScript that removes a style element.
    ///
    /// - Parameter id: ID of the style element to remove.
    /// - Returns: JavaScript string that removes the element.
    static func remove(id: String) -> String {
        """
        (function() {
            const style = document.getElementById('\(id)');
            if (style) style.remove();
        })();
        """
    }
}
