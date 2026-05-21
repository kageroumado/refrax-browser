/**
 * NSToolbarItemViewer.h
 * Refrax Browser
 *
 * Private AppKit view wrapper for toolbar items. Exposes glass-related
 * properties used to control background rendering and grouping.
 *
 * Source Reference: AppKit framework headers (macOS 26.1 SDK)
 */

#ifndef NSToolbarItemViewer_h
#define NSToolbarItemViewer_h

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NSToolbarPlatterView;

@interface NSToolbarItemViewer : NSView

/// The toolbar item this viewer displays.
@property (readonly, nullable) NSToolbarItem *item;

/// Whether the viewer has a transparent background.
@property BOOL transparentBackground;

/// Whether the viewer is positioned in the glass sidebar area.
@property BOOL inGlassSidebar;

/// Whether this is the first item in its glass group.
@property BOOL firstItemInGlassGroup;

/// Whether this is the last item in its glass group.
@property BOOL lastItemInGlassGroup;

/// The glass behavior for this item (0 = none, 1 = platter, etc.)
@property (readonly) NSUInteger glassBehavior;

/// The glass platter view that provides the background effect.
@property (weak, nullable) NSToolbarPlatterView *associatedPlatter;

/// Whether the item is currently animating in.
@property BOOL animatingIn;

/// Whether the item is currently animating out.
@property BOOL animatingOut;

@end

NS_ASSUME_NONNULL_END

#endif /* NSToolbarItemViewer_h */
