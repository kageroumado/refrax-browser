import AppKit
import Observation
import WebKit

/// Samples colors from the left edge of a WebView for the compact sidebar edge extension.
///
/// ## Overview
///
/// `WebViewEdgeSampler` extracts dominant colors from the left edge of the content area
/// using GPU-accelerated window capture (`CGSHWCaptureWindowList`). This reads directly
/// from WindowServer's GPU textures — the same API Safari uses for tab snapshots — avoiding
/// the IPC round-trip of `WKWebView.takeSnapshot()`.
///
/// The GPU path captures a vertical strip of the composited window at the web view's left
/// edge position. This naturally handles split views where multiple web views occupy the
/// same vertical space, as the composited result includes all visible content.
///
/// Falls back to `WKWebView.takeSnapshot()` if the GPU capture is unavailable (e.g.,
/// window not visible, web view not in hierarchy).
///
/// ## Sampling Strategy
///
/// 1. Captures a 56px-wide strip from the composited window at the web view's left edge
/// 2. Applies corner masking if the content area has rounded corners (top-left, bottom-left)
/// 3. Divides the height into vertical regions (default: 12)
/// 4. For each region, computes a weighted average color while filtering out:
///    - Dark pixels (likely text) on light backgrounds
///    - Bright pixels (likely text) on dark backgrounds
///
/// ## Debouncing
///
/// Sampling is debounced to avoid excessive snapshot operations:
/// - 200ms delay after scroll/navigation events
@Observable @MainActor
final class WebViewEdgeSampler {
    // MARK: - Public State

    /// Colors sampled from the full width of the edge region (56px, blurred).
    ///
    /// Array of colors from top to bottom of the visible viewport.
    /// Empty if no sampling has occurred.
    private(set) var fullWidthColors: [NSColor] = []

    /// Colors sampled from the ultra-narrow edge strip (first 2px from the left).
    ///
    /// These colors are less likely to contain icons/text and are used for the
    /// mirrored edge strip that sits adjacent to the webview.
    private(set) var edgeStripColors: [NSColor] = []

    /// Colors sampled from the near-edge region (first ~8px from the left).
    ///
    /// Used for progressive blending between the narrow edge and wider samples.
    private(set) var nearEdgeColors: [NSColor] = []

    /// Colors sampled from the mid-edge region (first ~20px from the left).
    ///
    /// Used for progressive blending between the narrow edge and wider samples.
    private(set) var midEdgeColors: [NSColor] = []

    /// Color sampled specifically from the top corner (top 8px of viewport).
    ///
    /// Uses precise averaging (not histogram binning) for pixel-perfect accuracy
    /// in the exposed corner area where there's no glass blur.
    private(set) var topCornerColor: NSColor?

    /// Color sampled specifically from the bottom corner (bottom 8px of viewport).
    ///
    /// Uses precise averaging (not histogram binning) for pixel-perfect accuracy
    /// in the exposed corner area where there's no glass blur.
    private(set) var bottomCornerColor: NSColor?

    /// Whether a sampling operation is currently in progress.
    private(set) var isSampling: Bool = false

    // MARK: - Private State

    @ObservationIgnored
    private var currentTask: Task<Void, Never>?

    @ObservationIgnored
    private var lastSampledPageID: UUID?

    // MARK: - Configuration

    /// Corner radius of the content area's top-left and bottom-left clipping.
    ///
    /// When the content area has rounded corners (e.g., 26px in non-compact sidebar mode),
    /// the GPU capture will include window background pixels in those corners. This radius
    /// is used to mask them out before color extraction.
    ///
    /// In compact sidebar mode this is 0 (no rounded corners). Set by the window controller
    /// based on the current sidebar mode.
    @ObservationIgnored
    var contentCornerRadius: CGFloat = 0

    // MARK: - Constants

    private enum Constants {
        /// Width of the edge region to sample (matches compact sidebar total width)
        static let sampleWidth: CGFloat = 56

