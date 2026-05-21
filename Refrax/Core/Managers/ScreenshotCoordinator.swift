import AppKit
import Foundation
import WebKit

/// Result of a screenshot capture operation.
enum ScreenshotResult: Sendable {
    /// Screenshot captured successfully.
    case success(data: Data, savedURL: URL?)

    /// Screenshot was cancelled by the user.
    case cancelled

    /// Screenshot failed with an error.
    case failed(any Error)
}

/// Coordinates screenshot capture workflow with visual and audio feedback.
///
/// Provides a complete screenshot experience similar to macOS system screenshots:
/// - Shutter sound on capture
/// - White flash effect
/// - Preview thumbnail in corner
/// - Option to copy, save, or quick-save to Desktop
///
/// ## Usage
///
/// ```swift
/// let coordinator = ScreenshotCoordinator()
/// let result = await coordinator.captureFullPage(webPage: page, in: window)
/// ```
///
/// For element selection mode, the coordinator injects JavaScript to allow
/// the user to select a page element, then captures that region.
@Observable
final class ScreenshotCoordinator {
    /// The current screenshot preview, if any.
    ///
    /// Set after a successful capture. The preview auto-dismisses after a delay,
    /// or can be dismissed by user interaction.
    private(set) var currentPreview: ScreenshotPreview?

    /// Whether element selection mode is currently active.
    private(set) var isSelectionModeActive = false

    /// Preview data shown after capture.
    struct ScreenshotPreview: Identifiable {
        let id = UUID()
        let image: NSImage
        let data: Data
        let savedURL: URL?

        /// Timer task for auto-dismiss.
        var dismissTask: Task<Void, Never>?
    }

    // MARK: - Capture Methods

    /// Captures the entire webpage content.
    ///
    /// - Parameters:
    ///   - webPage: The WebPage to capture.
    ///   - window: The window for flash effect display.
    ///   - saveDirectory: Directory to save the screenshot to.
    /// - Returns: The screenshot result.
    func captureFullPage(webPage: WebPage, in window: NSWindow?, saveDirectory: URL) async -> ScreenshotResult {
        await performCapture(window: window, saveDirectory: saveDirectory) {
            try await ScreenshotService.takeScreenshot(of: webPage, mode: .fullPage)
        }
    }

    /// Captures the visible viewport of the webpage.
    ///
    /// - Parameters:
    ///   - webPage: The WebPage to capture.
    ///   - window: The window for flash effect display.
    ///   - saveDirectory: Directory to save the screenshot to.
    /// - Returns: The screenshot result.
    func captureVisibleArea(webPage: WebPage, in window: NSWindow?, saveDirectory: URL) async -> ScreenshotResult {
        await performCapture(window: window, saveDirectory: saveDirectory) {
            try await ScreenshotService.takeScreenshot(of: webPage, mode: .visibleArea)
        }
    }

    /// Captures the entire window with Liquid Glass effects preserved.
    ///
    /// Uses ``WindowScreenshotService/captureWindowComposited(_:)`` to capture the
    /// composited display output, preserving backdrop blur and vibrancy effects.
    ///
    /// - Parameters:
    ///   - window: The window to capture.
    ///   - saveDirectory: Directory to save the screenshot to.
    /// - Returns: The screenshot result.
    func captureWindow(window: NSWindow?, saveDirectory: URL) async -> ScreenshotResult {
        guard let window else {
            return .failed(ScreenshotError.selectionFailed)
        }

        return await performCapture(window: window, saveDirectory: saveDirectory) {
            guard let data = await WindowScreenshotService.captureWindowComposited(window) else {
                throw ScreenshotError.windowCaptureFailed
            }
            return data
        }
    }

