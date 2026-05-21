import AppKit

/// Fixes a memory leak in SwiftUI's context menu system.
///
/// SwiftUI's `ContextMenuResponder.AppKitMenuDelegate` has a strong `menuResponder` ivar that
/// points back to the hosting controller. This creates a retain cycle that prevents deallocation
/// when the menu closes, leaking megabytes of delegates and menus (which contain images).
///
/// This swizzle intercepts `menuDidClose:` to nil out the `menuResponder` reference,
/// breaking the retain cycle and allowing proper cleanup.
///
/// ## The Bug
///
/// ```
/// ContextMenuResponder (lazy) → AppKitMenuDelegate
///                              ↓
///                         menuResponder (strong) → ContextMenuResponder
/// ```
///
/// The lazy storage keeps AppKitMenuDelegate alive, and menuResponder keeps the responder alive.
/// When the menu closes, nothing breaks the cycle.
///
/// ## The Fix
///
/// After calling the original `menuDidClose:`, we set `menuResponder` to nil via KVC,
/// allowing the responder to be deallocated.
enum SwiftUIContextMenuLeakFix {
    private static var isInstalled = false
    private static var originalImplementation: IMP?

    /// Installs the swizzle. Safe to call multiple times.
    static func install() {
        guard !isInstalled else { return }
        isInstalled = true

        // The class name is mangled: _TtCC7SwiftUI20ContextMenuResponder18AppKitMenuDelegate
        guard let delegateClass = NSClassFromString("_TtCC7SwiftUI20ContextMenuResponder18AppKitMenuDelegate") else {
            return
        }

        let selector = NSSelectorFromString("menuDidClose:")

        // Store the original implementation
        if let originalMethod = class_getInstanceMethod(delegateClass, selector) {
            originalImplementation = method_getImplementation(originalMethod)
        }

        let block: @convention(block) (NSObject, NSMenu) -> Void = { delegate, menu in
            // Call original implementation first
            callOriginalMenuDidClose(on: delegate, menu: menu)

            // Break the retain cycle by nilling out the menuResponder ivar directly
            // (KVC doesn't work because Swift properties aren't automatically @objc)
            nilOutMenuResponder(on: delegate)
        }

        let implementation = imp_implementationWithBlock(block)
        let typeEncoding = "v@:@" // void return, self, _cmd, NSMenu*

        if !class_addMethod(delegateClass, selector, implementation, typeEncoding) {
            if let method = class_getInstanceMethod(delegateClass, selector) {
                method_setImplementation(method, implementation)
            }
        }
    }

    private static func callOriginalMenuDidClose(on delegate: NSObject, menu: NSMenu) {
        guard let original = originalImplementation else { return }

        typealias MenuDidCloseFunc = @convention(c) (NSObject, Selector, NSMenu) -> Void
        let originalFunc = unsafeBitCast(original, to: MenuDidCloseFunc.self)
        originalFunc(delegate, NSSelectorFromString("menuDidClose:"), menu)
    }

    /// Nils out the menuResponder ivar using Objective-C runtime.
    ///
    /// Swift properties aren't automatically KVC-compliant, so we access the ivar directly.
    private static func nilOutMenuResponder(on delegate: NSObject) {
        let delegateClass: AnyClass = type(of: delegate)

        // Get the ivar for menuResponder
        guard let ivar = class_getInstanceVariable(delegateClass, "menuResponder") else {
            return
        }

        // Set the ivar to nil
        // object_setIvar expects an AnyObject?, so we pass nil
        object_setIvar(delegate, ivar, nil)
    }
}
