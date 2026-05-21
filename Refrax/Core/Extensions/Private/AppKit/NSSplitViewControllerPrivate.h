/**
 * NSSplitViewControllerPrivate.h
 * Refrax Browser
 *
 * Private NSSplitViewController APIs for sidebar overlay functionality.
 *
 * These APIs provide controller-level control over split view item
 * collapse and overlay behavior.
 *
 * ## Key Features
 *
 * - **Force Overlay**: Collapse items with forced overlay mode
 * - **Edge Reveal**: Reveal overlaid items on edge hover
 * - **Fullscreen Coordination**: Manage overlay in fullscreen
 *
 * ## App Store Notice
 * These APIs are NOT allowed in App Store submissions.
 *
 * ## Source Reference
 * Derived from AppKit framework headers (macOS 26.1 SDK)
 */

#ifndef NSSplitViewControllerPrivate_h
#define NSSplitViewControllerPrivate_h

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - NSSplitViewController Private Extensions

@interface NSSplitViewController (RefraxPrivate)

/**
 * Collapses or uncollapses a split view item with overlay control.
 *
 * This is the primary method for implementing overlay sidebar behavior.
 * When forceOverlay is YES, the item will appear over content instead
 * of being hidden or pushing content aside.
 *
 * @param collapse YES to collapse, NO to uncollapse.
 * @param item The split view item to collapse/uncollapse.
 * @param forceOverlay YES to force overlay mode when uncollapsing.
 * @param completionHandler Called when the animation completes.
 */
- (void)_collapse:(BOOL)collapse
    splitViewItem:(NSSplitViewItem *)item
     forceOverlay:(BOOL)forceOverlay
completionHandler:(void (^ _Nullable)(void))completionHandler;

/**
 * Whether an item can be overlaid.
 *
 * @param item The item to check.
 * @return YES if the item supports overlay mode.
 */
- (BOOL)_canOverlayItem:(NSSplitViewItem *)item;

/**
 * Whether an item can be overlaid in fullscreen.
 *
 * @param item The item to check.
 * @return YES if the item can overlay in fullscreen.
 */
- (BOOL)_canOverlaySplitViewItemInFullScreen:(NSSplitViewItem *)item;

/**
 * Reveals an edge-hovering overlaid item.
 *
 * Called when the user moves the cursor to the edge to reveal
 * a collapsed sidebar.
 *
 * @param item The item to reveal.
 */
- (void)_uncollapseEdgeRevealItem:(NSSplitViewItem *)item;

/**
 * Updates the overlay state for all items.
 */
- (void)_updateOverlays;

/**
 * Whether the split view contains a sidebar.
 *
 * @param splitView The split view to check.
 * @return YES if it contains a sidebar item.
 */
- (BOOL)_splitViewContainsSidebar:(NSSplitView *)splitView;

/**
 * Whether the split view contains a full-height sidebar.
 *
 * @param splitView The split view to check.
 * @return YES if it contains a full-height sidebar.
 */
- (BOOL)_splitViewContainsFullHeightSidebar:(NSSplitView *)splitView;

/**
 * Gets the sidebar item for toggling.
 *
 * @return The sidebar item, or nil if none exists.
 */
- (nullable NSSplitViewItem *)_sidebarItemForToggling;

/**
 * Gets the inspector item for toggling.
 *
 * @return The inspector item, or nil if none exists.
 */
- (nullable NSSplitViewItem *)_inspectorItemForToggling;

/**
 * Called when entering fullscreen.
 *
 * @param notification The fullscreen notification.
 */
- (void)_didEnterFullscreen:(NSNotification *)notification;

/**
 * Called when exiting fullscreen.
 *
 * @param notification The fullscreen notification.
 */
- (void)_didExitFullscreen:(NSNotification *)notification;

/**
 * Starts observing fullscreen events for a window.
 *
 * @param window The window to observe.
 */
- (void)_startObservingFullscreenForWindow:(NSWindow *)window;

/**
 * Stops observing fullscreen events for a window.
 *
 * @param window The window to stop observing.
 */
- (void)_stopObservingFullscreenForWindow:(NSWindow *)window;

/**
 * Minimum thickness for inline sidebars.
 */
@property (nonatomic) CGFloat minimumThicknessForInlineSidebars;

@end

NS_ASSUME_NONNULL_END

#endif /* NSSplitViewControllerPrivate_h */