    /// Activates element selection mode and captures the selected element.
    ///
    /// Injects JavaScript overlay that allows the user to select a page element
    /// by hovering and clicking. The selected element's bounds are captured.
    ///
    /// - Parameters:
    ///   - webPage: The WebPage to capture from.
    ///   - window: The window for flash effect display.
    ///   - saveDirectory: Directory to save the screenshot to.
    /// - Returns: The screenshot result, or `.cancelled` if user presses ESC.
    func captureSelectedElement(webPage: WebPage, in window: NSWindow?, saveDirectory: URL) async -> ScreenshotResult {
        isSelectionModeActive = true
        defer { isSelectionModeActive = false }

        // Inject element selection overlay
        guard let result = try? await webPage.callJavaScript(JavaScriptSnippets.elementSelectionOverlay) as? String else {
            return .failed(ScreenshotError.selectionFailed)
        }

        // Check for cancellation
        if result == "cancelled" {
            return .cancelled
        }

        // Parse the selected element bounds
        guard let data = result.data(using: .utf8),
              let rect = try? JSONDecoder().decode(ElementRect.self, from: data) else {
            return .failed(ScreenshotError.invalidSelectionResult)
        }

        // Capture the selected region
        return await performCapture(window: window, saveDirectory: saveDirectory) {
            try await ScreenshotService.captureRegion(
                of: webPage,
                rect: CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height),
            )
        }
    }

    // MARK: - Preview Actions

    /// Copies the current preview image to the clipboard and removes the saved file.
    func copyPreviewToClipboard() {
        guard let preview = currentPreview else { return }
        ScreenshotService.copyToClipboard(preview.data)

        // Remove the saved file — user chose clipboard over file (mirrors macOS behavior)
        if let url = preview.savedURL {
            try? FileManager.default.removeItem(at: url)
        }

        dismissPreview()
    }

    /// Pauses auto-dismiss while the user is hovering over the preview.
    func pauseAutoDismiss() {
        currentPreview?.dismissTask?.cancel()
        currentPreview?.dismissTask = nil
    }

    /// Resumes auto-dismiss after the user stops hovering.
    func resumeAutoDismiss() {
        currentPreview?.dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.dismissPreview()
        }
    }

    /// Deletes the saved screenshot file and dismisses the preview.
    func deleteScreenshot() {
        if let url = currentPreview?.savedURL {
            try? FileManager.default.removeItem(at: url)
        }
        dismissPreview()
    }

    /// Opens the preview image in Preview.app or Finder.
    func openPreview() {
        guard let preview = currentPreview, let url = preview.savedURL else { return }
        NSWorkspace.shared.open(url)
        dismissPreview()
    }

    /// Dismisses the current preview.
    func dismissPreview() {
        currentPreview?.dismissTask?.cancel()
        currentPreview = nil
    }

    // MARK: - Private Implementation

    /// Performs a screenshot capture with feedback effects.
    private func performCapture(
        window: NSWindow?,
        saveDirectory: URL,
        capture: @escaping () async throws -> Data,
    ) async -> ScreenshotResult {
        do {
            // Capture the screenshot
            let data = try await capture()

            // Play shutter sound and show flash
            playShutterSound()
            if let window {
                showFlashEffect(in: window)
            }

            // Save to the specified directory
            let savedURL: URL?
            do {
                savedURL = try await saveScreenshot(data, to: saveDirectory)
            } catch {
                Logger.warning("Failed to save screenshot: \(error)", category: Logger.navigation)
                savedURL = nil
            }

            // Show preview
            if let image = NSImage(data: data) {
                showPreview(image: image, data: data, savedURL: savedURL)
            }

            return .success(data: data, savedURL: savedURL)
        } catch {
            Logger.error("Screenshot capture failed: \(error)", category: Logger.navigation)
            return .failed(error)
        }
    }

    /// Saves screenshot data to the specified directory with a timestamped filename.
    private func saveScreenshot(_ data: Data, to directory: URL) async throws -> URL {
        let filename = generateFilename()
        let fileURL = directory.appendingPathComponent(filename)

        // Ensure directory exists
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory.path) {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        try data.write(to: fileURL)
        Logger.info("Screenshot saved to \(fileURL.path)", category: Logger.navigation)
        return fileURL
    }

    /// Generates a timestamped filename for screenshots.
    private func generateFilename() -> String {
        // Use static class method to avoid formatter allocation
        let timestamp = ISO8601DateFormatter.string(
            from: Date(),
            timeZone: .current,
            formatOptions: [.withFullDate, .withTime, .withColonSeparatorInTime],
        ).replacingOccurrences(of: ":", with: ".")
        return "Screenshot \(timestamp).png"
    }

    /// Plays the system camera shutter sound.
    private func playShutterSound() {
        // Use the system screenshot sound if available
        // The sound file path on macOS
        let soundPath = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        if FileManager.default.fileExists(atPath: soundPath) {
            NSSound(contentsOfFile: soundPath, byReference: true)?.play()
        } else {
            // Fallback to a system sound
            NSSound.beep()
        }
    }

    /// Shows a brief white flash effect in the window.
    private func showFlashEffect(in window: NSWindow) {
        let flashView = NSView(frame: window.contentView?.bounds ?? .zero)
        flashView.wantsLayer = true
        flashView.layer?.backgroundColor = NSColor.white.cgColor
        flashView.alphaValue = 0

        window.contentView?.addSubview(flashView)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.1
            flashView.animator().alphaValue = 0.5
        } completionHandler: {
            MainActor.assumeIsolated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    flashView.animator().alphaValue = 0
                } completionHandler: {
                    MainActor.assumeIsolated {
                        flashView.removeFromSuperview()
                    }
                }
            }
        }
    }

    /// Shows the screenshot preview thumbnail.
    private func showPreview(image: NSImage, data: Data, savedURL: URL?) {
        // Cancel any existing preview dismiss task
        currentPreview?.dismissTask?.cancel()

        var preview = ScreenshotPreview(image: image, data: data, savedURL: savedURL)

        // Auto-dismiss after 5 seconds
        preview.dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.dismissPreview()
        }

        currentPreview = preview
    }

    // MARK: - Supporting Types

    /// Decoded element bounds from JavaScript selection.
    private struct ElementRect: Decodable {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
    }

    /// Errors specific to screenshot coordination.
    enum ScreenshotError: Error, LocalizedError {
        case selectionFailed
        case invalidSelectionResult
        case windowCaptureFailed

        var errorDescription: String? {
            switch self {
            case .selectionFailed:
                "Failed to inject element selection overlay"
            case .invalidSelectionResult:
                "Invalid element selection result"
            case .windowCaptureFailed:
                "Composited window capture failed (screen recording permission may be required)"
            }
        }
    }
}
