import AppKit
@preconcurrency import ScreenCaptureKit

/// Captures screenshots of NSWindow instances.
///
/// Used by ``RefraxControlServer`` to serve window-level screenshots
/// to the CLI control interface.
///
/// Uses `SCShareableContent.getCurrentProcessShareableContent()` (macOS 14.4+)
/// to discover the app's own windows without requiring screen recording permission,
/// then `SCScreenshotManager.captureImage` to capture the window.
nonisolated enum WindowScreenshotService {
    /// Captures a screenshot of the specified window including all chrome.
    ///
    /// Uses `currentProcess` shareable content, so no screen recording permission is needed.
    /// Backdrop effects (Liquid Glass) are **not** preserved — the backing store capture
    /// replaces them with an opaque substitute color.
    ///
    /// - Parameter window: The window to capture.
    /// - Returns: PNG image data, or `nil` if capture fails.
    @MainActor
    static func captureWindow(_ window: NSWindow) async -> Data? {
        let windowNumber = CGWindowID(window.windowNumber)
        let scale = window.backingScaleFactor

        guard let content = try? await SCShareableContent.currentProcess,
              let scWindow = content.windows.first(where: { $0.windowID == windowNumber }) else {
            return nil
        }

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)

        let config = SCStreamConfiguration()
        config.width = Int(window.frame.width * scale)
        config.height = Int(window.frame.height * scale)
        config.showsCursor = false
        config.captureResolution = .best

        guard let cgImage = try? await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: config,
        ) else {
            return nil
        }

        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }

    /// Captures a screenshot of the specified window with Liquid Glass effects preserved.
    ///
    /// Backdrop blur and vibrancy (`CABackdropLayer`) are composited by WindowServer,
    /// not by the app. A `desktopIndependentWindow` capture reads the backing store
    /// *before* compositing, so glass effects fall back to an opaque substitute color.
    ///
    /// This method works around that by:
    /// 1. Capturing the full display output (composited by WindowServer) cropped to the window rect
    /// 2. Capturing the window independently for its alpha channel (rounded corners)
    /// 3. Compositing: display pixels clipped by the window's alpha mask
    ///
    /// - Important: Requires screen recording permission (system prompt on first use).
    ///
    /// - Parameter window: The window to capture.
    /// - Returns: PNG image data, or `nil` if capture fails.
    @MainActor
    static func captureWindowComposited(_ window: NSWindow) async -> Data? {
        let windowNumber = CGWindowID(window.windowNumber)
        let scale = window.backingScaleFactor
        let windowFrame = window.frame

        // Full SCShareableContent (not .currentProcess) — we need display info and all windows.
        guard let content = try? await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        ) else {
            return nil
        }

        guard let scWindow = content.windows.first(where: { $0.windowID == windowNumber }) else {
            return nil
        }

        // Find the display containing this window.
        guard let display = content.displays.first(where: { display in
            let displayRect = CGRect(
                x: display.frame.origin.x,
                y: display.frame.origin.y,
                width: CGFloat(display.width),
                height: CGFloat(display.height),
            )
            return displayRect.intersects(windowFrame)
        }) ?? content.displays.first else {
            return nil
        }

        let pixelWidth = Int(windowFrame.width * scale)
        let pixelHeight = Int(windowFrame.height * scale)

        // Step 1: Capture the composited display output cropped to the window rect.
        // This preserves all WindowServer effects (backdrop blur, vibrancy, shadows).
        let displayFilter = SCContentFilter(display: display, excludingWindows: [])
        let displayConfig = SCStreamConfiguration()
        displayConfig.sourceRect = scWindow.frame
        displayConfig.width = pixelWidth
        displayConfig.height = pixelHeight
        displayConfig.showsCursor = false
        displayConfig.captureResolution = .best

        guard let composited = try? await SCScreenshotManager.captureImage(
            contentFilter: displayFilter,
            configuration: displayConfig,
        ) else {
            return nil
        }

        // Step 2: Capture the window independently for its alpha channel (rounded corners).
        let windowFilter = SCContentFilter(desktopIndependentWindow: scWindow)
        let windowConfig = SCStreamConfiguration()
        windowConfig.width = pixelWidth
        windowConfig.height = pixelHeight
        windowConfig.showsCursor = false
        windowConfig.captureResolution = .best
        windowConfig.shouldBeOpaque = false

        guard let windowAlpha = try? await SCScreenshotManager.captureImage(
            contentFilter: windowFilter,
            configuration: windowConfig,
        ) else {
            return nil
        }

        // Step 3: Composite — display capture clipped by window alpha mask.
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: composited.width,
            height: composited.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else {
            return nil
        }

        let fullRect = CGRect(x: 0, y: 0, width: composited.width, height: composited.height)
        ctx.saveGState()
        ctx.clip(to: fullRect, mask: windowAlpha)
        ctx.draw(composited, in: fullRect)
        ctx.restoreGState()

        guard let result = ctx.makeImage() else {
            return nil
        }

        let rep = NSBitmapImageRep(cgImage: result)
        return rep.representation(using: .png, properties: [:])
    }
}
