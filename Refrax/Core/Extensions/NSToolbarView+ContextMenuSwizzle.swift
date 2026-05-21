import AppKit

/// Disables the NSToolbar right-click context menu and forwards the event
/// to the underlying web content.
///
/// By default, right-clicking the toolbar shows a menu with display mode options
/// (Icons Only, Icons and Text, etc.). This interferes with webpage context menus
/// in Refrax since web content extends under the toolbar.
///
/// This swizzle intercepts `rightMouseDown:` on `NSToolbarView` and forwards the
/// event to whatever view lies underneath in the content area.
enum ToolbarContextMenuSwizzle {
    private static var isInstalled = false

    /// Installs the swizzle. Safe to call multiple times.
    static func install() {
        guard !isInstalled else { return }
        isInstalled = true

        guard let toolbarViewClass = NSClassFromString("NSToolbarView") else { return }

        let selector = NSSelectorFromString("rightMouseDown:")

        let block: @convention(block) (NSView, NSEvent) -> Void = { toolbarView, event in
            guard let window = toolbarView.window,
                  let contentView = window.contentView
            else { return }

            // Convert from window coordinates to content view coordinates
            let locationInContent = contentView.convert(event.locationInWindow, from: nil)

            // Find the view at this location, excluding the toolbar hierarchy
            guard let hitView = contentView.hitTest(locationInContent),
                  !hitView.isDescendant(of: toolbarView)
            else { return }

            hitView.rightMouseDown(with: event)
        }

        let implementation = imp_implementationWithBlock(block)

        // IMPORTANT: We must use class_addMethod first. If NSToolbarView doesn't
        // override rightMouseDown: (inherits from NSView), class_getInstanceMethod
        // returns NSView's method. Using method_setImplementation on that would
        // modify NSView's implementation, affecting ALL NSView subclasses.
        //
        // class_addMethod adds the method only to NSToolbarView. It returns false
        // if the class already has its own implementation, in which case we can
        // safely use method_setImplementation on the class-specific method.
        let typeEncoding = "v@:@" // void return, self, _cmd, NSEvent*
        if !class_addMethod(toolbarViewClass, selector, implementation, typeEncoding) {
            // NSToolbarView has its own implementation, safe to replace
            if let method = class_getInstanceMethod(toolbarViewClass, selector) {
                method_setImplementation(method, implementation)
            }
        }
    }
}
