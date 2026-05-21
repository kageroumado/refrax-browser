/**
 * NSSplitViewItemPrivate.h
 * Refrax Browser
 *
 * Private NSSplitViewItem APIs for sidebar overlay functionality.
 *
 * These APIs control how individual split view items behave when collapsed,
 * including overlay mode where the item appears over content instead of
 * being hidden.
 *
 * ## Key Features
 *
 * - **Overlay State**: Check and set overlay mode
 * - **Edge Reveal**: Control fullscreen edge hover behavior
 * - **Peeking**: Preview sidebar before full reveal
 *
 * ## App Store Notice
 * These APIs are NOT allowed in App Store submissions.
 *
 * ## Source Reference
 * Derived from AppKit framework headers (macOS 26.1 SDK)
 */

#ifndef NSSplitViewItemPrivate_h
#define NSSplitViewItemPrivate_h

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - NSSplitViewItem Private Extensions

@interface NSSplitViewItem (RefraxPrivate)

/**
 * The wrapper view used by NSSplitView for this item.
 *
 * This is the view that NSSplitView directly manages. It contains
 * the item's viewController.view and handles collapse animations.
 * Use this for overlay transforms instead of the viewController's view.
 */
@property (nonatomic, readonly, nullable) NSView *_splitViewItemWrapperView;

/**
 * Whether this item is currently in overlay mode.
 *
 * When overlaid, the item's view appears over adjacent content
 * instead of taking space in the split view layout.
 */
@property (nonatomic, getter=isOverlaid) BOOL overlaid;

/**
 * Whether this item reveals on edge hover in fullscreen.
 *
 * When YES, moving the cursor to the edge of the screen in fullscreen
 * will reveal this sidebar item.
 *
 * Set to NO to disable AppKit's automatic edge reveal and handle
 * it manually.
 */
@property (nonatomic) BOOL revealsOnEdgeHoverInFullscreen;

/**
 * Uncollapses the item, preferring overlay mode.
 *
 * If the item supports overlay, it will be uncollapsed as an overlay.
 * Otherwise, it will be uncollapsed normally.
 */
- (void)_uncollapsePreferringOverlay;

/**
 * Whether this item can be overlaid.
 *
 * @return YES if the item supports overlay mode.
 */
- (BOOL)canOverlay;

/**
 * Whether the item has a floating appearance.
 *
 * Floating items appear detached from the window frame.
 */
- (BOOL)_hasFloatingAppearance;

/**
 * Whether the item wants glass (Liquid Glass) styling.
 */
- (BOOL)_wantsGlass;

/**
 * Whether the item wants a material background.
 */
- (BOOL)_wantsMaterialBackground;

/**
 * Starts the peeking animation.
 *
 * Peeking shows a preview of the collapsed sidebar before full reveal.
 */
- (void)_startPeeking;

/**
 * Stops the peeking animation.
 */
- (void)_stopPeeking;

/**
 * Whether this item is currently peeking.
 */
- (BOOL)_isPeeking;

/**
 * Whether this item is effectively collapsed.
 *
 * This accounts for animation state and may differ from `isCollapsed`
 * during transitions.
 */
- (BOOL)_isEffectivelyCollapsed;

/**
 * The split view controller containing this item.
 */
- (nullable NSSplitViewController *)_splitViewController;

/**
 * Whether this item has a base vibrancy effect (NSVisualEffectView with CABackdropLayer).
 *
 * When NO, the wrapper view skips creating the _effectView (NSVisualEffectView)
 * and its CABackdropLayer. Set to NO before the wrapper's _updateEffectViewState
 * runs to prevent backdrop creation entirely.
 */
- (BOOL)_hasBaseVibrancyEffect;
- (void)_setHasBaseVibrancyEffect:(BOOL)effect;

@end

#pragma mark - _NSSplitViewItemViewWrapper Private Extensions

/**
 * Private methods on _NSSplitViewItemViewWrapper (accessed through NSView typing).
 *
 * The wrapper view is returned as NSView * from _splitViewItemWrapperView,
 * so these are declared as a category on NSView.
 */
@interface NSView (SplitViewItemViewWrapperPrivate)

/**
 * Whether the wrapper creates an NSVisualEffectView with backdrop blur.
 *
 * When set to NO and _updateEffectViewState is called, the existing
 * _effectView is torn down.
 */
@property (nonatomic) BOOL hasBaseVibrancyEffect;

/**
 * Syncs the wrapper's _effectView (NSVisualEffectView) state with the
 * hasBaseVibrancyEffect flag. Call after changing the flag to create or
 * tear down the effect view.
 */
- (void)_updateEffectViewState;

@end

NS_ASSUME_NONNULL_END

#endif /* NSSplitViewItemPrivate_h */