        /// Width of the ultra-narrow edge strip to sample (in points, before scaling).
        ///
        /// This narrow strip is unlikely to contain icons/text, providing cleaner
        /// colors for the edge adjacent to the webview.
        static let edgeStripWidth: CGFloat = 2

        /// Width of the near-edge region to sample (in points, before scaling).
        ///
        /// Intermediate width for progressive blending.
        static let nearEdgeWidth: CGFloat = 8

        /// Width of the mid-edge region to sample (in points, before scaling).
        ///
        /// Wider sample for progressive blending further from the edge.
        static let midEdgeWidth: CGFloat = 20

        /// Height of corner edge to sample (just the very edge for accurate color)
        static let cornerSampleHeight: CGFloat = 8

        /// Number of vertical regions to divide the viewport into.
        ///
        /// Higher count provides finer granularity for better edge matching.
        static let regionCount: Int = 12

        static let downsampleSize: Int = 8

        /// Scale factor for the CPU fallback snapshot (lower = faster but less precise).
        /// Only used when GPU capture is unavailable.
        static let snapshotScale: CGFloat = 0.5

        /// Brightness threshold (0-255) for filtering content pixels on light backgrounds.
        ///
        /// On light backgrounds, dark pixels are likely content (text, icons).
        /// Pixels below this threshold are filtered out.
        static let lightModeMinBrightness: Int = 40

        /// Brightness threshold (0-255) for filtering content pixels on dark backgrounds.
        ///
        /// On dark backgrounds, bright pixels are likely content (text, icons).
        /// Pixels above this threshold are filtered out.
        static let darkModeMaxBrightness: Int = 215

        /// Threshold (0-255) to determine if background is dark or light.
        ///
        /// Computed from the average brightness of the 2px edge strip.
        /// Below this = dark mode (prefer dark pixels), above = light mode (prefer light pixels).
        static let darkBackgroundThreshold: Int = 100

        /// Weight multiplier for brightness-based color averaging.
        ///
        /// Higher values = stronger preference for background-like colors.
        static let brightnessWeightPower: CGFloat = 2.0
    }

    // MARK: - Initialization

    init() {}

    isolated deinit {
        currentTask?.cancel()
    }

    // MARK: - Public API

    /// Samples edge colors from the specified webpage.
    ///
    /// With the GPU capture path, sampling is fast enough to call directly on every
    /// scroll event without debouncing or throttling.
    ///
    /// - Parameter webPage: The webpage to sample colors from.
    func sampleEdgeColors(from webPage: WebPage) {
        performSampling(from: webPage)
    }

    /// Checks if re-sampling is needed for a different page.
    func shouldResample(pageID: UUID) -> Bool {
        pageID != lastSampledPageID
    }

    /// Clears the sampled colors.
    func clearColors() {
        currentTask?.cancel()
        fullWidthColors = []
        edgeStripColors = []
        nearEdgeColors = []
        midEdgeColors = []
        topCornerColor = nil
        bottomCornerColor = nil
        lastSampledPageID = nil
    }

    // MARK: - Private Implementation

