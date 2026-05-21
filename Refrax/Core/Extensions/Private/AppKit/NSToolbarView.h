/**
 * NSToolbarView.h
 * Refrax Browser
 *
 * Private AppKit view that hosts toolbar item viewers and supports
 * sidebar-aware layout via sidebarDividerPosition.
 *
 * Source Reference: AppKit framework headers (macOS 26.1 SDK)
 */

#ifndef NSToolbarView_h
#define NSToolbarView_h

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSToolbarView : NSView {
    // Instance variables (access via KVC)
    // NSGlassContainerView *_glassContainer;
    // NSMutableArray *_glassPlatters;
}

@property double sidebarDividerPosition;
@property (weak) NSToolbar *toolbar;

/// Disables platter animations during batch updates.
- (void)_disablePlatterAnimations;

/// Re-enables platter animations after batch updates.
- (void)_enablePlatterAnimations;

/// Forces layout of dirty item viewers and tiles the toolbar.
/// Call this when the sidebar divider position changes to force a relayout.
- (void)_layoutDirtyItemViewersAndTileToolbar;

@end

NS_ASSUME_NONNULL_END

#endif /* NSToolbarView_h */
