import AppKit
import OrderedCollections
import SwiftUI

// MARK: - Environment Keys

private struct FaviconBackgroundColorKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

private struct DelayFaviconFallbackKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

private struct FaviconSizeKey: EnvironmentKey {
    static let defaultValue: CGFloat = 32
}

private extension EnvironmentValues {
    /// The computed size of the favicon container, passed to child views.
    var faviconSize: CGFloat {
        get { self[FaviconSizeKey.self] }
        set { self[FaviconSizeKey.self] = newValue }
    }
}

extension EnvironmentValues {
    /// Background color for favicons with transparency and fallback views.
    ///
    /// When set, FaviconView displays:
    /// - Alpha favicons: inset to 75% with squircle background
    /// - Fallbacks: full size with squircle background
    /// - Solid favicons: full size, no background
    var faviconBackgroundColor: Color? {
        get { self[FaviconBackgroundColorKey.self] }
        set { self[FaviconBackgroundColorKey.self] = newValue }
    }

    /// When true, delays showing the fallback content briefly.
    ///
    /// Use this when favicon data is expected to arrive shortly (e.g., after
    /// page loading finishes) to prevent a brief flash of the letter fallback.
    var delayFaviconFallback: Bool {
        get { self[DelayFaviconFallbackKey.self] }
        set { self[DelayFaviconFallbackKey.self] = newValue }
    }
}

// MARK: - View Modifier

extension View {
    /// Enables background display for favicons with transparency and fallback views.
    ///
    /// When applied, favicons with alpha channels are inset to 75% of the container
    /// and displayed over a squircle background. Fallback views (letter, globe)
    /// display at full size with the background.
    ///
    /// - Parameter color: The background color. Defaults to `.secondary.opacity(0.2)`.
    func faviconBackground(_ color: Color = .secondary.opacity(0.2)) -> some View {
        environment(\.faviconBackgroundColor, color)
    }
}

// MARK: - Favicon View

/// A unified view for displaying website favicons with consistent styling.
///
/// `FaviconView` encapsulates all favicon display logic including:
/// - High-quality image rendering with proper interpolation
/// - Apple-style squircle clipping (28% corner radius)
/// - Automatic fallback to letter icon when no favicon data is available
/// - Optional background for transparent favicons (via `.faviconBackground()`)
///
/// ## Usage
///
/// ```swift
/// // Basic usage (default size: 32)
/// FaviconView(data: bookmark.faviconData, url: bookmark.url)
///
/// // With explicit size
/// FaviconView(data: bookmark.faviconData, url: bookmark.url, size: 48)
///
/// // With background for transparent favicons (compact sidebar style)
/// FaviconView(data: tab.faviconData, url: tab.url, size: 32)
///     .faviconBackground(.secondary.opacity(0.2))
/// ```
///
/// ## Size
///
/// Use the `size` parameter to specify the favicon dimensions.
/// For best results, use the same value for width and height in the containing frame.
struct FaviconView<Fallback: View>: View {
    @Environment(\.faviconBackgroundColor) private var backgroundColor
    @Environment(\.delayFaviconFallback) private var delayFallback

    @State private var decodedImage: DecodedFavicon?

    private let data: Data?
    private let url: URL?
    private let fallback: Fallback
    private let size: CGFloat

    /// Creates a favicon view with data and URL for automatic letter fallback.
    ///
    /// - Parameters:
    ///   - data: Optional favicon image data.
    ///   - url: URL used for letter fallback when no data is available.
    ///   - size: The size of the favicon in points. Defaults to 32.
    init(data: Data?, url: URL?, size: CGFloat = 32) where Fallback == LetterFallbackView {
        self.data = data
        self.url = url
        self.size = size
        self.fallback = LetterFallbackView(url: url)
    }

    /// Creates a favicon view with just a URL (always shows letter fallback).
    ///
    /// - Parameters:
    ///   - url: URL for letter generation.
    ///   - size: The size of the favicon in points. Defaults to 32.
    init(url: URL, size: CGFloat = 32) where Fallback == LetterFallbackView {
        self.data = nil
        self.url = url
        self.size = size
        self.fallback = LetterFallbackView(url: url)
    }
    
