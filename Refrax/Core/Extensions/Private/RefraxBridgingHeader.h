/**
 * RefraxBridgingHeader.h
 * Refrax Browser
 *
 * Main bridging header for Refrax.
 *
 * This header imports all private framework APIs used by Refrax.
 * It is organized into framework-specific modules for maintainability.
 *
 * ## Structure
 *
 * ```
 * Private/
 * ├── RefraxBridgingHeader.h    <- You are here
 * ├── WebKit/
 * │   ├── WebKitPrivate.h       <- WebKit umbrella header
 * │   ├── WKWebViewPrivate+Core.h
 * │   ├── WKWebViewPrivate+Media.h
 * │   ├── WKWebViewPrivate+Interaction.h
 * │   ├── WKThumbnailViewPrivate.h
 * │   ├── WKDelegatesPrivate.h
 * │   ├── WKContextMenuPrivate.h
 * │   ├── WKProcessStatePrivate.h
 * │   ├── WKInspectorPrivate.h
 * │   ├── WKWebAuthenticationPrivate.h
 * │   └── QuartzCoreSPI.h
 * └── AppKit/
 *     ├── AppKitPrivate.h       <- AppKit umbrella header
 *     ├── NSWindowPrivate.h
 *     ├── NSThemeFramePrivate.h
 *     ├── NSToolbarPrivate.h
 *     ├── NSTextFieldPrivate.h
 *     ├── NSGlassEffectViewPrivate.h
 *     └── NSVisualEffectViewPrivate.h
 * ```
 *
 * ## App Store Notice
 * These APIs are NOT allowed in App Store submissions. Refrax is
 * distributed outside the App Store.
 *
 * ## Updating
 * When adding new private APIs:
 * 1. Add the header to the appropriate framework folder
 * 2. Import it in the framework's umbrella header
 * 3. Document the APIs with their known behavior
 *
 * ## Thread Safety
 * All AppKit and WebKit APIs must be called on the main thread
 * unless explicitly documented otherwise.
 */

#ifndef RefraxBridgingHeader_h
#define RefraxBridgingHeader_h

// System frameworks
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import <QuartzCore/QuartzCore.h>

// WebKit private APIs (WKWebView, delegates, thumbnail, context menu, etc.)
#import "WebKit/WebKitPrivate.h"

// AppKit private APIs (NSWindow, NSThemeFrame, NSToolbar, glass effects, etc.)
#import "AppKit/AppKitPrivate.h"

// AutoFillUI private APIs (password picker, autofill popover)
#import "AutoFillUI/AutoFillUIPrivate.h"

// CoreAnimation private APIs (CAIOSurface for GPU texture access)
#import "CoreAnimation/CAIOSurfacePrivate.h"

// CoreGraphics private APIs (GPU hardware window capture)
#import "CoreGraphics/CoreGraphicsSPI.h"

// Note: MediaPlaybackCore APIs are loaded dynamically at runtime
// to avoid linker dependencies on private frameworks.
// See ProcessAudioTapManager.swift for implementation.

#endif /* RefraxBridgingHeader_h */
