/**
 * NSSplitViewPrivate.h
 * Refrax Browser
 *
 * Private NSSplitView APIs for sidebar overlay functionality.
 *
 * These APIs enable the overlay sidebar feature where the sidebar content
 * appears over the main content instead of pushing it aside. This is used
 * for Arc-style sidebar behavior.
 *
 * ## Key Features
 *
 * - **Overlay Mode**: Show collapsed items as overlays
 * - **Animated Collapse**: Collapse with overlay option
 * - **Edge Reveal**: Reveal sidebar on edge hover
 *
 * ## App Store Notice
 * These APIs are NOT allowed in App Store submissions.
 *
 * ## Source Reference
 * Derived from AppKit framework headers (macOS 26.1 SDK)
 */

#ifndef NSSplitViewPrivate_h
#define NSSplitViewPrivate_h

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - NSSplitView Private Extensions

@interface NSSplitView (RefraxPrivate)

/**
 * Collapses an arranged view with animation.
 *
 * @param view The view to collapse.
 * @param animated Whether to animate the collapse.
 */
- (void)_collapseArrangedView:(NSView *)view animated:(BOOL)animated;

/**
 * Uncollapses an arranged view.
 *
 * @param view The view to uncollapse.
 */
- (void)_uncollapseArrangedView:(NSView *)view;

/**
 * Uncollapses an arranged view with animation.
 *
 * @param view The view to uncollapse.
 * @param animated Whether to animate the uncollapse.
 */
- (void)_uncollapseArrangedView:(NSView *)view animated:(BOOL)animated;

/**
 * Uncollapses an arranged view, optionally overlaying it.
 *
 * When overlayed, the view appears over the adjacent content instead
 * of pushing it aside.
 *
 * @param view The view to uncollapse.
 * @param overlayIfNecessary Whether to overlay the view if it was collapsed.
 * @return YES if the operation succeeded.
 */
- (BOOL)_uncollapseArrangedView:(NSView *)view overlayIfNecessary:(BOOL)overlayIfNecessary;

/**
 * Puts an arranged view into overlay mode.
 *
 * The view appears over adjacent content instead of taking space.
 *
 * @param view The view to overlay.
 */
- (void)_overlayArrangedView:(NSView *)view;

/**
 * Uncollapses a view and puts it into overlay mode.
 *
 * Combined operation for revealing a collapsed sidebar as an overlay.
 *
 * @param view The view to uncollapse and overlay.
 */
- (void)_uncollapseAndOverlayArrangedView:(NSView *)view;

/**
 * Uncollapses a view with overlay and animation.
 *
 * This is the primary method for animated overlay sidebar reveal.
 *
 * @param view The view to uncollapse.
 * @param animated Whether to animate the transition.
 */
- (void)_uncollapseWithOverlayArrangedView:(NSView *)view animated:(BOOL)animated;

/**
 * Simulates a collapse without actually collapsing.
 *
 * Useful for preview animations or testing overlay behavior.
 *
 * @param collapse Whether to simulate collapse (YES) or uncollapse (NO).
 * @param view The view to fake collapse.
 * @param canOverlay Whether overlay is permitted.
 * @param handler Completion handler called when animation finishes.
 */
- (void)_fakeCollapse:(BOOL)collapse
         arrangedView:(NSView *)view
           canOverlay:(BOOL)canOverlay
          withHandler:(void (^ _Nullable)(void))handler;

/**
 * Whether a view can be auto-collapsed.
 *
 * @param view The view to check.
 * @return YES if the view supports auto-collapse.
 */
- (BOOL)_canAutocollapseArrangedView:(NSView *)view;

/**
 * Whether a view is currently auto-collapsed.
 *
 * @param view The view to check.
 * @return YES if the view is auto-collapsed.
 */
- (BOOL)_isArrangedViewAutoCollapsed:(NSView *)view;

/**
 * Whether auto-collapse animations are enabled.
 */
@property (nonatomic) BOOL _animatesAutocollapses;

@end

NS_ASSUME_NONNULL_END

#endif /* NSSplitViewPrivate_h */
