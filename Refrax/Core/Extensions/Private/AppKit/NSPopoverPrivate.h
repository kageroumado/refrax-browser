/**
 * NSPopoverPrivate.h
 * Refrax Browser
 *
 * Private APIs for NSPopover customization.
 *
 * ## Available APIs
 *
 * ### Anchor Visibility
 * - `shouldHideAnchor` / `setShouldHideAnchor:` - Hides the popover's arrow/anchor
 *
 * ## Usage
 *
 * ```objc
 * NSPopover *popover = [[NSPopover alloc] init];
 * [popover setShouldHideAnchor:YES]; // Arrow-less popover
 * ```
 *
 * ## App Store Notice
 * These APIs are NOT allowed in App Store submissions. Refrax is distributed
 * outside the App Store.
 *
 * ## Source Reference
 * Derived from AppKit framework headers using ipsw.
 *
 * Last verified: macOS 26.1 SDK (Tahoe)
 */

#ifndef NSPopoverPrivate_h
#define NSPopoverPrivate_h

#import <AppKit/AppKit.h>

@interface NSPopover (Private)

/**
 * Controls whether the popover's arrow/anchor is visible.
 *
 * When set to YES, the popover displays without an arrow, appearing as a
 * floating rectangle near the positioning view.
 *
 * @property shouldHideAnchor Whether to hide the arrow. Default is NO.
 */
@property (nonatomic) BOOL shouldHideAnchor;

/**
 * The current edge where the anchor is displayed.
 *
 * This is the computed edge after layout, which may differ from preferredEdge
 * if the popover needed to flip to fit on screen.
 */
@property (nonatomic, readonly) NSRectEdge anchorEdge;

/**
 * Size of the anchor/arrow.
 *
 * Returns the size of the anchor triangle used for positioning calculations.
 */
@property (nonatomic, readonly) CGSize anchorSize;

@end

#endif /* NSPopoverPrivate_h */
