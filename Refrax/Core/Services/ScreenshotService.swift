import AppKit
import Foundation
import UniformTypeIdentifiers
import WebKit

/// Modes for capturing webpage screenshots.
enum ScreenshotMode: Sendable {
    /// Captures the entire webpage content, including scrollable areas.
    case fullPage

    /// Captures only the currently visible viewport.
    case visibleArea

    /// Activates selection mode for user-defined region capture.
    ///
    /// This mode requires additional UI coordination to display a selection
    /// overlay and capture the user's chosen region.
    case selection

    /// Captures the entire window with Liquid Glass effects preserved.
    ///
    /// Uses composited display capture + window alpha masking to retain
    /// backdrop blur and vibrancy that are lost in normal window capture.
    case window
}

/// Service for capturing screenshots of webpages.
///
/// Provides three capture modes:
/// - **Full Page**: Captures the entire scrollable content of the webpage
/// - **Visible Area**: Captures only the currently visible viewport
/// - **Selection**: Allows user to select a region to capture (requires UI coordination)
///
/// ## Usage
///
/// ```swift
/// let data = try await ScreenshotService.takeScreenshot(of: webPage, mode: .fullPage)
/// await ScreenshotService.saveToDesktop(data)
/// ```
///
/// ## Export Format
///
/// Screenshots are exported as PNG images using WebKit's native export functionality.
/// The resulting `Data` can be saved to disk, copied to clipboard, or shared.
enum ScreenshotService {
    // MARK: - Public Interface

    /// Captures a screenshot of the webpage using the specified mode.
    ///
    /// - Parameters:
    ///   - webPage: The WebPage instance to capture.
    ///   - mode: The capture mode determining what region to capture.
    /// - Returns: PNG image data of the captured region.
    /// - Throws: Error if the capture fails.
    static func takeScreenshot(of webPage: WebPage, mode: ScreenshotMode) async throws -> Data {
        switch mode {
        case .fullPage:
            try await captureFullPage(webPage)
        case .visibleArea:
            try await captureVisibleArea(webPage)
        case .selection:
            // Selection mode requires UI coordination - return visible area as fallback
            // The actual selection UI should be handled by the view layer
            try await captureVisibleArea(webPage)
        case .window:
            preconditionFailure("Window mode bypasses ScreenshotService — use WindowScreenshotService directly")
        }
    }

    /// Captures a specific rectangular region of the webpage.
    ///
    /// - Parameters:
    ///   - webPage: The WebPage instance to capture.
    ///   - rect: The rectangle in webpage coordinates to capture.
    /// - Returns: PNG image data of the captured region.
    /// - Throws: Error if the capture fails.
    static func captureRegion(of webPage: WebPage, rect: CGRect) async throws -> Data {
        let config = WebPage.ExportedContentConfiguration.image(
            region: .rect(rect),
            allowTransparentBackground: false,
            afterScreenUpdates: true,
        )
        return try await webPage.exported(as: config)
    }

    /// Saves screenshot data to the user's Desktop folder with a timestamped filename.
    ///
    /// The filename format is: `Screenshot YYYY-MM-DD at HH.MM.SS.png`
    ///
    /// - Parameter data: The PNG image data to save.
    /// - Returns: The URL where the file was saved.
    /// - Throws: Error if the file cannot be written.
    @discardableResult
    static func saveToDesktop(_ data: Data) async throws -> URL {
        let filename = generateFilename()
        let fileURL = Directories.desktop.appendingPathComponent(filename)

        try data.write(to: fileURL)
        Logger.info("Screenshot saved to \(fileURL.path)", category: Logger.navigation)
        return fileURL
    }

    /// Copies screenshot data to the system clipboard.
    ///
    /// - Parameter data: The PNG image data to copy.
    static func copyToClipboard(_ data: Data) {
        guard let image = NSImage(data: data) else {
            Logger.warning("Failed to create image from screenshot data", category: Logger.navigation)
            return
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        Logger.info("Screenshot copied to clipboard", category: Logger.navigation)
    }

    /// Presents a save panel for the user to choose where to save the screenshot.
    ///
    /// - Parameters:
    ///   - data: The PNG image data to save.
    ///   - suggestedName: Optional suggested filename (without extension).
    /// - Returns: The URL where the file was saved, or nil if cancelled.
    static func saveWithPanel(_ data: Data, suggestedName: String? = nil) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggestedName ?? generateFilename()
        panel.canCreateDirectories = true

        let response = await panel.begin()
        guard response == .OK, let url = panel.url else {
            return nil
        }

        do {
            try data.write(to: url)
            Logger.info("Screenshot saved to \(url.path)", category: Logger.navigation)
            return url
        } catch {
            Logger.error("Failed to save screenshot: \(error)", category: Logger.navigation)
            return nil
        }
    }

    // MARK: - Private Implementation

    /// Captures the entire webpage content.
    private static func captureFullPage(_ webPage: WebPage) async throws -> Data {
        let config = WebPage.ExportedContentConfiguration.image(
            region: .contents,
            allowTransparentBackground: false,
            afterScreenUpdates: true,
        )
        return try await webPage.exported(as: config)
    }

    /// Captures the visible viewport of the webpage.
    private static func captureVisibleArea(_ webPage: WebPage) async throws -> Data {
        // Get the visible rect via JavaScript
        let visibleRect = try await getVisibleRect(webPage)

        let config = WebPage.ExportedContentConfiguration.image(
            region: .rect(visibleRect),
            allowTransparentBackground: false,
            afterScreenUpdates: true,
        )
        return try await webPage.exported(as: config)
    }

    /// Gets the currently visible rectangle of the webpage.
    private static func getVisibleRect(_ webPage: WebPage) async throws -> CGRect {
        guard let result = try await webPage.callJavaScript(JavaScriptSnippets.visibleViewportJSON) as? String,
              let data = result.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: CGFloat],
              let x = dict["x"],
              let y = dict["y"],
              let width = dict["width"],
              let height = dict["height"]
        else {
            // Fallback to a reasonable default
            return CGRect(x: 0, y: 0, width: 1_920, height: 1_080)
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Generates a timestamped filename for screenshots.
    private static func generateFilename() -> String {
        // Use static class method to avoid formatter allocation
        let timestamp = ISO8601DateFormatter.string(
            from: Date(),
            timeZone: .current,
            formatOptions: [.withFullDate, .withTime, .withColonSeparatorInTime],
        ).replacingOccurrences(of: ":", with: ".")
        return "Screenshot \(timestamp).png"
    }
}
