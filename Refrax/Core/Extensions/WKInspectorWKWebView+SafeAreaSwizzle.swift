import AppKit

/// Swizzles WKInspectorWKWebView.setFrame: to extend the inspector to the top of its container.
///
/// WebKit's inspector constrains its frame to the window's safe area via `contentLayoutRect`,
/// respecting the title bar. This is appropriate for Safari (which has toolbar items at top),
/// but Refrax has no chrome in the title bar area, so the inspector should extend to the top.
///
/// This swizzle intercepts `setFrame:` on `WKInspectorWKWebView` (WebKit's inspector view class)
/// and extends the frame height to fill the superview when the inspector is docked (attached
/// to a browser window rather than floating in a standalone window).
///
/// ## Setup
/// Call `InspectorSafeAreaSwizzle.install()` once at app launch.
enum InspectorSafeAreaSwizzle {
    private static var isInstalled = false
    private static var originalImplementation: IMP?

    /// Installs the swizzle. Safe to call multiple times.
    static func install() {
        guard !isInstalled else { return }

        // WKInspectorWKWebView is a private WebKit class
        guard let inspectorViewClass = NSClassFromString("WKInspectorWKWebView") else {
            Logger.warning(
                "WKInspectorWKWebView class not found, inspector safe area swizzle not installed",
                category: Logger.webview,
            )
            return
        }

        isInstalled = true

        let selector = #selector(setter: NSView.frame)

        // Store the original implementation
        if let originalMethod = class_getInstanceMethod(inspectorViewClass, selector) {
            originalImplementation = method_getImplementation(originalMethod)
        }

        let block: @convention(block) (NSView, NSRect) -> Void = { view, frame in
            let adjustedFrame = adjustFrameForDockedInspector(view: view, proposedFrame: frame)
            callOriginalSetFrame(on: view, frame: adjustedFrame)
        }

        let implementation = imp_implementationWithBlock(block)

        // Use class_addMethod first to avoid modifying WKWebView's implementation
        let typeEncoding = "v@:{CGRect={CGPoint=dd}{CGSize=dd}}" // void, self, _cmd, NSRect
        if !class_addMethod(inspectorViewClass, selector, implementation, typeEncoding) {
            // WKInspectorWKWebView has its own implementation (or inherits), safe to replace
            if let method = class_getInstanceMethod(inspectorViewClass, selector) {
                method_setImplementation(method, implementation)
            }
        }
    }

    /// Adjusts the frame to extend to the top of the superview when docked.
    private static func adjustFrameForDockedInspector(view: NSView, proposedFrame: NSRect) -> NSRect {
        // Only adjust if this appears to be a docked inspector (not standalone window)
        guard isDocked(view: view) else {
            return proposedFrame
        }

        guard let superview = view.superview else {
            return proposedFrame
        }

        // Extend the frame to fill the full height of the superview
        // The inspector is constrained by contentLayoutRect which excludes the title bar safe area.
        // We want it to extend to the top, so use superview.bounds.height.
        var adjustedFrame = proposedFrame
        adjustedFrame.size.height = superview.bounds.height - proposedFrame.origin.y

        return adjustedFrame
    }

    /// Determines if the inspector view is docked (attached to browser window) vs standalone.
    ///
    /// When docked, the inspector is added as a sibling of the inspected WKWebView inside
    /// a container view. When standalone, it's the main content of a dedicated inspector window.
    private static func isDocked(view: NSView) -> Bool {
        guard let superview = view.superview,
              let window = view.window,
              let contentView = window.contentView
        else {
            return false
        }

        // If the superview is NOT the window's content view, inspector is docked inside a container
        // (like CocoaWebViewAdapter). If superview IS the content view, it's standalone.
        return superview !== contentView
    }

    /// Calls the original setFrame: implementation.
    private static func callOriginalSetFrame(on view: NSView, frame: NSRect) {
        guard let original = originalImplementation else {
            // Fallback to direct frame assignment (shouldn't happen)
            view.frame = frame
            return
        }

        // Cast to the expected function signature and call
        typealias SetFrameFunc = @convention(c) (NSView, Selector, NSRect) -> Void
        let originalFunc = unsafeBitCast(original, to: SetFrameFunc.self)
        originalFunc(view, #selector(setter: NSView.frame), frame)
    }
}
