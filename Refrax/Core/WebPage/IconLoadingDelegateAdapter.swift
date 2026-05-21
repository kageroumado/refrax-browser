import AppKit
import WebKit

/// Adapter that implements WebKit's private `_WKIconLoadingDelegate` protocol.
///
/// This adapter provides efficient favicon detection by hooking into WebKit's
/// HTML parser:
/// - WebKit notifies us when it parses `<link rel="icon">` elements
/// - No need to wait for page load or execute JavaScript
/// - Works even when JavaScript is disabled
/// - WebKit handles the network request and provides the data
///
/// ## Icon Collection Strategy
///
/// We collect **all** icons WebKit discovers, categorizing them into:
///
/// - **Large** (>= 64px): For favorites grid
/// - **Small** (any size): For tabs/lists. Target 64px for 2x retina (32pt display).
///
/// ## Icon Priority
///
/// Icons are selected in order of quality:
/// 1. **SVG** (infinitely scalable, best quality)
/// 2. **Apple Touch Icons** (180px, designed for home screens)
/// 3. **Larger sizes first** (better for downscaling)
///
/// ## WebKit Callback Pattern
///
/// The `_WKIconLoadingDelegate` uses a double-completion-handler pattern:
/// 1. WebKit calls us with icon parameters and a completion handler
/// 2. We call the completion handler with our callback function
/// 3. WebKit loads the icon and calls our callback with the data
///
/// ## Usage
///
/// ```swift
/// let adapter = IconLoadingDelegateAdapter()
/// adapter.owner = self  // Set after WebPage init
/// adapter.attach(to: backingWebView)
/// ```
final class IconLoadingDelegateAdapter: NSObject, _WKIconLoadingDelegate {
    // MARK: - Constants

    /// Minimum pixel size for "large" category (32pt × 2 for retina).
    private static let largeThreshold: Int = 64

    /// Target size for small icon storage (32pt × 2 for retina).
    private nonisolated static let smallTargetSize: CGFloat = 64

    /// Target size for large icon storage (128pt, or larger for favorites grid).
    private nonisolated static let largeTargetSize: CGFloat = 180

    /// Scores an icon size for small icon selection.
    ///
    /// Downscaling looks better than upscaling, so icons >= target size always
    /// score higher than icons below target. Within each category:
    /// - >= target: prefer closer to target (less downscaling)
    /// - < target: prefer larger (less upscaling needed)
    ///
    /// Score ranges:
    /// - >= 64px: 1000+ (decreasing as size increases beyond target)
    /// - < 64px: 0-63 (the actual size)
    private func smallIconScore(_ size: Int) -> Int {
        let target = Int(Self.smallTargetSize)
        if size >= target {
            // All icons >= target beat all icons < target
            // Among >= target, prefer smaller (closer to target)
            return 1_000 + target - min(size, target + 500)
        } else {
            // Among < target, prefer larger
            return size
        }
    }

    // MARK: - Properties

    /// Reference to the owning WebPage for updating favicon state.
    weak var owner: WebPage?

    /// Tracks the best large icon seen during current navigation.
    private var bestLargeIcon: CollectedIcon?

    /// Tracks the best small icon seen during current navigation.
    private var bestSmallIcon: CollectedIcon?

    /// Pending update work item for debouncing.
    private var pendingUpdateWorkItem: DispatchWorkItem?

    /// Debounce delay for favicon updates.
    /// Gives WebKit time to deliver all icons before processing.
    private static let updateDebounceDelay: TimeInterval = 0.15

    /// Collected icon with metadata for comparison.
    private struct CollectedIcon {
        let url: URL
        let size: Int
        let isSVG: Bool
        let isAppleTouchIcon: Bool
        var data: Data?
    }

    // MARK: - Attachment

    /// Attaches the icon loading delegate to a WKWebView.
    ///
    /// - Parameter webView: The WKWebView to monitor for favicons.
    func attach(to webView: WKWebView) {
        resetForNavigation()
        webView._iconLoadingDelegate = self
    }

    /// Detaches from a WKWebView.
    func detach(from webView: WKWebView) {
        webView._iconLoadingDelegate = nil
        resetForNavigation()
    }

    /// Resets state for a new navigation.
    ///
    /// Call this when navigation starts to allow loading new favicons.
    func resetForNavigation() {
        pendingUpdateWorkItem?.cancel()
        pendingUpdateWorkItem = nil
        bestLargeIcon = nil
        bestSmallIcon = nil
    }
}

// MARK: - _WKIconLoadingDelegate Conformance

