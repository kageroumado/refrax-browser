/**
 * _NSSplitViewPartitionAdapter.h
 * Refrax Browser
 *
 * Private AppKit adapter that wraps an NSSplitView to provide sidebar
 * divider position tracking for titlebar and toolbar layout.
 *
 * ## Purpose
 *
 * This adapter bridges an NSSplitView with the sidebar tracking system.
 * It's the "real" adapter that AppKit uses when you have an actual split
 * view sidebar. Unlike `_NSOSPSidebarTrackingAdapter`, this class fully
 * implements the `NSSidebarTrackingAdapter` protocol.
 *
 * ## Implementation Notes (from binary analysis)
 *
 * All properties have actual implementations that query the split view:
 *
 * - `sidebarDividerPosition`: Returns the X position of the tracked divider
 * - `isCollapsed`: Calls `_trackedArrangedView` then `_isTargetStateOfArrangedViewCollapsed:`
 * - `overlaidAsSidebar` / `isOverlaidAsSidebar`: Checks if the sidebar item is overlaid
 * - `logicalDividerPosition`: Returns `sidebarDividerPosition`
 * - `minimumDividerPosition`: Queries the split view item's minimum thickness
 * - `maximumDividerPosition`: Queries the split view item's maximum thickness
 * - `depthOfView`: Returns the depth in the view hierarchy
 * - `representedView`: Returns the split view
 * - `dividerWidth`: Returns the split view's divider thickness
 *
 * ## Configuration
 *
 * To use this adapter:
 * ```objc
 * _NSSplitViewPartitionAdapter *adapter = [[_NSSplitViewPartitionAdapter alloc] init];
 * adapter.splitView = mySplitView;
 * adapter.splitViewDividerIndex = 0;  // First divider (leading sidebar)
 * adapter.sidebarIsTrailingDivider = NO;  // Leading sidebar
 * ```
 *
 * ## Usage with NSTrackingSeparatorToolbarItem
 *
 * This is the correct adapter to use with `NSTrackingSeparatorToolbarItem._setPartitionAdapter:`
 * because it fully implements `isCollapsed` and other required methods.
 *
 * ## Internal Methods Called
 *
 * From disassembly:
 * - `_trackedArrangedView` - Gets the arranged subview being tracked
 * - `_isTargetStateOfArrangedViewCollapsed:` - Checks collapse state
 * - `_splitViewDividerFrame` - Gets the divider frame
 * - `_sidebar` - Returns the sidebar split view item
 * - `_isSidebar` / `_isInspector` - Type checks
 *
 * Source Reference: AppKit framework binary (macOS 26.1)
 */

#ifndef _NSSplitViewPartitionAdapter_h
#define _NSSplitViewPartitionAdapter_h

#import <AppKit/AppKit.h>
#import "NSSidebarTrackingAdapter-Protocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface _NSSplitViewPartitionAdapter : NSObject <NSSidebarTrackingAdapter>

/// The split view to track. Must be set before use.
@property (retain, nonatomic) NSSplitView *splitView;

/// Which divider to track (0 = first divider between items 0 and 1).
@property (nonatomic) long long splitViewDividerIndex;

/// Whether the sidebar is on the trailing side (right in LTR).
/// Set to NO for a leading sidebar (left in LTR).
@property (nonatomic) BOOL sidebarIsTrailingDivider;

/// Returns the X position of the divider being tracked.
/// Computed from the split view's arranged subviews.
@property (readonly) double sidebarDividerPosition;

/// Returns the minimum position based on split view item constraints.
@property (readonly) double minimumDividerPosition;

/// Returns the maximum position based on split view item constraints.
@property (readonly) double maximumDividerPosition;

/// Returns YES if the tracked sidebar item is collapsed.
/// Implementation: `[splitView _isTargetStateOfArrangedViewCollapsed:trackedView]`
@property (readonly) BOOL isCollapsed;

/// Returns YES if the sidebar item is in overlay mode.
/// Implementation: checks `[splitViewItem isOverlaid]`
@property (readonly) BOOL overlaidAsSidebar;

/// Returns `sidebarDividerPosition` (same value).
@property (readonly) double logicalDividerPosition;

/// Returns the depth of the split view in the window hierarchy.
@property (readonly) long long depthOfView;

/// Returns the split view.
@property (readonly) NSObject *representedView;

/// Returns YES if splitView and dividerIndex are valid.
@property (readonly) BOOL isValidConfiguration;

/// Returns the split view's divider thickness.
@property (readonly) double dividerWidth;

/// Returns the frame of the divider for cursor tracking.
@property (readonly) CGRect dividerCursorRect;

/// Additional safe area insets for the sidebar.
@property NSEdgeInsets sidebarAdditionalSafeAreaInsets;

/// Programmatically sets the divider position.
- (void)setDividerPosition:(double)position;

/// Method form of overlaidAsSidebar property.
- (BOOL)isOverlaidAsSidebar;

/// Toggles the sidebar collapse state.
/// Equivalent to `[splitViewItem.animator() setCollapsed:!isCollapsed]`
- (void)toggleSidebar:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END

#endif /* _NSSplitViewPartitionAdapter_h */
