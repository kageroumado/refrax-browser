/**
 * _NSOSPSidebarTrackingAdapter.h
 * Refrax Browser
 *
 * Private AppKit adapter for overlay sidebar position tracking.
 *
 * ## What is _NSOSPSidebarTrackingAdapter?
 *
 * "OSP" likely stands for "Overlay Sidebar Position". This is a minimal
 * adapter class that implements `NSSidebarTrackingAdapter` with just
 * a settable `sidebarDividerPosition` property.
 *
 * ## Implementation Notes (from binary analysis)
 *
 * The class only has actual implementations for:
 * - `sidebarDividerPosition` / `setSidebarDividerPosition:` (stored property)
 * - `depthOfView` / `setDepthOfView:` (stored property)
 * - `dividerWidth` (returns 0.0)
 * - `representedView` (returns nil)
 *
 * **CRITICAL**: The following properties are declared but NOT implemented:
 * - `isCollapsed` - will crash if called!
 * - `overlaidAsSidebar` - will crash if called!
 * - `isValidConfiguration` - will crash if called!
 * - `minimumDividerPosition` - will crash if called!
 * - `maximumDividerPosition` - will crash if called!
 * - `logicalDividerPosition` - will crash if called!
 * - `dividerCursorRect` - will crash if called!
 *
 * ## Usage Warning
 *
 * Do NOT use this adapter with `NSTrackingSeparatorToolbarItem._setPartitionAdapter:`
 * because the toolbar item will call `isCollapsed` which is not implemented.
 *
 * For overlay sidebars where toolbar items need to track position, create a
 * custom Swift class that fully implements `NSSidebarTrackingAdapter`.
 *
 * ## When to Use
 *
 * This adapter is suitable ONLY for setting `themeFrame.sidebarTrackingAdapter`
 * where AppKit only reads `sidebarDividerPosition` for titlebar layout.
 *
 * Source Reference: AppKit framework binary (macOS 26.1)
 */

#ifndef _NSOSPSidebarTrackingAdapter_h
#define _NSOSPSidebarTrackingAdapter_h

#import <AppKit/AppKit.h>
#import "NSSidebarTrackingAdapter-Protocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface _NSOSPSidebarTrackingAdapter : NSObject <NSSidebarTrackingAdapter>

/// The sidebar divider position. This is the only settable property with
/// an actual implementation. Sets the X position of the sidebar divider.
@property double sidebarDividerPosition;

/// Depth of the view in the hierarchy. Has an actual implementation.
@property long long depthOfView;

/// Returns nil. Minimal implementation.
@property (readonly) NSObject *representedView;

/// Returns 0.0. Minimal implementation.
@property (readonly) double dividerWidth;

/// NOT IMPLEMENTED - will crash if called.
@property (readonly) double logicalDividerPosition;

/// NOT IMPLEMENTED - will crash if called.
@property (readonly) BOOL isValidConfiguration;

/// NOT IMPLEMENTED - will crash if called.
@property (readonly) double minimumDividerPosition;

/// NOT IMPLEMENTED - will crash if called.
@property (readonly) double maximumDividerPosition;

/// NOT IMPLEMENTED - will crash if called.
/// This causes crashes when used with NSTrackingSeparatorToolbarItem.
@property (readonly) BOOL isCollapsed;

/// NOT IMPLEMENTED - will crash if called.
@property (readonly) BOOL overlaidAsSidebar;

/// NOT IMPLEMENTED - will crash if called.
@property (readonly) CGRect dividerCursorRect;

/// Safe area insets for the sidebar. Has implementation.
@property NSEdgeInsets sidebarAdditionalSafeAreaInsets;

@end

NS_ASSUME_NONNULL_END

#endif /* _NSOSPSidebarTrackingAdapter_h */
