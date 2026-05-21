import AppKit

/// Swizzles NSPopover to selectively hide arrows based on registration.
///
/// This swizzle replaces the `shouldHideAnchor` property getter to return `true` only
/// for popovers that have been registered as arrowless via `registerNextPopoverAsArrowless()`.
///
/// ## Setup
/// Call `NSPopover.installArrowlessSwizzle()` once at app launch.
///
/// ## Usage
/// Before showing a popover that should be arrowless, call:
/// ```swift
/// ArrowlessPopoverSwizzle.registerNextPopoverAsArrowless()
/// ```
/// The next popover to query `shouldHideAnchor` will be registered and remain arrowless.
enum ArrowlessPopoverSwizzle {
    private static var isInstalled = false

    /// Weak set of popovers that should be arrowless.
    private static let arrowlessPopovers = NSHashTable<NSPopover>.weakObjects()

    /// Flag indicating the next popover should be registered as arrowless.
    static var nextPopoverShouldBeArrowless = false

    /// Registers the next popover to be arrowless.
    ///
    /// Call this immediately before showing a popover that should hide its arrow.
    /// The registration is consumed by the first popover that checks `shouldHideAnchor`.
    static func registerNextPopoverAsArrowless() {
        nextPopoverShouldBeArrowless = true
    }

    /// Installs the swizzle. Safe to call multiple times.
    static func install() {
        guard !isInstalled else { return }
        isInstalled = true

        let selector = NSSelectorFromString("shouldHideAnchor")

        let block: @convention(block) (NSPopover) -> Bool = { popover in
            // If this popover is already registered, return true
            if arrowlessPopovers.contains(popover) {
                return true
            }

            // If the next popover should be arrowless, register this one
            if nextPopoverShouldBeArrowless {
                nextPopoverShouldBeArrowless = false
                arrowlessPopovers.add(popover)
                return true
            }

            // Default: show the arrow
            return false
        }

        let implementation = imp_implementationWithBlock(block)

        if let method = class_getInstanceMethod(NSPopover.self, selector) {
            method_setImplementation(method, implementation)
        }
    }
}

extension NSPopover {
    /// Installs the arrowless popover swizzle.
    ///
    /// Call this method once at app launch, typically in `AppDelegate.applicationDidFinishLaunching`.
    /// After installation, only popovers registered via `ArrowlessPopoverSwizzle.registerNextPopoverAsArrowless()`
    /// will appear without arrows.
    static func installArrowlessSwizzle() {
        ArrowlessPopoverSwizzle.install()
    }
}
