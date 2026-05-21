import AppKit
import Foundation

/// Stateless utility for fetching website favicons without a WebView.
///
/// ## When to Use
///
/// Use `FaviconService` **only** when a `WKWebView` is not available:
/// - Fetching favicons for bookmarks that haven't been visited
/// - Prefetching favicons for URLs before navigation
/// - Loading favicons for imported bookmarks
///
/// ## When NOT to Use
///
/// When a page is loaded in a `WKWebView`, use `IconLoadingDelegateAdapter` instead.
/// WebKit's native icon loading is superior because it:
/// - Receives icons as WebKit parses them (no extra network request)
/// - Handles JavaScript-injected icons
/// - Works with dynamically loaded icons
///
/// ## How It Works
///
/// 1. **Parse HTML** - Fetches the first 16KB of the page and extracts
///    `<link rel="icon">` URLs. This discovers icons at custom paths.
///
/// 2. **Icon Priority** - Icons are selected in order of quality:
///    - **SVG** (infinitely scalable, best quality)
///    - **Apple Touch Icons** (180px, designed for home screens)
///    - **Larger sizes first** (better for downscaling)
///
/// 3. **Fallback Paths** - If HTML parsing fails, tries well-known paths:
///    - `/favicon.svg`
///    - `/apple-touch-icon.png` and variants
///    - `/favicon-32x32.png`, `/favicon.ico`
///
/// ## Usage
///
/// ```swift
/// // Fetch best available favicon
/// if let data = try await FaviconService.fetchFavicon(for: url) {
///     bookmark.faviconData = data
/// }
///
/// // Fetch both sizes for caching
/// let (small, large) = try await FaviconService.fetchFavicons(for: url)
/// ```
enum FaviconService {
    // MARK: - Size Thresholds

    /// Minimum pixel size for "large" category (for 2x retina, 32pt display = 64px).
    private static let largeThreshold: Int = 64

    // MARK: - Well-Known Paths

    /// Large icon paths (>= 64px), in order of preference.
    ///
    /// Apple Touch Icons are preferred for favorites grid (high quality, square).
    /// Then PWA/Android icons, Windows tiles, and other modern formats.
    private static let largeIconPaths: [(path: String, expectedSize: Int)] = [
        // Apple Touch Icons (preferred for favorites grid - highest quality)
        ("/apple-touch-icon.png", 180),
        ("/apple-touch-icon-precomposed.png", 180),
        ("/apple-touch-icon-180x180.png", 180),
        ("/apple-touch-icon-152x152.png", 152),
        ("/apple-touch-icon-144x144.png", 144),
        ("/apple-touch-icon-120x120.png", 120),
        ("/apple-touch-icon-114x114.png", 114),
        ("/apple-touch-icon-76x76.png", 76),

        // PWA/Android icons (good quality, square)
        ("/icon-512x512.png", 512),
        ("/icon-192x192.png", 192),
        ("/android-chrome-512x512.png", 512),
        ("/android-chrome-192x192.png", 192),
        ("/favicon-192x192.png", 192),

        // Windows tiles
        ("/mstile-310x310.png", 310),
        ("/mstile-150x150.png", 150),
        ("/mstile-144x144.png", 144),

        // Other modern sizes
        ("/favicon-96x96.png", 96),
    ]

    /// Small icon paths, in order of preference.
    ///
    /// SVG is preferred because it's infinitely scalable and can be rendered
    /// at any size. Falls back to raster formats.
    private static let smallIconPaths: [(path: String, expectedSize: Int)] = [
        ("/favicon.svg", 0), // SVG preferred - infinitely scalable
        ("/favicon-32x32.png", 32),
        ("/favicon-16x16.png", 16),
        ("/favicon.ico", 32), // Often contains multiple sizes
    ]

    // MARK: - Public Interface

    /// Fetches the best available favicon for a URL.
    ///
    /// Tries large icons first (Apple Touch Icons, PWA icons), then falls back
    /// to smaller icons. Returns the first valid icon found.
    ///
    /// - Parameter url: The website URL to fetch favicon from.
    /// - Returns: Favicon image data, or nil if unavailable.
    static func fetchFavicon(for url: URL) async throws -> Data? {
        // Try large icons first (higher quality)
        if let largeIcon = await fetchLargeIcon(from: url) {
            return largeIcon
        }

        // Fall back to small icons
        if let smallIcon = await fetchSmallIcon(from: url) {
            return smallIcon
        }

        return nil
    }