    /// Creates a favicon view with data and automatic letter fallback.
    ///
    /// - Parameters:
    ///   - data: Optional favicon image data.
    ///   - size: The size of the favicon in points. Defaults to 32.
    init(data: Data?, size: CGFloat = 32) where Fallback == LetterFallbackView {
        self.data = data
        self.url = nil
        self.size = size
        self.fallback = LetterFallbackView(host: "")
    }

    /// Creates a favicon view with data and a custom fallback view.
    ///
    /// - Parameters:
    ///   - data: Optional favicon image data.
    ///   - size: The size of the favicon in points. Defaults to 32.
    ///   - fallback: View to show when no favicon data is available.
    init(data: Data?, size: CGFloat = 32, @ViewBuilder fallback: () -> Fallback) {
        self.data = data
        self.url = nil
        self.size = size
        self.fallback = fallback()
    }

    var body: some View {
        // Check global cache synchronously — avoids the async gap that causes
        // favicon blink on NSTableView cell reuse. Most favicons are shared across
        // tabs from the same domain, so cache hit rate is high during scrolling.
        let cachedFavicon = data.flatMap { DecodedFaviconCache[$0] }

        ZStack {
            if let favicon = cachedFavicon ?? decodedImage {
                faviconContent(favicon, size: size)
            } else if data == nil {
                fallbackContent(size: size)
            }
        }
        .environment(\.faviconSize, size)
        .frame(width: size, height: size)
        .onChange(of: data) { _, _ in
            // Clear stale decoded image from previous cell content to prevent
            // briefly showing the wrong favicon during NSTableView cell reuse.
            decodedImage = nil
        }
        .task(id: data) {
            guard let data else {
                decodedImage = nil
                return
            }
            // Fast path: already in global cache
            if let cached = DecodedFaviconCache[data] {
                decodedImage = cached
                return
            }
            // Slow path: decode on background thread, then cache
            let decoded = await Task.detached(priority: .utility) {
                DecodedFavicon(data: data)
            }.value
            if let decoded {
                DecodedFaviconCache[data] = decoded
            }
            decodedImage = decoded
        }
    }

    // MARK: - Favicon Content

    @ViewBuilder
    private func faviconContent(_ favicon: DecodedFavicon, size: CGFloat) -> some View {
        let showBackground = backgroundColor != nil && favicon.hasAlphaChannel
        let insetSize = size * 0.75

        if showBackground {
            SquircleShape()
                .fill(backgroundColor!)

            Image(nsImage: favicon.image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: insetSize, height: insetSize)
                .clipToSquircle()
        } else {
            Image(nsImage: favicon.image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipToSquircle()
        }
    }

    @ViewBuilder
    private func fallbackContent(size: CGFloat) -> some View {
        if let backgroundColor {
            SquircleShape()
                .fill(backgroundColor)

            fallback
                .frame(width: size, height: size)
                .delayedAppearance(shouldDelay: delayFallback)
        } else {
            fallback
                .frame(width: size, height: size)
                .delayedAppearance(shouldDelay: delayFallback)
        }
    }
}

// MARK: - Letter Fallback View

/// Default fallback view showing the first letter of a domain.
///
/// Used automatically by `FaviconView` when initialized with a URL.
struct LetterFallbackView: View {
    @Environment(\.faviconBackgroundColor) private var backgroundColor
    @Environment(\.faviconSize) private var size

    let letters: String

    init(url: URL?) {
        if let host = url?.host {
            self.letters = Self.extractLetters(from: host)
        } else {
            self.letters = "?"
        }
    }

    init(host: String) {
        self.letters = Self.extractLetters(from: host)
    }

