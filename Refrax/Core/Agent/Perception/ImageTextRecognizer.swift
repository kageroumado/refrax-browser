import Foundation
import Vision
import WebKit

/// Recognizes text in images on web pages using the Vision framework.
///
/// WebKit's `WKTextExtractionImageItem` often misses content images (e.g., tweet
/// photos, embedded screenshots) that are deeply nested or styled with CSS.
/// Instead, this service discovers images via JavaScript DOM queries, downloads
/// them by URL, and runs Vision OCR.
///
/// Results are stored in ``PageContentTree/imageOCR`` and displayed as a footer
/// section in the formatted output.
///
/// ## Heuristics
///
/// - **Size**: Minimum 100×50px rendered size (skips icons, avatars, emojis)
/// - **Viewport**: Must be at least partially visible
/// - **Source**: Must have an HTTP(S) src (skips data URIs, blob URLs)
/// - **Count cap**: Maximum 5 images per extraction
///
/// ## Performance
///
/// Image downloads and OCR run in parallel via TaskGroup.
/// Vision uses `.fast` recognition level. Typical total: 1–2 seconds.
nonisolated enum ImageTextRecognizer {
    // MARK: - Configuration

    private static let minWidth = 100
    private static let minHeight = 50
    private static let maxImages = 5
    private static let minOCRConfidence: Float = 0.3
    private static let maxOCRTextLength = 500

    // MARK: - Public API

    /// Discovers images in the viewport via JavaScript and runs OCR on them.
    ///
    /// - Parameter webView: The web view to scan for images.
    /// - Returns: Dictionary mapping image labels to recognized text.
    @MainActor
    static func recognizeText(
        webView: WKWebView,
    ) async -> [String: String] {
        let images = await discoverImages(in: webView)

        if images.isEmpty {
            Logger.debug("[ImageOCR] No qualifying images in viewport", category: Logger.agent)
            return [:]
        }

        Logger.debug(
            "[ImageOCR] Found \(images.count) image(s), downloading for OCR",
            category: Logger.agent,
        )

        // Download and OCR in parallel
        return await withTaskGroup(of: (String, String?).self) { group in
            for (i, image) in images.enumerated() {
                group.addTask {
                    guard let text = await downloadAndOCR(image) else {
                        return ("", nil)
                    }
                    let label = image.alt.isEmpty ? "Image \(i + 1)" : image.alt
                    return (label, text)
                }
            }

            var results: [String: String] = [:]
            for await (label, text) in group {
                if let text, !label.isEmpty {
                    results[label] = text
                }
            }
            return results
        }
    }

    // MARK: - Image Discovery

    /// Finds visible `<img>` elements in the viewport via JavaScript.
    ///
    /// This is more reliable than relying on `WKTextExtractionImageItem`, which
    /// often misses images that are deeply nested in the DOM (e.g., Twitter's
    /// tweet photos wrapped in many `<div>` layers).
    @MainActor
    private static func discoverImages(in webView: WKWebView) async -> [DiscoveredImage] {
        let js = """
        (() => {
            const results = [];
            for (const img of document.querySelectorAll('img')) {
                const rect = img.getBoundingClientRect();
                if (rect.width < \(minWidth) || rect.height < \(minHeight)) continue;
                if (rect.bottom < 0 || rect.top > window.innerHeight) continue;
                if (!img.src || img.src.startsWith('data:') || img.src.startsWith('blob:')) continue;
                results.push({
                    src: img.src,
                    alt: img.alt || '',
                    width: Math.round(rect.width),
                    height: Math.round(rect.height)
                });
            }
            return JSON.stringify(results.slice(0, \(maxImages)));
        })()
        """

        guard let json = try? await webView.evaluateJavaScriptWithoutUserGesture(js) as? String,
              let data = json.data(using: .utf8),
              let images = try? JSONDecoder().decode([DiscoveredImage].self, from: data)
        else {
            Logger.debug("[ImageOCR] JavaScript image discovery failed", category: Logger.agent)
            return []
        }

        return images
    }

    // MARK: - Download & OCR

    /// Downloads an image by URL and runs Vision text recognition on it.
    private static func downloadAndOCR(_ image: DiscoveredImage) async -> String? {
        guard let url = URL(string: image.src) else { return nil }

        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            Logger.debug(
                "[ImageOCR] Download failed: \(image.src.prefix(80))",
                category: Logger.agent,
            )
            return nil
        }

        guard let nsImage = NSImage(data: data),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        return performOCR(on: cgImage)
    }

    // MARK: - OCR

    private static func performOCR(on image: CGImage) -> String? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        do {
            try handler.perform([request])
        } catch {
            Logger.debug(
                "[ImageOCR] Vision error: \(error.localizedDescription)",
                category: Logger.agent,
            )
            return nil
        }

        guard let observations = request.results else { return nil }

        let texts = observations
            .filter { $0.confidence >= minOCRConfidence }
            .compactMap { $0.topCandidates(1).first?.string }

        guard !texts.isEmpty else { return nil }

        let joined = texts.joined(separator: " ")
        Logger.debug(
            "[ImageOCR] Recognized \(texts.count) text region(s), \(joined.count) chars",
            category: Logger.agent,
        )

        if joined.count > maxOCRTextLength {
            return String(joined.prefix(maxOCRTextLength - 3)) + "..."
        }
        return joined
    }
}

// MARK: - Supporting Types

private nonisolated struct DiscoveredImage: Decodable, Sendable {
    let src: String
    let alt: String
    let width: Int
    let height: Int
}