    /// Fetches favicons at multiple sizes for caching.
    ///
    /// Fetches both small (≤64px, for tabs/lists) and large (>64px, for favorites
    /// grid) icons in parallel. Either may be nil if unavailable.
    ///
    /// For "small", we actually target 64px to support 2x retina (32pt × 2).
    /// For "large", we prefer Apple Touch Icons (180px) for the favorites grid.
    ///
    /// Icons are processed before returning:
    /// - SVGs are rendered at target size (not their declared size)
    /// - Large images are downscaled to target size
    /// - Output is PNG format for consistency
    ///
    /// - Parameter url: The website URL to fetch favicons from.
    /// - Returns: Tuple of (small, large) processed favicon PNG data.
    static func fetchFavicons(for url: URL) async throws -> (small: Data?, large: Data?) {
        // First try: Parse HTML to find actual icon URLs (handles custom paths like /y18.svg)
        let parsedIconURLs = await parseIconURLsFromHTML(for: url)

        var largeRaw: Data?
        var smallRaw: Data?

        // Try fetching from parsed URLs first
        for iconURL in parsedIconURLs {
            guard let data = await fetchIcon(from: iconURL) else { continue }

            // Determine if this is suitable for large or small based on actual size
            let size = await imageSize(from: data)
            let isLarge = (size ?? 0) >= largeThreshold || isSVG(data)

            if isLarge, largeRaw == nil {
                largeRaw = data
            }
            if smallRaw == nil {
                smallRaw = data
            }

            // Stop if we have both
            if largeRaw != nil, smallRaw != nil { break }
        }

        // Fallback: Try well-known paths if HTML parsing didn't find icons
        if largeRaw == nil {
            largeRaw = await fetchLargeIcon(from: url)
        }
        if smallRaw == nil {
            smallRaw = await fetchSmallIcon(from: url)
        }

        // If no large icon found but small is SVG, use SVG for large too (infinitely scalable)
        if largeRaw == nil, let smallData = smallRaw, isSVG(smallData) {
            largeRaw = smallData
        }

        // Process icons off MainActor (render SVG at target size, convert to PNG)
        // Capture target sizes before entering detached task (they're MainActor-isolated)
        let largeSz = largeTargetSize
        let smallSz = smallTargetSize
        let (large, small) = await Task.detached {
            let processedLarge = largeRaw.map { Self.processIconData($0, targetSize: largeSz) }
            let processedSmall = smallRaw.map { Self.processIconData($0, targetSize: smallSz) }
            return (processedLarge, processedSmall)
        }.value

        return (small, large)
    }

    // MARK: - Target Sizes

    /// Target size for small icons (32pt × 2 for retina).
    private static let smallTargetSize: CGFloat = 64

    /// Target size for large icons (favorites grid).
    private static let largeTargetSize: CGFloat = 180

    // MARK: - Private Implementation

    /// Fetches the best large icon (>= 64px) from well-known paths.
    ///
    /// Apple Touch Icons are preferred because they're designed for home screen
    /// bookmarks and look best in the favorites grid.
    private static func fetchLargeIcon(from url: URL) async -> Data? {
        guard let host = url.host else { return nil }
        guard let baseURL = URL(string: "https://\(host)") else { return nil }

        // Try large icon paths in preference order
        for (path, _) in largeIconPaths {
            if let iconURL = URL(string: path, relativeTo: baseURL),
               let data = await fetchIcon(from: iconURL) {
                // Validate it's actually a reasonable size
                let size = await imageSize(from: data)
                if size == nil || size! >= largeThreshold {
                    // If we can't determine size, trust the path naming
                    return data
                }
            }
        }

        return nil
    }

    /// Fetches a small icon suitable for tabs and lists.
    ///
    /// For 2x retina displays, we want at least 64px (32pt × 2).
    private static func fetchSmallIcon(from url: URL) async -> Data? {
        guard let host = url.host else { return nil }
        guard let baseURL = URL(string: "https://\(host)") else { return nil }

        // Try small icon paths
        for (path, _) in smallIconPaths {
            if let iconURL = URL(string: path, relativeTo: baseURL),
               let data = await fetchIcon(from: iconURL) {
                return data
            }
        }

        return nil
    }

    // MARK: - HTML Parsing

