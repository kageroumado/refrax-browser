import Foundation

/// Decides which web view an extension page needs.
///
/// WebKit binds a web view to one extension when the view is created: a view built from
/// `WKWebExtensionContext.webViewConfiguration` navigates only within that extension's base
/// URL, and every other view is refused that extension's pages. A tab moving between an
/// extension's pages and anything else therefore needs a new web view.
nonisolated enum ExtensionPageRouting {
    /// The scheme of every `WKWebExtensionContext.baseURL` in Refrax, which keeps WebKit's default.
    static let scheme = "webkit-extension"

    /// Whether `url` addresses a page inside an extension.
    static func isExtensionURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == scheme
    }

    /// Whether a web view bound to the extension at `currentBaseURL` can load a URL owned by
    /// the extension at `targetBaseURL`. `nil` stands for "no extension" on either side.
    ///
    /// Only the scheme and host identify an extension, matching how WebKit reads `baseURL`.
    static func canNavigate(from currentBaseURL: URL?, to targetBaseURL: URL?) -> Bool {
        origin(of: currentBaseURL) == origin(of: targetBaseURL)
    }

    /// Whether `url` shows the same document as `page`: equal once fragments are dropped, so a
    /// tab on `dashboard.html#settings` counts as showing `dashboard.html`.
    static func isSamePage(_ url: URL, _ page: URL) -> Bool {
        withoutFragment(url) == withoutFragment(page)
    }

    private static func withoutFragment(_ url: URL) -> String {
        let string = url.absoluteString
        return string.firstIndex(of: "#").map { String(string[..<$0]) } ?? string
    }

    private static func origin(of url: URL?) -> String? {
        guard let url else { return nil }
        return "\(url.scheme?.lowercased() ?? "")://\(url.host()?.lowercased() ?? "")"
    }
}