    private func performSampling(from webPage: WebPage) {
        currentTask?.cancel()
        currentTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await doSampling(from: webPage)
        }
    }

    @MainActor
    private func doSampling(from webPage: WebPage) async {
        isSampling = true
        defer { isSampling = false }

        let wkWebView = webPage.backingWebView

        let viewportHeight = wkWebView.bounds.height
        guard viewportHeight > 0 else { return }

        // Wait for WebKit to commit the latest frame before capturing. Without this,
        // CGSHWCaptureWindowList may read a stale composited frame (e.g., pre-scroll content)
        // because it reads from WindowServer's texture, not from WebKit's render pipeline.
        // This is lightweight — no image creation, just a presentation sync.
        await wkWebView.waitForPresentationUpdate()
        guard !Task.isCancelled else { return }

        // Try GPU path: capture from WindowServer's GPU textures after the sync.
        // Much faster than takeSnapshot() which creates a new image via IPC.
        if let gpuImage = captureLeftEdgeGPU(webView: wkWebView) {
            guard !Task.isCancelled else { return }

            let scale = wkWebView.window?.backingScaleFactor ?? 2.0
            let result = extractColors(
                from: gpuImage,
                scale: scale,
                regionCount: Constants.regionCount,
                cornerSampleHeight: Constants.cornerSampleHeight,
                edgeStripWidth: Constants.edgeStripWidth,
            )

            guard !Task.isCancelled else { return }

            applyResult(result, pageID: webPage.id)
            return
        }

        // Fall back to CPU snapshot path (async IPC to web process)
        let config = WKSnapshotConfiguration()
        config.rect = CGRect(
            x: 0,
            y: 0,
            width: Constants.sampleWidth,
            height: viewportHeight,
        )
        config.snapshotWidth = NSNumber(value: Int(Constants.sampleWidth * Constants.snapshotScale))

        do {
            let snapshot = try await wkWebView.takeSnapshot(configuration: config)

            guard !Task.isCancelled else { return }

            guard let cgImage = snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return
            }

            let result = extractColors(
                from: cgImage,
                scale: Constants.snapshotScale,
                regionCount: Constants.regionCount,
                cornerSampleHeight: Constants.cornerSampleHeight,
                edgeStripWidth: Constants.edgeStripWidth,
            )

            guard !Task.isCancelled else { return }

            applyResult(result, pageID: webPage.id)
        } catch {
            Logger.debug("Edge sampling failed: \(error)", category: Logger.ui)
        }
    }

    /// Applies extraction result to the published properties.
    private func applyResult(_ result: ExtractionResult, pageID: UUID) {
        fullWidthColors = result.colors
        edgeStripColors = result.edgeStripColors
        nearEdgeColors = result.nearEdgeColors
        midEdgeColors = result.midEdgeColors
        topCornerColor = result.topColor
        bottomCornerColor = result.bottomColor
        lastSampledPageID = pageID
    }

    /// Result of extracting colors from a snapshot.
    private struct ExtractionResult {
        /// Gradient colors from top to bottom (sampled from full width).
        let colors: [NSColor]
        /// Edge strip colors from top to bottom (sampled from narrow 2px left edge).
        let edgeStripColors: [NSColor]
        /// Near-edge colors from top to bottom (sampled from ~8px left edge).
        let nearEdgeColors: [NSColor]
        /// Mid-edge colors from top to bottom (sampled from ~20px left edge).
        let midEdgeColors: [NSColor]
        /// Color for the top corner region (precise average, not histogram).
        let topColor: NSColor?
        /// Color for the bottom corner region (precise average, not histogram).
        let bottomColor: NSColor?
    }

    /// Extracts dominant colors from vertical regions of an image at multiple horizontal depths.
    ///
    /// - Parameters:
    ///   - cgImage: The image to analyze (GPU capture or CPU snapshot).
    ///   - scale: Scale factor mapping points to pixels. For GPU captures this is the
    ///     window's `backingScaleFactor` (e.g. 2.0). For CPU snapshots it's `snapshotScale` (0.5).
    ///   - regionCount: Number of vertical regions for the gradient.
    ///   - cornerSampleHeight: Height in points of the corner edges to sample (typically 8).
    ///   - edgeStripWidth: Width in points of the narrow edge strip to sample (typically 2).
    /// - Returns: Extraction result containing gradient colors at multiple depths and corner colors.
    private func extractColors(
        from cgImage: CGImage,
        scale: CGFloat,
        regionCount: Int,
        cornerSampleHeight: CGFloat,
        edgeStripWidth: CGFloat,
    ) -> ExtractionResult {
        let emptyResult = ExtractionResult(
            colors: [],
            edgeStripColors: [],
            nearEdgeColors: [],
            midEdgeColors: [],
            topColor: nil,
            bottomColor: nil,
        )

        let width = cgImage.width
        let height = cgImage.height
        let regionHeight = height / regionCount

        guard regionHeight > 0 else {
            return emptyResult
        }

        // Create bitmap context to read pixel data
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else {
            return emptyResult
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Calculate pixel widths for each sampling depth using the image's scale factor
        let scaledCornerSampleHeight = Int(cornerSampleHeight * scale)
        let scaledEdgeStripWidth = max(1, Int(edgeStripWidth * scale))
        let scaledNearEdgeWidth = max(1, Int(Constants.nearEdgeWidth * scale))
        let scaledMidEdgeWidth = max(1, Int(Constants.midEdgeWidth * scale))

        // First, compute average brightness of the entire 2px edge strip to determine dark/light mode
        let edgeStripBrightness = computeAverageBrightness(
            pixelData: pixelData,
            startX: 0,
            endX: scaledEdgeStripWidth,
            startY: 0,
            endY: height,
            bytesPerPixel: bytesPerPixel,
            bytesPerRow: bytesPerRow,
        )
        let isDarkBackground = edgeStripBrightness < Constants.darkBackgroundThreshold

        // Top corner: use PRECISE averaging for pixel-perfect color in exposed corner area
        let topColor = computePreciseAverageColor(
            pixelData: pixelData,
            startX: 0,
            endX: scaledEdgeStripWidth,
            startY: 0,
            endY: min(scaledCornerSampleHeight, height),
            bytesPerPixel: bytesPerPixel,
            bytesPerRow: bytesPerRow,
        )

        // Bottom corner: use PRECISE averaging for pixel-perfect color
        let bottomColor = computePreciseAverageColor(
            pixelData: pixelData,
            startX: 0,
            endX: scaledEdgeStripWidth,
            startY: max(0, height - scaledCornerSampleHeight),
            endY: height,
            bytesPerPixel: bytesPerPixel,
            bytesPerRow: bytesPerRow,
        )

        // Sample at all four horizontal depths for each vertical region
        var colors: [NSColor] = []
        var edgeStripColors: [NSColor] = []
        var nearEdgeColors: [NSColor] = []
        var midEdgeColors: [NSColor] = []

        for regionIndex in 0 ..< regionCount {
            let startY = regionIndex * regionHeight
            let endY = min(startY + regionHeight, height)

            // Full width (for blurred background)
            colors.append(computeRegionColor(
                pixelData: pixelData,
                startX: 0,
                endX: width,
                startY: startY,
                endY: endY,
                bytesPerPixel: bytesPerPixel,
                bytesPerRow: bytesPerRow,
                isDarkBackground: isDarkBackground,
            ))

            // Edge strip (2px)
            edgeStripColors.append(computeRegionColor(
                pixelData: pixelData,
                startX: 0,
                endX: scaledEdgeStripWidth,
                startY: startY,
                endY: endY,
                bytesPerPixel: bytesPerPixel,
                bytesPerRow: bytesPerRow,
                isDarkBackground: isDarkBackground,
            ))

            // Near edge (8px)
            nearEdgeColors.append(computeRegionColor(
                pixelData: pixelData,
                startX: 0,
                endX: scaledNearEdgeWidth,
                startY: startY,
                endY: endY,
                bytesPerPixel: bytesPerPixel,
                bytesPerRow: bytesPerRow,
                isDarkBackground: isDarkBackground,
            ))

            // Mid edge (20px)
            midEdgeColors.append(computeRegionColor(
                pixelData: pixelData,
                startX: 0,
                endX: scaledMidEdgeWidth,
                startY: startY,
                endY: endY,
                bytesPerPixel: bytesPerPixel,
                bytesPerRow: bytesPerRow,
                isDarkBackground: isDarkBackground,
            ))
        }

        return ExtractionResult(
            colors: colors,
            edgeStripColors: edgeStripColors,
            nearEdgeColors: nearEdgeColors,
            midEdgeColors: midEdgeColors,
            topColor: topColor,
            bottomColor: bottomColor,
        )
    }

    /// Computes the average brightness (0-255) of a rectangular region.
    ///
    /// Used to determine if the background is dark or light before applying
    /// brightness-based filtering.
    private func computeAverageBrightness(
        pixelData: [UInt8],
        startX: Int,
        endX: Int,
        startY: Int,
        endY: Int,
        bytesPerPixel: Int,
        bytesPerRow: Int,
    ) -> Int {
        var totalBrightness = 0
        var count = 0

        let regionWidth = endX - startX
        let regionHeight = endY - startY

        // Sample at regular intervals for performance
        let stepX = regionWidth <= 2 ? 1 : max(1, regionWidth / Constants.downsampleSize)
        let stepY = max(1, regionHeight / Constants.downsampleSize)

        for y in stride(from: startY, to: endY, by: stepY) {
            for x in stride(from: startX, to: endX, by: stepX) {
                let pixelIndex = y * bytesPerRow + x * bytesPerPixel

                // Skip transparent pixels (masked corners from GPU capture)
                guard pixelData[pixelIndex + 3] > 127 else { continue }

                let r = Int(pixelData[pixelIndex])
                let g = Int(pixelData[pixelIndex + 1])
                let b = Int(pixelData[pixelIndex + 2])

                totalBrightness += (r + g + b) / 3
                count += 1
            }
        }

        return count > 0 ? totalBrightness / count : 128
    }

    /// Computes the dominant color for a rectangular region using brightness-weighted averaging.
    ///
    /// On light backgrounds, filters out dark pixels and weights lighter pixels more heavily.
    /// On dark backgrounds, filters out bright pixels and weights darker pixels more heavily.
    ///
    /// - Parameter isDarkBackground: If true, prefer dark pixels (filter out bright content).
    private func computeRegionColor(
        pixelData: [UInt8],
        startX: Int,
        endX: Int,
        startY: Int,
        endY: Int,
        bytesPerPixel: Int,
        bytesPerRow: Int,
        isDarkBackground: Bool,
    ) -> NSColor {
        let weightPower = Constants.brightnessWeightPower

        var weightedSumR: CGFloat = 0
        var weightedSumG: CGFloat = 0
        var weightedSumB: CGFloat = 0
        var totalWeight: CGFloat = 0

        // Track extreme pixel as fallback
        var fallbackR: Int = isDarkBackground ? 255 : 0
        var fallbackG: Int = isDarkBackground ? 255 : 0
        var fallbackB: Int = isDarkBackground ? 255 : 0
        var extremeBrightness: Int = isDarkBackground ? 255 : 0

        let regionWidth = endX - startX
        let regionHeight = endY - startY

        // Sample at regular intervals for performance (but sample all pixels for very narrow regions)
        let stepX = regionWidth <= 2 ? 1 : max(1, regionWidth / Constants.downsampleSize)
        let stepY = max(1, regionHeight / Constants.downsampleSize)

        for y in stride(from: startY, to: endY, by: stepY) {
            for x in stride(from: startX, to: endX, by: stepX) {
                let pixelIndex = y * bytesPerRow + x * bytesPerPixel

                // Skip transparent pixels (masked corners from GPU capture)
                guard pixelData[pixelIndex + 3] > 127 else { continue }

                let r = Int(pixelData[pixelIndex])
                let g = Int(pixelData[pixelIndex + 1])
                let b = Int(pixelData[pixelIndex + 2])

                // Calculate brightness (simple average, fast)
                let brightness = (r + g + b) / 3

                // Track most extreme pixel (darkest for dark bg, brightest for light bg) as fallback
                if isDarkBackground {
                    if brightness < extremeBrightness {
                        extremeBrightness = brightness
                        fallbackR = r
                        fallbackG = g
                        fallbackB = b
                    }
                } else {
                    if brightness > extremeBrightness {
                        extremeBrightness = brightness
                        fallbackR = r
                        fallbackG = g
                        fallbackB = b
                    }
                }

                // Filter pixels based on background type
                if isDarkBackground {
                    // Dark background: filter OUT bright pixels (likely content like text/icons)
                    guard brightness <= Constants.darkModeMaxBrightness else { continue }
                    // Weight by darkness: darker pixels get higher weight
                    let normalizedDarkness = 1.0 - CGFloat(brightness) / 255.0
                    let weight = pow(normalizedDarkness, weightPower)
                    weightedSumR += CGFloat(r) * weight
                    weightedSumG += CGFloat(g) * weight
                    weightedSumB += CGFloat(b) * weight
                    totalWeight += weight
                } else {
                    // Light background: filter OUT dark pixels (likely content)
                    guard brightness >= Constants.lightModeMinBrightness else { continue }
                    // Weight by brightness: lighter pixels get higher weight
                    let normalizedBrightness = CGFloat(brightness) / 255.0
                    let weight = pow(normalizedBrightness, weightPower)
                    weightedSumR += CGFloat(r) * weight
                    weightedSumG += CGFloat(g) * weight
                    weightedSumB += CGFloat(b) * weight
                    totalWeight += weight
                }
            }
        }

        // If no pixels passed the filter, use the most extreme pixel found
        if totalWeight < 0.001 {
            return NSColor(
                red: CGFloat(fallbackR) / 255.0,
                green: CGFloat(fallbackG) / 255.0,
                blue: CGFloat(fallbackB) / 255.0,
                alpha: 1.0,
            )
        }

        return NSColor(
            red: weightedSumR / totalWeight / 255.0,
            green: weightedSumG / totalWeight / 255.0,
            blue: weightedSumB / totalWeight / 255.0,
            alpha: 1.0,
        )
    }

    // MARK: - GPU Capture

    /// Captures a left-edge strip from the composited window using GPU hardware capture.
    ///
    /// Uses `CGSHWCaptureWindowList` to read directly from WindowServer's GPU textures.
    /// The capture is synchronous — no IPC round-trip to the web content process.
    ///
    /// The strip is taken at the web view's left edge position in the window, which means
    /// it captures the composited result of all content at that horizontal position. In a
    /// vertical split, both panes are included naturally.
    ///
    /// - Parameter webView: The web view whose left edge position determines the crop.
    /// - Returns: A CGImage of the left edge strip, or `nil` if capture failed.
    private func captureLeftEdgeGPU(webView: WKWebView) -> CGImage? {
        guard let window = webView.window, window.isVisible,
              webView.superview != nil,
              webView.bounds.width > 0, webView.bounds.height > 0 else { return nil }

        var windowID = CGSWindowID(window.windowNumber)
        let options = CGSWindowCaptureOptions(kCGSCaptureIgnoreGlobalClipShape)

        guard let snapshots = CGSHWCaptureWindowList(CGSMainConnectionID(), &windowID, 1, options),
              let first = (snapshots as NSArray).firstObject else { return nil }
        let fullImage = first as! CGImage

        // Convert web view's bounds to window coordinates (AppKit: origin at bottom-left)
        let webViewInWindow = webView.convert(webView.bounds, to: nil)
        let scale = window.backingScaleFactor

        // Crop to left edge strip at the web view's position.
        // CGImage origin is top-left, so flip Y from AppKit's bottom-left origin.
        let cropRect = CGRect(
            x: webViewInWindow.origin.x * scale,
            y: (window.frame.height - webViewInWindow.maxY) * scale,
            width: Constants.sampleWidth * scale,
            height: webViewInWindow.height * scale,
        ).integral

        guard cropRect.width > 0, cropRect.height > 0,
              let croppedImage = fullImage.cropping(to: cropRect) else { return nil }

        // Apply corner masking if the content area has rounded left-side corners
        if contentCornerRadius > 0 {
            return applyCornerMask(to: croppedImage, cornerRadius: contentCornerRadius * scale)
        }

        return croppedImage
    }

    /// Masks rounded corners on the left side of an image by clearing those pixels to transparent.
    ///
    /// The content area uses `UnevenRoundedRectangle` with rounded top-left and bottom-left
    /// corners. When capturing the composited window, those corner pixels show the window
    /// background instead of web content. This method clears them so they're skipped during
    /// color extraction (the alpha check in the iteration loops filters them out).
    ///
    /// - Parameters:
    ///   - image: The cropped edge strip image.
    ///   - cornerRadius: The corner radius in pixels (already multiplied by scale factor).
    /// - Returns: A new image with transparent corner regions, or the original if masking fails.
    private func applyCornerMask(to image: CGImage, cornerRadius: CGFloat) -> CGImage {
        let width = image.width
        let height = image.height

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else { return image }

        // Flip to top-left origin to match CGImage orientation
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)

        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        let radius = min(cornerRadius, CGFloat(min(width, height)) / 2)

        // Build path with only top-left and bottom-left corners rounded.
        // Right side is straight (only the left edge is adjacent to rounded content).
        let path = CGMutablePath()
        path.move(to: CGPoint(x: radius, y: 0))
        // Top edge → top-right (no rounding)
        path.addLine(to: CGPoint(x: CGFloat(width), y: 0))
        // Right edge → bottom-right (no rounding)
        path.addLine(to: CGPoint(x: CGFloat(width), y: CGFloat(height)))
        // Bottom edge → bottom-left corner
        path.addLine(to: CGPoint(x: radius, y: CGFloat(height)))
        // Bottom-left rounded corner
        path.addArc(
            tangent1End: CGPoint(x: 0, y: CGFloat(height)),
            tangent2End: CGPoint(x: 0, y: CGFloat(height) - radius),
            radius: radius,
        )
        // Left edge → top-left corner
        path.addLine(to: CGPoint(x: 0, y: radius))
        // Top-left rounded corner
        path.addArc(
            tangent1End: CGPoint(x: 0, y: 0),
            tangent2End: CGPoint(x: radius, y: 0),
            radius: radius,
        )
        path.closeSubpath()

        context.addPath(path)
        context.clip()
        context.draw(image, in: rect)

        return context.makeImage() ?? image
    }

    // MARK: - Color Extraction Helpers

    /// Computes the precise average color for a rectangular region.
    ///
    /// Unlike `computeRegionColor` which uses histogram binning, this method computes
    /// the exact arithmetic mean of all pixels. Use this for corner regions where
    /// pixel-perfect accuracy is needed (exposed areas not covered by glass blur).
    private func computePreciseAverageColor(
        pixelData: [UInt8],
        startX: Int,
        endX: Int,
        startY: Int,
        endY: Int,
        bytesPerPixel: Int,
        bytesPerRow: Int,
    ) -> NSColor {
        var sumR = 0
        var sumG = 0
        var sumB = 0
        var count = 0

        // Sample ALL pixels in narrow regions for maximum precision
        for y in startY ..< endY {
            for x in startX ..< endX {
                let pixelIndex = y * bytesPerRow + x * bytesPerPixel

                // Skip transparent pixels (masked corners from GPU capture)
                guard pixelData[pixelIndex + 3] > 127 else { continue }

                sumR += Int(pixelData[pixelIndex])
                sumG += Int(pixelData[pixelIndex + 1])
                sumB += Int(pixelData[pixelIndex + 2])
                count += 1
            }
        }

        guard count > 0 else {
            return NSColor.windowBackgroundColor
        }

        return NSColor(
            red: CGFloat(sumR) / CGFloat(count) / 255.0,
            green: CGFloat(sumG) / CGFloat(count) / 255.0,
            blue: CGFloat(sumB) / CGFloat(count) / 255.0,
            alpha: 1.0,
        )
    }
}
