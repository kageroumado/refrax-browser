/**
 * NSSidebarTrackingAdapter-Protocol.h
 * Refrax Browser
 *
 * Private protocol used by AppKit to track sidebar divider positions
 * for titlebar/toolbar coordination.
 *
 * ## Purpose
 *
 * This protocol powers native sidebar-aware titlebar layout, including:
 * - Toolbar item alignment relative to sidebar edge
 * - Traffic light (window button) positioning
 * - Titlebar divider visuals
 *
 * ## Consumers
 *
 * - **NSThemeFrame.sidebarTrackingAdapter**: Controls titlebar layout
 *   - Mainly uses `sidebarDividerPosition` for positioning
 *   - Uses `depthOfView` for z-ordering
 *
 * - **NSTrackingSeparatorToolbarItem._partitionAdapter**: Controls toolbar layout
 *   - Uses `sidebarDividerPosition` for separator position
 *   - **Calls `isCollapsed` during validation** - must be implemented!
 *   - Uses `minimumDividerPosition` / `maximumDividerPosition` for constraints
 *
 * ## Known Implementations
 *
 * - **`_NSSplitViewPartitionAdapter`**: Full implementation, queries real split view
 *   - Implements ALL properties and methods
 *   - Safe to use with both theme frame and toolbar separator
 *
 * - **`_NSOSPSidebarTrackingAdapter`**: Minimal implementation for overlay positioning
 *   - Only implements: `sidebarDividerPosition`, `depthOfView`, `dividerWidth`, `representedView`
 *   - **DOES NOT implement**: `isCollapsed`, `overlaidAsSidebar`, etc.
 *   - Only safe for theme frame, NOT for toolbar separator
 *
 * ## Implementation Warning
 *
 * If you create a custom adapter for overlay sidebars:
 * - For theme frame only: Minimal implementation is sufficient
 * - For toolbar separator: MUST implement `isCollapsed` at minimum
 *
 * Source Reference: AppKit framework binary (macOS 26.1)
 */

#ifndef NSSidebarTrackingAdapter_Protocol_h
#define NSSidebarTrackingAdapter_Protocol_h

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol NSSidebarTrackingAdapter <NSObject>

@required

/// The X position of the sidebar divider in window coordinates.
/// This is the primary value used for layout calculations.
@property (readonly) double sidebarDividerPosition;

/// The depth of the represented view in the window's view hierarchy.
/// Used for z-ordering when multiple adapters are present.
@property (readonly) long long depthOfView;

/// The view being tracked (usually the split view).
/// Returns nil for virtual adapters like `_NSOSPSidebarTrackingAdapter`.
@property (readonly) NSObject *representedView;

@optional

/// Returns `sidebarDividerPosition` in most implementations.
/// May differ for RTL layouts.
@property (readonly) double logicalDividerPosition;

/// Whether the adapter has a valid configuration.
/// Returns YES if split view and divider index are properly set.
@property (readonly) BOOL isValidConfiguration;

/// The minimum allowed divider position (from split view item constraints).
@property (readonly) double minimumDividerPosition;

/// The maximum allowed divider position (from split view item constraints).
@property (readonly) double maximumDividerPosition;

/// Whether the tracked sidebar is collapsed.
/// **CRITICAL**: This is called by NSTrackingSeparatorToolbarItem during validation.
/// If not implemented, the toolbar will crash when validated.
@property (readonly) BOOL isCollapsed;

/// Whether the sidebar is in overlay mode (floating over content).
@property (readonly) BOOL overlaidAsSidebar;

/// The width of the divider line (usually 1pt).
@property (readonly) double dividerWidth;

/// The rect for divider cursor tracking.
@property (readonly) CGRect dividerCursorRect;

/// Additional safe area insets for the sidebar content.
@property NSEdgeInsets sidebarAdditionalSafeAreaInsets;

/// Method form of `overlaidAsSidebar` property.
- (BOOL)isOverlaidAsSidebar;

/// Programmatically sets the divider position.
- (void)setDividerPosition:(double)position;

/// Toggles the sidebar collapse state.
/// Implementation typically calls `[splitViewItem.animator() setCollapsed:!isCollapsed]`
- (void)toggleSidebar:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END

#endif /* NSSidebarTrackingAdapter_Protocol_h */
