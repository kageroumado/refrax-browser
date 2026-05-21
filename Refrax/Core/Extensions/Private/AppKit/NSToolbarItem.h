/**
 * NSToolbarItem.h
 * Refrax Browser
 *
 * Private extensions for toolbar items used to access item viewers and
 * split view tracking for sidebar-aware layout.
 *
 * ## Key Properties
 *
 * - **`_itemViewer`**: The NSToolbarItemViewer that renders this item
 * - **`_partitionAdapter`**: The NSSidebarTrackingAdapter for sidebar tracking
 * - **`trackedSplitView`**: The split view being tracked (for tracking separators)
 *
 * ## Partition Adapter
 *
 * The `_partitionAdapter` property is used by `NSTrackingSeparatorToolbarItem`
 * (`.sidebarTrackingSeparator`) to track a sidebar divider position.
 *
 * **Important**: The partition adapter MUST implement `isCollapsed` because
 * the toolbar calls this during validation. Using `_NSOSPSidebarTrackingAdapter`
 * will crash since it doesn't implement `isCollapsed`.
 *
 * Safe adapters for toolbar items:
 * - `_NSSplitViewPartitionAdapter` - Full implementation, always safe
 *
 * Unsafe adapters for toolbar items:
 * - `_NSOSPSidebarTrackingAdapter` - Minimal implementation, will crash
 *
 * ## Implementation Notes (from binary analysis)
 *
 * - `_setPartitionAdapter:` removes KVO observer from old adapter before setting new
 * - Observes `sidebarDividerPosition` and `isCollapsed` on the adapter
 * - `_isPartitionItem` returns true for `NSTrackingSeparatorToolbarItem`
 *
 * Source Reference: AppKit framework binary (macOS 26.1)
 */

#ifndef NSToolbarItem_h
#define NSToolbarItem_h

#import <AppKit/AppKit.h>
#import "NSToolbarItemViewer.h"
#import "NSSidebarTrackingAdapter-Protocol.h"

NS_ASSUME_NONNULL_BEGIN

@interface NSToolbarItem (Private)

/// The item viewer that renders this toolbar item.
/// Contains the actual view displayed in the toolbar.
@property (retain) NSToolbarItemViewer *_itemViewer;

/// The split view being tracked (for tracking separator items).
@property (retain, nonatomic) NSSplitView *trackedSplitView;

/// Which divider to track (0 = first divider).
@property (nonatomic) long long trackedSplitViewDividerIndex;

/// Sets the partition adapter for sidebar tracking.
///
/// Used by NSTrackingSeparatorToolbarItem to track a sidebar divider position.
/// The adapter is observed via KVO for `sidebarDividerPosition` and `isCollapsed`.
///
/// **Warning**: The adapter MUST implement `isCollapsed`. Using an adapter that
/// doesn't implement this method (like `_NSOSPSidebarTrackingAdapter`) will crash
/// when the toolbar validates.
- (void)_setPartitionAdapter:(nullable id<NSSidebarTrackingAdapter>)adapter;

/// Returns the current partition adapter.
- (nullable id<NSSidebarTrackingAdapter>)_partitionAdapter;

/// Whether this item is a partition item (sidebarTrackingSeparator).
/// Returns YES for NSTrackingSeparatorToolbarItem instances.
@property (readonly) BOOL _isPartitionItem;

/// The logical position of the partition (sidebar divider).
/// Computed from the partition adapter's `logicalDividerPosition`.
@property (readonly) double _logicalPartitionPosition;

/// The visual position of the partition (sidebar divider).
/// Computed from the partition adapter's `sidebarDividerPosition`.
@property (readonly) double _visualPartitionPosition;

@end

NS_ASSUME_NONNULL_END

#endif /* NSToolbarItem_h */
