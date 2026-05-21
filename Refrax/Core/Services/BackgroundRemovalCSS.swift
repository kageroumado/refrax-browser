import Foundation

/// Generates CSS for background removal modes.
enum BackgroundRemovalCSS {
    private static let styleID = "refrax-background-removal"

    /// Generate CSS for the given background removal mode.
    ///
    /// - Parameter mode: The background removal mode to apply.
    /// - Returns: CSS string to inject, or empty string for `.none`.
    static func css(for mode: BackgroundRemovalMode) -> String {
        switch mode {
        case .none:
            ""

        case .removeImages:
            """
            * {
                background-image: none !important;
            }
            """

        case .simplify:
            """
            * {
                background-image: none !important;
            }
            body {
                background-color: Canvas !important;
            }
            """

        case .transparent:
            """
            * {
                background-image: none !important;
            }
            html, body {
                background-color: transparent !important;
            }
            """
        }
    }

    /// Generate JavaScript to inject the background removal CSS.
    ///
    /// - Parameter mode: The background removal mode to apply.
    /// - Returns: JavaScript string that injects the CSS.
    static func injectionScript(for mode: BackgroundRemovalMode) -> String {
        let bgCSS = css(for: mode)
        guard !bgCSS.isEmpty else { return "" }

        return CSSInjectionScript.create(id: styleID, css: bgCSS)
    }

    /// Script to remove the background removal styling.
    static let removeScript = CSSInjectionScript.remove(id: styleID)
}
