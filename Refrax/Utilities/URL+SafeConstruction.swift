import Foundation

extension URL {
    /// Constructs a `URL` from a compile-time string literal that is required to be valid.
    ///
    /// Use this for URLs that are hardcoded in source (e.g., well-known API endpoints,
    /// bundled resource URLs). Traps with a descriptive message if the literal is
    /// malformed — producing a named, symbolicated crash site rather than an anonymous
    /// trap inside Swift runtime glue.
    ///
    /// - Parameter string: A compile-time URL literal.
    /// - Returns: The parsed URL.
    nonisolated static func staticRequired(_ string: StaticString) -> URL {
        let literal = string.withUTF8Buffer { buffer -> String in
            String(decoding: buffer, as: UTF8.self)
        }
        guard let url = URL(string: literal) else {
            preconditionFailure("Malformed URL literal: \(literal)")
        }
        return url
    }

    /// Constructs a `URL` from a runtime string, logging and returning a fallback on failure.
    ///
    /// Use this for URLs assembled from dynamic sources (config values, server responses,
    /// user input, SwiftData). Never traps — logs a warning and returns `fallback` when the
    /// string is malformed so launch-time and hot paths degrade gracefully.
    ///
    /// - Parameters:
    ///   - string: The runtime URL string.
    ///   - fallback: URL to return when `string` cannot be parsed.
    ///   - context: Short label included in the warning log for diagnostics.
    /// - Returns: The parsed URL, or `fallback` on failure.
    nonisolated static func dynamicOrFallback(
        _ string: String,
        fallback: URL,
        context: String,
    ) -> URL {
        if let url = URL(string: string) {
            return url
        }
        Logger.warning(
            "Malformed URL in \(context), using fallback: \(string)",
            category: Logger.network,
        )
        return fallback
    }

    /// A safe `about:blank` URL used as a last-resort fallback.
    nonisolated static let safeBlank = URL.staticRequired("about:blank")
}

extension URLComponents {
    /// Resolves `self.url`, trapping with a descriptive message if resolution fails.
    ///
    /// Only use when the components are built from compile-time-constant inputs
    /// where failure would indicate a programmer error.
    ///
    /// - Parameter context: Short label included in the trap message for diagnostics.
    /// - Returns: The resolved URL.
    nonisolated func resolvedRequired(_ context: StaticString) -> URL {
        guard let resolved = url else {
            preconditionFailure("URLComponents produced no URL at \(context)")
        }
        return resolved
    }
}