    var body: some View {
        ZStack {
            // Only show internal background if no external background is set
            if backgroundColor == nil {
                SquircleShape()
                    .fill(.secondary)
            }

            Text(letters)
                .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private static func extractLetters(from host: String) -> String {
        var domain = host.lowercased()
        if domain.hasPrefix("www.") {
            domain = String(domain.dropFirst(4))
        }

        let parts = domain.split(separator: ".")
        guard let mainPart = parts.first else {
            return "?"
        }

        return String(mainPart).prefix(1).uppercased()
    }
}

// MARK: - Decoded Favicon Cache

/// Global in-memory cache for decoded favicon images.
///
/// Keyed by favicon `Data` content, so identical images from different tabs
/// resolve instantly without re-decoding PNG data or re-running alpha detection.
/// Checked synchronously in `FaviconView.body` for flicker-free cell reuse.
///
/// Uses `OrderedDictionary` for FIFO eviction — oldest entries are removed first,
/// which approximates LRU for scroll-heavy workloads where recently-accessed
/// favicons are also recently-inserted.
@MainActor
enum DecodedFaviconCache {
    private static var entries: OrderedDictionary<Data, DecodedFavicon> = [:]
    private static let maxEntries = 400

    static subscript(data: Data) -> DecodedFavicon? {
        get { entries[data] }
        set {
            entries[data] = newValue
            if entries.count > maxEntries {
                entries.removeFirst(maxEntries / 4)
            }
        }
    }
}

// MARK: - Cached Favicon

/// Wraps an NSImage with a pre-computed alpha channel detection result.
///
/// The alpha detection creates a CGContext, draws at 8x8, and samples corner pixels —
/// expensive when called on every `FaviconView.body` evaluation. This struct computes
/// the result once at init time. Create on a background thread so the main thread
/// never pays the CGContext cost.
nonisolated struct DecodedFavicon: Sendable {
    let image: NSImage
    let hasAlphaChannel: Bool

    /// Creates a cached favicon from raw image data.
    ///
    /// Returns `nil` if the data cannot be decoded as an image.
    init?(data: Data) {
        guard let image = NSImage(data: data) else { return nil }
        self.image = image
        self.hasAlphaChannel = Self.detectAlpha(in: image)
    }

    /// Creates a cached favicon from an existing NSImage.
    init(image: NSImage) {
        self.image = image
        self.hasAlphaChannel = Self.detectAlpha(in: image)
    }

    private static func detectAlpha(in image: NSImage) -> Bool {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return false
        }

        switch cgImage.alphaInfo {
        case .none, .noneSkipLast, .noneSkipFirst:
            return false
        case .premultipliedLast, .premultipliedFirst, .last, .first, .alphaOnly:
            return hasActualTransparency(cgImage)
        @unknown default:
            return false
        }
    }

    /// Samples corner pixels to detect actual transparency (not just an unused alpha channel).
    private static func hasActualTransparency(_ cgImage: CGImage) -> Bool {
        let sampleSize = 8
        let bytesPerPixel = 4
        let bytesPerRow = sampleSize * bytesPerPixel

        var pixelData = [UInt8](repeating: 0, count: sampleSize * sampleSize * bytesPerPixel)

        guard let context = CGContext(
            data: &pixelData,
            width: sampleSize,
            height: sampleSize,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else {
            return true
        }

        context.interpolationQuality = .none
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSize, height: sampleSize))

        let lastPixel = sampleSize - 1
        let cornerPixels = [
            (0, 0),
            (lastPixel, 0),
            (0, lastPixel),
            (lastPixel, lastPixel),
        ]

        for (x, y) in cornerPixels {
            let offset = y * bytesPerRow + x * bytesPerPixel + 3
            let alpha = pixelData[offset]
            if alpha < 250 {
                return true
            }
        }

        return false
    }
}


// MARK: - Preview

#Preview("FaviconView") {
    VStack(spacing: 20) {
        Text("Without background")
        HStack(spacing: 16) {
            FaviconView(data: nil, url: URL(string: "https://apple.com"), size: 32)

            FaviconView(data: nil, url: URL(string: "https://github.com"), size: 32)

            FaviconView(data: nil, size: 32)
        }

        Text("With background")
        HStack(spacing: 16) {
            FaviconView(data: nil, url: URL(string: "https://apple.com"), size: 32)
                .faviconBackground()

            FaviconView(data: nil, url: URL(string: "https://github.com"), size: 32)
                .faviconBackground()

            FaviconView(data: nil, size: 32)
                .faviconBackground()
        }
    }
    .padding()
}