    /// Fetches the HTML head and parses icon URLs from link elements.
    ///
    /// This discovers favicons at custom paths like `/y18.svg` that can't be
    /// guessed from well-known paths. Only fetches the first ~16KB of HTML.
    ///
    /// - Parameter url: The page URL to fetch.
    /// - Returns: Parsed icon URLs sorted by preference (apple-touch-icon first, then by size).
    private static func parseIconURLsFromHTML(for url: URL) async -> [URL] {
        guard let host = url.host else { return [] }
        guard let pageURL = URL(string: "https://\(host)") else { return [] }

        do {
            var request = URLRequest(url: pageURL)
            request.timeoutInterval = 5
            // Request only first 16KB - enough for <head> section
            request.setValue("bytes=0-16383", forHTTPHeaderField: "Range")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ... 206).contains(httpResponse.statusCode)
            else {
                return []
            }

            guard let html = String(data: data.prefix(16_384), encoding: .utf8) else {
                return []
            }

            return parseIconURLs(from: html, baseURL: pageURL)
        } catch {
            return []
        }
    }

    /// Parses `<link rel="icon">` and `<link rel="apple-touch-icon">` from HTML.
    private static func parseIconURLs(from html: String, baseURL: URL) -> [URL] {
        // Match <link> tags with rel containing "icon"
        let linkPattern = #"<link\s+[^>]*rel\s*=\s*["']([^"']*icon[^"']*)["'][^>]*>"#
        guard let linkRegex = try? NSRegularExpression(pattern: linkPattern, options: .caseInsensitive) else {
            return []
        }

        let range = NSRange(html.startIndex ..< html.endIndex, in: html)
        let matches = linkRegex.matches(in: html, options: [], range: range)

        var icons: [(url: URL, isSVG: Bool, isAppleTouchIcon: Bool, size: Int)] = []

        for match in matches {
            guard let relRange = Range(match.range(at: 1), in: html),
                  let matchRange = Range(match.range, in: html)
            else {
                continue
            }

            let rel = String(html[relRange]).lowercased()
            let linkTag = String(html[matchRange])

            guard let href = extractAttribute("href", from: linkTag),
                  let iconURL = URL(string: href, relativeTo: baseURL)
            else {
                continue
            }

            let size = extractAttribute("sizes", from: linkTag)
                .flatMap { $0.split(separator: "x").first }
                .flatMap { Int($0) } ?? 0

            icons.append((
                url: iconURL,
                isSVG: href.lowercased().hasSuffix(".svg"),
                isAppleTouchIcon: rel.contains("apple-touch-icon"),
                size: size,
            ))
        }

        // Sort: SVG first, then apple-touch-icons, then by size descending
        icons.sort { lhs, rhs in
            if lhs.isSVG != rhs.isSVG { return lhs.isSVG }
            if lhs.isAppleTouchIcon != rhs.isAppleTouchIcon { return lhs.isAppleTouchIcon }
            return lhs.size > rhs.size
        }

        return icons.map(\.url)
    }

    /// Extracts an HTML attribute value from a tag string.
    private static func extractAttribute(_ name: String, from tag: String) -> String? {
        let pattern = #"\#(name)\s*=\s*["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: tag, options: [], range: NSRange(tag.startIndex..., in: tag)),
              let valueRange = Range(match.range(at: 1), in: tag)
        else {
            return nil
        }
        return String(tag[valueRange])
    }

    /// Fetches icon data from a URL with validation.
    private static func fetchIcon(from url: URL) async -> Data? {
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                return nil
            }

            guard !data.isEmpty, isValidImageData(data) else {
                return nil
            }

            return data
        } catch {
            return nil
        }
    }

    /// Extracts the dimensions of an image from its data.
    ///
    /// For SVG, parses viewBox to get actual content size (not declared width/height).
    /// Returns the smaller dimension (for non-square images).
    ///
    /// - Note: Image decoding is performed off the main thread via `Task.detached`
    ///   since `NSImage(data:)` is CPU-intensive.
    private static func imageSize(from data: Data) async -> Int? {
        // Check for SVG first - parse viewBox for true dimensions (no NSImage needed)
        if let svgSize = svgSize(from: data) {
            return svgSize
        }

        // Decode image off main thread
        return await Task.detached(priority: .utility) {
            guard let image = NSImage(data: data) else { return nil }
            let size = image.size
            return Int(min(size.width, size.height))
        }.value
    }

    /// Extracts SVG dimensions from viewBox or width/height attributes.
    private static func svgSize(from data: Data) -> Int? {
        guard let str = String(data: data.prefix(1_024), encoding: .utf8),
              str.contains("<svg") else {
            return nil
        }

        // Try viewBox first (format: "minX minY width height")
        if let viewBoxMatch = str.range(of: #"viewBox\s*=\s*["']([^"']+)["']"#, options: .regularExpression),
           let valueRange = str.range(of: #"["'][^"']+["']"#, options: .regularExpression, range: viewBoxMatch) {
            let value = str[valueRange].dropFirst().dropLast()
            let parts = value.split(whereSeparator: { $0.isWhitespace || $0 == "," })
            if parts.count >= 4,
               let width = Double(parts[2]),
               let height = Double(parts[3]) {
                return Int(min(width, height))
            }
        }

        // SVG without viewBox - treat as scalable/large
        return 512
    }

    // MARK: - Image Processing

    /// Processes icon data, resizing and converting to PNG.
    ///
    /// For SVG, renders at target size regardless of declared dimensions.
    /// For raster formats, downscales if larger than target.
    ///
    /// - Note: This is `nonisolated` to run off the MainActor. Image processing
    ///   with `lockFocus()`/`unlockFocus()` creates a thread-local graphics context
    ///   and is safe on background threads since macOS 10.6.
    private nonisolated static func processIconData(_ data: Data, targetSize: CGFloat) -> Data {
        if isSVG(data) {
            return processSVGData(data, targetSize: targetSize)
        }

        guard let image = NSImage(data: data) else { return data }

        let size = image.size

        // Only resize if larger than target
        guard size.width > targetSize || size.height > targetSize else {
            return convertToPNG(image) ?? data
        }

        // Downscale to target size
        let scale = min(targetSize / size.width, targetSize / size.height)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)

        let resizedImage = NSImage(size: newSize)
        resizedImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: newSize),
            from: NSRect(origin: .zero, size: size),
            operation: .copy,
            fraction: 1.0,
        )
        resizedImage.unlockFocus()

        return convertToPNG(resizedImage) ?? data
    }

    /// Checks if data is SVG format.
    private nonisolated static func isSVG(_ data: Data) -> Bool {
        guard let str = String(data: data.prefix(256), encoding: .utf8) else {
            return false
        }
        return str.contains("<svg")
    }

    /// Renders SVG at target size.
    ///
    /// SVG's declared width/height may be tiny even when viewBox is large.
    /// We render at target size to get crisp output.
    private nonisolated static func processSVGData(_ data: Data, targetSize: CGFloat) -> Data {
        guard let image = NSImage(data: data) else { return data }

        let renderSize = NSSize(width: targetSize, height: targetSize)

        let renderedImage = NSImage(size: renderSize)
        renderedImage.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(
            in: NSRect(origin: .zero, size: renderSize),
            from: NSRect(origin: .zero, size: image.size),
            operation: .copy,
            fraction: 1.0,
        )
        renderedImage.unlockFocus()

        return convertToPNG(renderedImage) ?? data
    }

    /// Converts an NSImage to PNG data.
    private nonisolated static func convertToPNG(_ image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    /// Validates that data appears to be a recognized image format.
    ///
    /// Checks magic bytes for PNG, JPEG, GIF, ICO, WebP, and SVG formats.
    private static func isValidImageData(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }

        let bytes = [UInt8](data.prefix(12))

        // PNG: 89 50 4E 47 (.PNG)
        if bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47 {
            return true
        }

        // JPEG: FF D8 FF
        if bytes[0] == 0xFF, bytes[1] == 0xD8 {
            return true
        }

        // GIF: 47 49 46 (GIF)
        if bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46 {
            return true
        }

        // ICO: 00 00 01 00
        if bytes[0] == 0x00, bytes[1] == 0x00, bytes[2] == 0x01, bytes[3] == 0x00 {
            return true
        }

        // WebP: RIFF....WEBP
        if data.count >= 12,
           bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46,
           bytes[8] == 0x57, bytes[9] == 0x45, bytes[10] == 0x42, bytes[11] == 0x50 {
            return true
        }

        // SVG: Check for XML declaration or svg tag
        if let str = String(data: data.prefix(256), encoding: .utf8) {
            if str.contains("<?xml") || str.contains("<svg") {
                return true
            }
        }

        return false
    }
}
