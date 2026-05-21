import AppKit

/// Makes empty toolbar areas transparent to mouse events, allowing clicks to reach content underneath.
///
/// NSToolbarView's `hitTest:` returns itself for all points within its bounds—even transparent/empty
/// areas—which claims mouse events for window dragging. This blocks interaction with content that
/// extends under the toolbar (`fullSizeContentView`), particularly web content and SwiftUI views.
///
/// This swizzle intercepts `hitTest:` and returns `nil` for empty areas when there's clickable
/// content underneath, allowing the window to dispatch events to that content instead. When there's
/// nothing underneath, the original behavior is preserved (enabling window drag).
///
/// ## Why hitTest instead of mouseDown?
///
/// SwiftUI views use gesture recognizers that are triggered during the window's event dispatch,
/// not when `mouseDown(with:)` is called directly. By swizzling `hitTest:`, we intercept *before*
/// dispatch, so the window naturally routes events to content views and their gesture systems work.
///
/// ## Hit-testing logic:
/// 1. If the point hits an interactive toolbar element → return original result (toolbar handles it)
/// 2. If empty space and content underneath wants events → return nil (content handles it)
/// 3. If empty space and nothing underneath → return original result (preserves window drag)
enum ToolbarMouseDownSwizzle {
    private static var isInstalled = false
    private static var originalImplementation: IMP?
    /// Re-entrancy guard: prevents infinite recursion when `contentView.hitTest()`
    /// traverses back into the toolbar view (e.g., during fullscreen transitions
    /// where titlebar views are nested inside the content hierarchy).
    private static var isInHitTest = false

    /// Installs the swizzle. Safe to call multiple times.
    static func install() {
        guard !isInstalled else { return }
        isInstalled = true

        guard let toolbarViewClass = NSClassFromString("NSToolbarView") else { return }

        let selector = #selector(NSView.hitTest(_:))

        // Store the original implementation for calling when needed
        if let originalMethod = class_getInstanceMethod(toolbarViewClass, selector) {
            originalImplementation = method_getImplementation(originalMethod)
        }

        let block: @convention(block) (NSView, NSPoint) -> NSView? = { toolbarView, point in
            handleHitTest(toolbarView: toolbarView, point: point)
        }

        let implementation = imp_implementationWithBlock(block)

        // Use class_addMethod first to avoid modifying NSView's implementation
        // (same safety pattern as ToolbarContextMenuSwizzle)
        let typeEncoding = "@@:{CGPoint=dd}" // NSView* return, self, _cmd, NSPoint
        if !class_addMethod(toolbarViewClass, selector, implementation, typeEncoding) {
            // NSToolbarView has its own implementation, safe to replace
            if let method = class_getInstanceMethod(toolbarViewClass, selector) {
                method_setImplementation(method, implementation)
            }
        }
    }

    private static func handleHitTest(toolbarView: NSView, point: NSPoint) -> NSView? {
        // Prevent infinite recursion: contentView.hitTest() below can traverse
        // back into NSToolbarView, retriggering this swizzle.
        guard !isInHitTest else {
            return callOriginalHitTest(on: toolbarView, point: point)
        }

        isInHitTest = true
        defer { isInHitTest = false }

        // Get the original hit test result
        let originalHit = callOriginalHitTest(on: toolbarView, point: point)

        // If nothing was hit, return nil
        guard let hitView = originalHit else { return nil }

        // If we hit an interactive toolbar element, let the toolbar handle it
        if isInteractiveToolbarElement(hitView, in: toolbarView) {
            return hitView
        }

        // Empty area hit - check if content underneath wants this event
        guard let window = toolbarView.window,
              let contentView = window.contentView
        else {
            return originalHit
        }

        // Convert point to content view coordinates
        let pointInWindow = toolbarView.convert(point, to: nil)
        let pointInContent = contentView.convert(pointInWindow, from: nil)

        // Find what's at this location in the content view, excluding the toolbar hierarchy
        guard let contentHit = contentView.hitTest(pointInContent),
              !contentHit.isDescendant(of: toolbarView)
        else {
            // Nothing underneath wants the event, let toolbar handle it (window drag)
            return originalHit
        }

        // Special case: NSHostingView doesn't do proper hit testing into SwiftUI.
        // It returns itself for most areas, but SwiftUI handles its own gesture dispatch
        // internally. If contentHit is an NSHostingView, pass through to let SwiftUI handle it.
        if contentHit === contentView, !NSStringFromClass(type(of: contentHit)).contains("NSHostingView") {
            // Plain NSView content view with no specific target - let toolbar handle (window drag)
            return originalHit
        }

        // Content underneath wants the event - return nil so window dispatches to it
        return nil
    }

    /// Checks if the given view is an interactive toolbar element.
    private static func isInteractiveToolbarElement(_ view: NSView, in toolbarView: NSView) -> Bool {
        // If we hit the toolbar view itself, it's empty space
        if view === toolbarView { return false }

        // _NSToolbarFlexibleSpace is also empty space
        let typeName = NSStringFromClass(type(of: view))
        if typeName.hasSuffix("_NSToolbarFlexibleSpace") {
            return false
        }

        // Walk up the hierarchy to check for interactive elements
        var current: NSView? = view
        while let check = current {
            // Stop at the toolbar view
            if check === toolbarView { break }

            let checkTypeName = NSStringFromClass(type(of: check))

            // Check for NSToolbarItemViewer
            if checkTypeName.contains("ToolbarItemViewer") {
                return true
            }

            // Check for controls (buttons, etc.)
            if check is NSControl {
                return true
            }

            current = check.superview
        }

        return false
    }

    /// Calls the original hitTest implementation.
    private static func callOriginalHitTest(on toolbarView: NSView, point: NSPoint) -> NSView? {
        guard let original = originalImplementation else {
            // Fallback to super's implementation if we don't have the original
            return toolbarView.superview?.hitTest(toolbarView.convert(point, to: toolbarView.superview))
        }

        // Cast to the expected function signature and call
        typealias HitTestFunc = @convention(c) (NSView, Selector, NSPoint) -> NSView?
        let originalFunc = unsafeBitCast(original, to: HitTestFunc.self)
        return originalFunc(toolbarView, #selector(NSView.hitTest(_:)), point)
    }
}
