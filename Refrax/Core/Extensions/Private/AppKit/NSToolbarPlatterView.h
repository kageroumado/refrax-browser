/**
 * NSToolbarPlatterView.h
 * Refrax Browser
 *
 * Private AppKit view that provides the Liquid Glass background effect
 * for grouped toolbar items.
 *
 * Source Reference: AppKit framework headers (macOS 26.1 SDK)
 */

#ifndef NSToolbarPlatterView_h
#define NSToolbarPlatterView_h

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSToolbarPlatterView : NSView

/// The content view containing the toolbar items.
@property (readonly, retain, nullable) NSView *contentView;

/// The toolbar items contained in this platter.
@property (copy, nullable) NSArray *containedItems;

/// The target frame for animation.
@property CGRect targetFrame;

/// Custom tint color for the platter.
@property (copy, nullable) NSColor *tintColor;

/// The visual variant of the platter (0 = default, 1 = subdued, etc.)
@property long long variant;

/// The subdued state of the platter.
@property long long subduedState;

/// Whether this platter is in a customization palette view.
@property BOOL inPaletteView;

/// Disables animations for this platter.
- (void)disableAnimations;

/// Enables animations for this platter.
- (void)enableAnimations;

/// Whether the platter is currently animating its origin.
@property (readonly) BOOL animatingOrigin;

/// Whether the platter is currently animating its size.
@property (readonly) BOOL animatingSize;

@end

NS_ASSUME_NONNULL_END

#endif /* NSToolbarPlatterView_h */
