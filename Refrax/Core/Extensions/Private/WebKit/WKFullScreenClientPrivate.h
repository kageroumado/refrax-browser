/**
 * WKFullScreenClientPrivate.h
 * Refrax Browser
 *
 * WebKit C API for replacing the page's fullscreen client.
 *
 * `WKPageSetFullScreenClientForTesting` swaps out the client that normally
 * creates WebKit's fullscreen window (`WKFullScreenWindowController`) and the
 * macOS fullscreen Space. With a replacement client installed, the web process
 * still runs the complete Fullscreen API sequence — `document.fullscreenElement`,
 * `fullscreenchange`, `:fullscreen` styles — while the embedder decides what
 * happens on screen. The page lays out fullscreen at the web view's current
 * size, so fullscreen is contained in the tab.
 *
 * Contract (from WKPage.cpp `FullScreenClientForTesting`):
 * - `willEnterFullScreen` and `beganExitFullScreen` receive a listener that
 *   MUST be completed via `WKCompletionListenerComplete`, or the transition
 *   stalls. A NULL callback rejects the transition instead.
 * - `beganEnterFullScreen` and `exitFullScreen` are notifications.
 *
 * Source references:
 * - WebKit/Source/WebKit/UIProcess/API/C/WKPageFullScreenClient.h
 * - WebKit/Source/WebKit/UIProcess/API/C/WKPage.cpp (adapter semantics)
 * - WebKit/Source/WebKit/Shared/API/c/WKGeometry.h (WKRect layout)
 */

#ifndef WKFullScreenClientPrivate_h
#define WKFullScreenClientPrivate_h

#import <WebKit/WebKit.h>

// MARK: - C API opaque types (WKBase.h)

typedef const struct OpaqueWKPage* WKPageRef;
typedef const void* WKTypeRef;
typedef const struct OpaqueWKCompletionListener* WKCompletionListenerRef;

// MARK: - Geometry (WKGeometry.h)

typedef struct WKFSPoint {
    double x;
    double y;
} WKFSPoint;

typedef struct WKFSSize {
    double width;
    double height;
} WKFSSize;

/// Layout-identical to WebKit's WKRect (WKPoint origin; WKSize size).
typedef struct WKFSRect {
    WKFSPoint origin;
    WKFSSize size;
} WKFSRect;

// MARK: - Fullscreen client (WKPageFullScreenClient.h)

typedef void (*WKPageWillEnterFullScreenCallback)(WKPageRef page, WKCompletionListenerRef listener, const void* clientInfo);
typedef void (*WKPageBeganEnterFullScreenCallback)(WKPageRef page, WKFSRect initialFrame, WKFSRect finalFrame, const void* clientInfo);
typedef void (*WKPageExitFullScreenCallback)(WKPageRef page, const void* clientInfo);
typedef void (*WKPageBeganExitFullScreenCallback)(WKPageRef page, WKFSRect initialFrame, WKFSRect finalFrame, WKCompletionListenerRef listener, const void* clientInfo);

typedef struct WKPageFullScreenClientBase {
    int version;
    const void* clientInfo;
} WKPageFullScreenClientBase;

typedef struct WKPageFullScreenClientV0 {
    WKPageFullScreenClientBase base;

    // Version 0.
    WKPageWillEnterFullScreenCallback willEnterFullScreen;
    WKPageBeganEnterFullScreenCallback beganEnterFullScreen;
    WKPageExitFullScreenCallback exitFullScreen;
    WKPageBeganExitFullScreenCallback beganExitFullScreen;
} WKPageFullScreenClientV0;

/// Installs a replacement fullscreen client on the page. Pass NULL to restore
/// the default client. The struct is copied; `clientInfo` must stay valid for
/// the page's lifetime.
extern void WKPageSetFullScreenClientForTesting(WKPageRef page, const WKPageFullScreenClientBase* client);

/// Completes a listener handed to a fullscreen client callback. `result` may be NULL.
extern void WKCompletionListenerComplete(WKCompletionListenerRef listener, WKTypeRef result);

/// Asks the web process to exit fullscreen (equivalent of the UA's Esc handling).
extern void WKPageRequestExitFullScreen(WKPageRef page);

// MARK: - Page reference

@interface WKWebView (RefraxFullScreenClient)

/**
 * The C API page reference for this web view.
 *
 * Named for the WebKit1→WebKit2 transition era but simply returns the
 * WKPageRef of the view's page, valid for the web view's lifetime.
 */
@property (nonatomic, readonly) WKPageRef _pageRefForTransitionToWKWebView;

@end

#endif /* WKFullScreenClientPrivate_h */
