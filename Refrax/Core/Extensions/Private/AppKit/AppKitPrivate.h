/**
 * AppKitPrivate.h
 * Refrax Browser
 *
 * Unified bridging header for AppKit private APIs.
 *
 * This header serves as the single import point for all private AppKit APIs
 * used by Refrax. It imports modular headers organized by class.
 *
 * ## Module Structure
 *
 * ### NSWindow (NSWindowPrivate.h)
 * - Corner radius customization
 * - Screenshot capture (_cgImageScreenShot, etc.)
 * - Titlebar backdrop control
 * - WindowServer layer hosting
 *
 * ### NSThemeFrame (NSThemeFramePrivate.h)
 * - Traffic light button positioning
 * - Custom titlebar height
 * - Sidebar divider integration
 * - Titlebar transparency
 *
 * ### NSToolbar (NSToolbarPrivate.h)
 * - Autohide behavior in full screen
 * - Glass effect variants
 * - Immovable item boundaries
 * - Context menu control
 * - Sidebar tracking adapters and toolbar view layout
 *
 * ### Toolbar Layout (NSToolbarView.h, NSToolbarItem.h, NSToolbarItemViewer.h)
 * - Sidebar divider positioning for titlebar alignment
 * - Item viewer glass background control
 * - Split view tracking for sidebar-aware items
 *
 * ### Sidebar Tracking (NSSidebarTrackingAdapter-Protocol.h,
 *     _NSSplitViewPartitionAdapter.h, _NSOSPSidebarTrackingAdapter.h)
 * - Native sidebar divider position sources
 * - Overlay sidebar tracking adapters
 *
 *
 * ### NSTextField (NSTextFieldPrivate.h)
 * - Password autofill control
 * - Text suggestions
 * - Writing Tools (macOS Tahoe)
 * - Border shape customization
 *
 * ### NSGlassEffectView (NSGlassEffectViewPrivate.h)
 * - Liquid Glass effects (macOS Tahoe)
 * - Glass variants and interaction states
 * - Content lensing
 * - Adaptive appearance
 *
 * ### NSVisualEffectView (NSVisualEffectViewPrivate.h)
 * - Backdrop groups for coordinated blur
 * - Material corner radius
 * - Continuous corners
 * - Chameleon appearance
 *
 * ### NSPopover (NSPopoverPrivate.h)
 * - Anchor/arrow visibility control (shouldHideAnchor)
 * - Anchor edge and size properties
 *
 * ## App Store Notice
 * These APIs are NOT allowed in App Store submissions. Refrax is distributed
 * outside the App Store.
 *
 * ## Stability
 * Private APIs may change between macOS versions. Test thoroughly on each
 * new OS release.
 *
 * ## Source References
 * All declarations are derived from AppKit framework headers using
 * reverse engineering tools. The exact behavior may differ from
 * documented assumptions.
 *
 * Last verified: macOS 26.1 SDK (Tahoe)
 */

#ifndef AppKitPrivate_h
#define AppKitPrivate_h

#import <AppKit/AppKit.h>

// Window customization and screenshot capture
#import "NSWindowPrivate.h"

// Theme frame and traffic light button control
#import "NSThemeFramePrivate.h"

// Toolbar autohide and glass effects
#import "NSToolbarPrivate.h"
#import "NSToolbarView.h"
#import "NSToolbarItem.h"
#import "NSToolbarItemViewer.h"
#import "NSToolbarPlatterView.h"

// Sidebar tracking adapters (titlebar + toolbar alignment)
#import "NSSidebarTrackingAdapter-Protocol.h"
#import "_NSSplitViewPartitionAdapter.h"
#import "_NSOSPSidebarTrackingAdapter.h"

// Text field password autofill and suggestions
#import "NSTextFieldPrivate.h"

// Liquid Glass effects (macOS Tahoe)
#import "NSGlassEffectViewPrivate.h"
#import "NSContainerConcentricGlassEffectView.h"

// Visual effect view backdrop groups
#import "NSVisualEffectViewPrivate.h"

// Split view overlay functionality (sidebar overlay)
#import "NSSplitViewPrivate.h"
#import "NSSplitViewItemPrivate.h"
#import "NSSplitViewControllerPrivate.h"

// Popover anchor control
#import "NSPopoverPrivate.h"

// Cursor override control (for resisting WKWebView cursor changes)
#import "NSCursorPrivate.h"


#endif /* AppKitPrivate_h */