extension IconLoadingDelegateAdapter {
    /// Called when WebKit discovers an icon link in the page's HTML.
    ///
    /// This is called for each `<link rel="icon">` or `<link rel="apple-touch-icon">`
    /// element found during HTML parsing. We request ALL icons and categorize them
    /// as they arrive.
    @objc(webView:shouldLoadIconWithParameters:completionHandler:)
    func webView(
        _ webView: WKWebView,
        shouldLoadIconWithParameters parameters: _WKLinkIconParameters,
        completionHandler: @escaping (@escaping (Data?) -> Void) -> Void,
    ) {
        let iconType = parameters.iconType
        let iconURL = parameters.url
        let iconSize = parameters.size?.intValue ?? 0
        let isAppleTouchIcon = iconType == .touchIcon || iconType == .touchPrecomposedIcon

        // Always load the icon - we collect all of them
        completionHandler { [weak self, weak webView] iconData in
            guard let self, let iconData, !iconData.isEmpty else { return }

            // Validate it's actually an image (can be done off main thread)
            guard Self.isValidImageData(iconData) else {
                Logger.debug("Received invalid image data for favicon", category: Logger.navigation)
                return
            }

            // Get actual size from image data (can be done off main thread)
            let actualSize = Self.imageSize(from: iconData) ?? iconSize

            // WebKit callbacks may arrive on a background thread.
            // Dispatch to main for WKWebView access and shared state mutation.
            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView else { return }

                // Get the host from the page URL (not the icon URL)
                guard let host = webView.url?.host else { return }

                // Validate the favicon is for the current page's host
                guard let owner,
                      let currentHost = owner.url?.host?.lowercased(),
                      host.lowercased() == currentHost else {
                    return
                }

                // Categorize and potentially update our best icons
                processIcon(
                    url: iconURL,
                    data: iconData,
                    size: actualSize,
                    isAppleTouchIcon: isAppleTouchIcon,
                    host: host,
                    owner: owner,
                )
            }
        }
    }

    /// Processes a received icon, updating best small/large if it's better.
    private func processIcon(
        url: URL,
        data: Data,
        size: Int,
        isAppleTouchIcon: Bool,
        host: String,
        owner: WebPage,
    ) {
        let isSVG = Self.isSVG(data)
        let icon = CollectedIcon(url: url, size: size, isSVG: isSVG, isAppleTouchIcon: isAppleTouchIcon, data: data)

        // SVG is always considered "large" since it's infinitely scalable
        let isLarge = size >= Self.largeThreshold || isSVG

        if isLarge {
            if bestLargeIcon == nil || iconPriority(icon) > iconPriority(bestLargeIcon!) {
                bestLargeIcon = icon
            }
        }

        // Also consider for small icon (any icon can be downscaled for tabs)
        if bestSmallIcon == nil || smallIconPriority(icon) > smallIconPriority(bestSmallIcon!) {
            bestSmallIcon = icon
        }

        // Schedule debounced update - waits for all icons to arrive before processing
        scheduleOwnerUpdate(host: host, owner: owner)
    }

    /// Schedules a debounced update to the owner.
    ///
    /// Cancels any pending update and schedules a new one after the debounce delay.
    /// This ensures we only process once after all icons have arrived.
    private func scheduleOwnerUpdate(host: String, owner: WebPage) {
        pendingUpdateWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self, weak owner] in
            guard let self, let owner else { return }
            updateOwner(host: host, owner: owner)
        }
        pendingUpdateWorkItem = workItem

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.updateDebounceDelay, execute: workItem)
    }

    /// Calculates priority score for large icon selection.
    ///
    /// Priority order: SVG (highest) > Apple Touch Icon > larger size
    private func iconPriority(_ icon: CollectedIcon) -> Int {
        var score = icon.size

        if icon.isSVG {
            score += 100_000
        }
        if icon.isAppleTouchIcon {
            score += 10_000
        }

        return score
    }

    /// Calculates priority score for small icon selection.
    ///
    /// SVG always wins. Otherwise uses size scoring that prefers icons closest
    /// to target size (downscaling preferred over upscaling).
    private func smallIconPriority(_ icon: CollectedIcon) -> Int {
        if icon.isSVG {
            return 100_000
        }
        return smallIconScore(icon.size)
    }

    /// Updates the TabPage and cache with the current best icons.
    ///
    /// Image processing is performed on a background thread to avoid blocking the main thread.
    private func updateOwner(host: String, owner: WebPage) {
        guard let smallIconData = bestSmallIcon?.data else { return }
        let largeIconData = bestLargeIcon?.data

        Task.detached(priority: .utility) {
            let processedSmall = Self.processIconData(smallIconData, targetSize: Self.smallTargetSize)
            let processedLarge = largeIconData.map { Self.processIconData($0, targetSize: Self.largeTargetSize) }

            await MainActor.run {
                owner.tabPage.faviconData = processedSmall
                owner.tabPage.largeFaviconData = processedLarge
            }

            await owner.faviconCache.updateFavicon(forHost: host, small: processedSmall, large: processedLarge)
        }
    }

    // MARK: - Image Processing

    /// Extracts image dimensions from data by parsing image headers.
    ///
    /// This is more efficient than creating an NSImage as it only reads the header bytes.
    private static func imageSize(from data: Data) -> Int? {
        guard data.count >= 24 else { return nil }

        let bytes = [UInt8](data.prefix(32))

        // PNG: dimensions at bytes 16-23 (width: 16-19, height: 20-23, big-endian)
        if bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47 {
            let width = Int(bytes[16]) << 24 | Int(bytes[17]) << 16 | Int(bytes[18]) << 8 | Int(bytes[19])
            let height = Int(bytes[20]) << 24 | Int(bytes[21]) << 16 | Int(bytes[22]) << 8 | Int(bytes[23])
            return min(width, height)
        }

        // JPEG: Need to parse segments to find SOF marker
        if bytes[0] == 0xFF, bytes[1] == 0xD8 {
            return jpegSize(from: data)
        }

        // GIF: dimensions at bytes 6-9 (little-endian)
        if bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46 {
            let width = Int(bytes[6]) | Int(bytes[7]) << 8
            let height = Int(bytes[8]) | Int(bytes[9]) << 8
            return min(width, height)
        }

        // ICO: First image dimensions at bytes 6-7 (width, height; 0 means 256)
        if bytes[0] == 0x00, bytes[1] == 0x00, bytes[2] == 0x01, bytes[3] == 0x00 {
            let width = bytes[6] == 0 ? 256 : Int(bytes[6])
            let height = bytes[7] == 0 ? 256 : Int(bytes[7])
            return min(width, height)
        }

        // WebP: dimensions depend on format (VP8/VP8L/VP8X)
        if data.count >= 30,
           bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46,
           bytes[8] == 0x57, bytes[9] == 0x45, bytes[10] == 0x42, bytes[11] == 0x50 {
            return webpSize(from: data)
        }

        // SVG: parse viewBox or width/height attributes
        if let svgSize = svgSize(from: data) {
            return svgSize
        }

        return nil
    }

    /// Extracts SVG dimensions from viewBox or width/height attributes.
    ///
    /// Prefers viewBox dimensions since they represent actual content size,
    /// falling back to width/height attributes if viewBox is missing.
    /// Returns a large value for SVGs without explicit dimensions since
    /// they're infinitely scalable.
    private nonisolated static func svgSize(from data: Data) -> Int? {
        guard let str = String(data: data.prefix(1_024), encoding: .utf8),
              str.contains("<svg") else {
            return nil
        }

        // Try viewBox first (format: "minX minY width height")
        if let viewBoxMatch = str.range(of: #"viewBox\s*=\s*["']([^"']+)["']"#, options: .regularExpression),
           let valueRange = str.range(of: #"["'][^"']+["']"#, options: .regularExpression, range: viewBoxMatch) {
            let value = str[valueRange].dropFirst().dropLast() // Remove quotes
            let parts = value.split(whereSeparator: { $0.isWhitespace || $0 == "," })
            if parts.count >= 4,
               let width = Double(parts[2]),
               let height = Double(parts[3]) {
                return Int(min(width, height))
            }
        }

        // Fall back to width/height attributes (may have units like "px")
        var width: Double?
        var height: Double?

        if let widthMatch = str.range(of: #"width\s*=\s*["']([0-9.]+)"#, options: .regularExpression) {
            let valueStart = str[widthMatch].firstIndex(of: "\"") ?? str[widthMatch].firstIndex(of: "'")
            if let start = valueStart {
                let numStr = str[str.index(after: start)...].prefix(while: { $0.isNumber || $0 == "." })
                width = Double(numStr)
            }
        }

        if let heightMatch = str.range(of: #"height\s*=\s*["']([0-9.]+)"#, options: .regularExpression) {
            let valueStart = str[heightMatch].firstIndex(of: "\"") ?? str[heightMatch].firstIndex(of: "'")
            if let start = valueStart {
                let numStr = str[str.index(after: start)...].prefix(while: { $0.isNumber || $0 == "." })
                height = Double(numStr)
            }
        }

        if let w = width, let h = height {
            return Int(min(w, h))
        }

        // SVG without dimensions is infinitely scalable - treat as large
        return 512
    }

    /// Extracts JPEG dimensions by parsing SOF markers.
    private static func jpegSize(from data: Data) -> Int? {
        var offset = 2
        while offset < data.count - 9 {
            guard data[offset] == 0xFF else { return nil }

            let marker = data[offset + 1]

            // SOF markers (0xC0-0xCF except 0xC4, 0xC8, 0xCC)
            if marker >= 0xC0, marker <= 0xCF, marker != 0xC4, marker != 0xC8, marker != 0xCC {
                let height = Int(data[offset + 5]) << 8 | Int(data[offset + 6])
                let width = Int(data[offset + 7]) << 8 | Int(data[offset + 8])
                return min(width, height)
            }

            // Skip to next marker
            if marker == 0xD8 || marker == 0xD9 || (marker >= 0xD0 && marker <= 0xD7) {
                offset += 2
            } else {
                let length = Int(data[offset + 2]) << 8 | Int(data[offset + 3])
                offset += 2 + length
            }
        }
        return nil
    }

    /// Extracts WebP dimensions.
    private static func webpSize(from data: Data) -> Int? {
        guard data.count >= 30 else { return nil }

        // Check VP8 chunk type at offset 12
        let chunk = String(bytes: data[12 ..< 16], encoding: .ascii)

        switch chunk {
        case "VP8 ":
            // Lossy: dimensions at offset 26-29
            guard data.count >= 30 else { return nil }
            let width = Int(data[26]) | (Int(data[27] & 0x3F) << 8)
            let height = Int(data[28]) | (Int(data[29] & 0x3F) << 8)
            return min(width, height)

        case "VP8L":
            // Lossless: dimensions encoded in first 4 bytes after signature
            guard data.count >= 25 else { return nil }
            let bits = UInt32(data[21]) | UInt32(data[22]) << 8 | UInt32(data[23]) << 16 | UInt32(data[24]) << 24
            let width = Int(bits & 0x3FFF) + 1
            let height = Int((bits >> 14) & 0x3FFF) + 1
            return min(width, height)

        case "VP8X":
            // Extended: dimensions at offset 24-29
            guard data.count >= 30 else { return nil }
            let width = Int(data[24]) | Int(data[25]) << 8 | Int(data[26]) << 16
            let height = Int(data[27]) | Int(data[28]) << 8 | Int(data[29]) << 16
            return min(width + 1, height + 1)

        default:
            return nil
        }
    }

    /// Validates that the data is a recognized image format.
    private static func isValidImageData(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }

        let bytes = [UInt8](data.prefix(12))

        // PNG: 89 50 4E 47
        if bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47 {
            return true
        }

        // JPEG: FF D8
        if bytes[0] == 0xFF, bytes[1] == 0xD8 {
            return true
        }

        // GIF: 47 49 46
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

    /// Processes icon data, resizing if necessary.
    ///
    /// - Parameters:
    ///   - data: Raw icon data.
    ///   - targetSize: Target size in pixels (e.g., 64 for small, 180 for large).
    /// - Returns: Processed PNG data at target size.
    private nonisolated static func processIconData(_ data: Data, targetSize: CGFloat) -> Data {
        if isSVG(data) {
            return processSVGData(data, targetSize: targetSize)
        }

        guard let image = NSImage(data: data) else { return data }

        let size = image.size

        // Only resize if larger than target (downscaling is fine, upscaling loses quality)
        guard size.width > targetSize || size.height > targetSize else {
            // Already smaller - just convert to PNG for consistency
            if let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                return pngData
            }
            return data
        }

        // Calculate new size maintaining aspect ratio
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

        guard let tiffData = resizedImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            return data
        }

        return pngData
    }

    /// Checks if data is SVG format.
    private nonisolated static func isSVG(_ data: Data) -> Bool {
        guard let str = String(data: data.prefix(256), encoding: .utf8) else {
            return false
        }
        return str.contains("<svg")
    }

    /// Processes SVG data by rendering at target size.
    ///
    /// SVG's declared width/height may be tiny (e.g., 18px) even when the viewBox
    /// defines high-resolution content. We render directly at target size to get
    /// crisp output regardless of declared dimensions.
    private nonisolated static func processSVGData(_ data: Data, targetSize: CGFloat) -> Data {
        guard let image = NSImage(data: data) else { return data }

        // Render at target size (SVG will scale up cleanly, favicons are typically square)
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

        guard let tiffData = renderedImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            return data
        }

        return pngData
    }
}
