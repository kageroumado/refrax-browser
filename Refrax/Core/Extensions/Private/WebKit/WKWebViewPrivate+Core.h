/**
 * WKWebViewPrivate+Core.h
 * Refrax Browser
 *
 * Core private WKWebView extensions for browser functionality.
 *
 * This header declares fundamental private APIs for WKWebView that enable
 * essential browser features like page lifecycle management, document detection,
 * and presentation synchronization.
 *
 * ## Contents
 * - Page lifecycle methods (_close, _tryClose, _isClosed)
 * - Document type detection (_isDisplayingPDF, _isDisplayingStandaloneImageDocument)
 * - Presentation update synchronization
 * - Reload variants
 * - Content preloading
 *
 * ## Thread Safety
 * All APIs must be called on the main thread.
 *
 * ## Source Reference
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebViewPrivate.h
 *
 * Last verified: WebKit trunk (December 2024)
 */

#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - _WKRectEdge Type

/**
 * Edge flags for scroll rubberbanding and scrolling operations.
 *
 * These values are based on CGRectEdge constants for compatibility.
 */
typedef NS_OPTIONS(NSUInteger, _WKRectEdge) {
    _WKRectEdgeNone = 0,
    _WKRectEdgeLeft = 1 << CGRectMinXEdge,
    _WKRectEdgeTop = 1 << CGRectMinYEdge,
    _WKRectEdgeRight = 1 << CGRectMaxXEdge,
    _WKRectEdgeBottom = 1 << CGRectMaxYEdge,
    _WKRectEdgeAll = _WKRectEdgeLeft | _WKRectEdgeTop | _WKRectEdgeRight | _WKRectEdgeBottom
} API_AVAILABLE(macos(10.13.4), ios(18.0), visionos(2.0));

#pragma mark - WKScrollGeometry

/**
 * Scroll geometry information for the web view.
 *
 * This class provides information about the scroll position, content size,
 * and visible area of a web view. It's used by the scroll geometry change
 * delegate method to notify about scroll state changes.
 *
 * ## Source Reference
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKScrollGeometry.h
 *
 * ## Availability
 * macOS 26.0+
 */
API_AVAILABLE(macos(26.0))
@interface WKScrollGeometry : NSObject

/** The size of the scroll view container. */
@property (nonatomic, readonly) CGSize containerSize;

/** The edge insets for the content. */
@property (nonatomic, readonly) NSEdgeInsets contentInsets;

/** The current scroll offset of the content. */
@property (nonatomic, readonly) CGPoint contentOffset;

/** The total size of the scrollable content. */
@property (nonatomic, readonly) CGSize contentSize;

/** Initializer with all geometry values. */
- (instancetype)initWithContainerSize:(CGSize)containerSize
                        contentInsets:(NSEdgeInsets)contentInsets
                        contentOffset:(CGPoint)contentOffset
                          contentSize:(CGSize)contentSize;

@end

#pragma mark - WKWebView Core Private Extensions

/**
 * Core private methods for WKWebView lifecycle and state management.
 */
@interface WKWebView (WKPrivateCore)

#pragma mark - Page Lifecycle

/**
 * Closes the web view and releases all resources.
 *
 * Call this when permanently closing a tab. This method:
 * - Terminates the web process
 * - Releases all associated resources
 * - Invalidates pending loads and JavaScript execution
 *
 * @warning After calling this method, the web view cannot be reused.
 *          Create a new WKWebView instance for subsequent use.
 *
 * @note This is a synchronous operation that immediately begins cleanup.
 */
- (void)_close;

/**
 * Attempts to close the web view gracefully, respecting beforeunload handlers.
 *
 * Unlike `_close`, this method checks if the page has unsaved changes by firing
 * the `beforeunload` event. If a handler prevents the close (by returning a
 * truthy value or calling `event.preventDefault()`), the close is cancelled.
 *
 * @return `YES` if the close was initiated successfully.
 *         `NO` if the page prevented closing via `beforeunload`.
 *
 * ## Usage
 * Use this for user-initiated close requests where you want to prevent
 * accidental data loss:
 *
 * @code
 * if (![webView _tryClose]) {
 *     // Page prevented close - show confirmation dialog
 *     [self showCloseConfirmationForWebView:webView];
 * }
 * @endcode
 *
 * ## Availability
 * macOS 10.15.4+, iOS 13.4+
 */
- (BOOL)_tryClose API_AVAILABLE(macos(10.15.4), ios(13.4));

/**
 * Checks whether the web view has been closed.
 *
 * @return `YES` if `_close` or a successful `_tryClose` has been called.
 *
 * ## Usage
 * Check this before performing operations on a web view that may have been closed:
 *
 * @code
 * if (![webView _isClosed]) {
 *     [webView evaluateJavaScript:@"..." completionHandler:nil];
 * }
 * @endcode
 *
 * ## Availability
 * macOS 10.15.4+, iOS 13.4+
 */
- (BOOL)_isClosed API_AVAILABLE(macos(10.15.4), ios(13.4));

#pragma mark - Process Identifiers

@property (nonatomic, readonly) pid_t _webProcessIdentifier;
@property (nonatomic, readonly) pid_t _provisionalWebProcessIdentifier API_AVAILABLE(macos(10.14.4), ios(12.2));
@property (nonatomic, readonly) pid_t _gpuProcessIdentifier API_AVAILABLE(macos(13.0), ios(16.0));

#pragma mark - Document Type Detection

/**
 * Whether the web view is displaying a PDF document.
 *
 * `YES` when the main frame is showing a PDF file (either loaded directly
 * or via `data:` URI with PDF content type).
 *
 * ## Usage
 * Show PDF-specific toolbar controls:
 *
 * @code
 * if (webView._displayingPDF) {
 *     [self showPDFToolbar];
 * }
 * @endcode
 *
 * ## Availability
 * macOS 15.0+, iOS 18.0+
 */
@property (nonatomic, readonly, getter=_isDisplayingPDF) BOOL _displayingPDF
    API_AVAILABLE(macos(15.0), ios(18.0));

/**
 * Whether the web view is displaying a standalone image document.
 *
 * `YES` when navigated directly to an image file (e.g., `https://example.com/photo.jpg`).
 * This is NOT set when viewing an HTML page that contains images.
 *
 * ## Usage
 * Show image-specific controls (zoom, rotate, save):
 *
 * @code
 * if (webView._displayingStandaloneImageDocument) {
 *     [self showImageControls];
 * }
 * @endcode
 */
@property (nonatomic, readonly, getter=_isDisplayingStandaloneImageDocument)
    BOOL _displayingStandaloneImageDocument;

#pragma mark - Presentation Updates

/**
 * Executes a block after the next presentation update completes.
 *
 * Use this to ensure the web view has finished rendering before performing
 * operations that require accurate visual state, such as taking screenshots
 * or measuring rendered content.
 *
 * @param updateBlock The block to execute after the presentation update.
 *                    This block is always called on the main thread.
 *
 * ## Usage
 * @code
 * [webView _doAfterNextPresentationUpdate:^{
 *     // Web view has finished rendering - safe to take snapshot
 *     [webView takeSnapshotWithConfiguration:config completionHandler:^(NSImage *image, NSError *error) {
 *         // Handle snapshot
 *     }];
 * }];
 * @endcode
 *
 * ## Timing
 * The block is called after:
 * - All pending layout is complete
 * - Compositing has occurred
 * - The content is ready for display
 *
 * ## Availability
 * macOS 10.12+, iOS 10.0+
 */
- (void)_doAfterNextPresentationUpdate:(void (^)(void))updateBlock
    API_AVAILABLE(macos(10.12), ios(10.0));

#pragma mark - Reload Variants

/**
 * Reloads the page bypassing all content blockers.
 *
 * Use this when a site is broken by content blocking rules or when the user
 * wants to see blocked content. This reload does NOT permanently disable
 * content blockers - subsequent navigations will apply them normally.
 *
 * @return A navigation object representing the reload, or nil if the reload
 *         could not be started.
 *
 * ## Usage
 * Implement a "Reload Without Content Blockers" menu item:
 *
 * @code
 * - (IBAction)reloadWithoutBlockers:(id)sender {
 *     [webView _reloadWithoutContentBlockers];
 * }
 * @endcode
 *
 * ## Availability
 * macOS 10.12+, iOS 10.0+
 */
- (nullable WKNavigation *)_reloadWithoutContentBlockers
    API_AVAILABLE(macos(10.12), ios(10.0));

/**
 * Reloads only resources that have expired in the cache.
 *
 * More efficient than a full reload - only fetches resources whose cache
 * headers indicate they're stale. Useful for "soft refresh" functionality.
 *
 * @return A navigation object representing the reload, or nil if the reload
 *         could not be started.
 *
 * ## Cache Behavior
 * - Resources with valid `Cache-Control` or `Expires` that haven't expired
 *   are NOT re-fetched
 * - The main document is always checked (conditional GET with `If-Modified-Since`)
 * - Resources without cache headers are re-fetched
 *
 * ## Availability
 * macOS 10.13+, iOS 11.0+
 */
- (nullable WKNavigation *)_reloadExpiredOnly
    API_AVAILABLE(macos(10.13), ios(11.0));

#pragma mark - Alternate HTML Loading

/**
 * The URL that was unreachable, causing alternate HTML to be displayed.
 *
 * When `_loadAlternateHTMLString:baseURL:forUnreachableURL:` is used to show
 * an error page, this property returns the original URL that failed to load.
 * This URL is recorded in the back-forward list, enabling proper history
 * navigation even when showing error content.
 *
 * @return The unreachable URL, or nil if not showing alternate content.
 *
 * ## Usage
 * Check this to determine if the web view is showing an error page:
 *
 * @code
 * if (webView._unreachableURL != nil) {
 *     // Currently showing error page for this URL
 *     NSURL *failedURL = webView._unreachableURL;
 * }
 * @endcode
 */
@property (nonatomic, readonly, nullable) NSURL *_unreachableURL;

/**
 * Loads alternate HTML content for an unreachable URL.
 *
 * This method displays custom HTML content (typically an error page) while
 * recording the unreachable URL in the back-forward list. This enables:
 *
 * - **Proper history**: The failed URL appears in back/forward navigation
 * - **Correct reload**: Reloading retries the original URL, not the error page
 * - **URL display**: The address bar shows the failed URL, not about:blank
 *
 * ## Usage
 *
 * Show a custom error page when a navigation fails:
 *
 * @code
 * NSString *errorHTML = @"<html><body><h1>Page Not Found</h1></body></html>";
 * [webView _loadAlternateHTMLString:errorHTML
 *                           baseURL:[NSURL URLWithString:@"about:blank"]
 *                 forUnreachableURL:failedURL];
 * @endcode
 *
 * ## History Behavior
 *
 * Unlike `loadHTMLString:baseURL:`, this method:
 * 1. Records `unreachableURL` in the back-forward list
 * 2. Sets `_unreachableURL` property to the failed URL
 * 3. Reload will attempt to load `unreachableURL` again
 *
 * @param string The HTML content to display.
 * @param baseURL The base URL for resolving relative references in the HTML.
 * @param unreachableURL The original URL that failed to load.
 */
- (void)_loadAlternateHTMLString:(NSString *)string
                         baseURL:(nullable NSURL *)baseURL
               forUnreachableURL:(NSURL *)unreachableURL;

#pragma mark - Content Preloading

/**
 * Preconnects to a server for faster subsequent requests.
 *
 * This establishes a connection (including DNS lookup, TCP handshake, and
 * TLS negotiation) to the server before any request is made, reducing latency
 * for the first actual request.
 *
 * @param serverURL The URL of the server to preconnect to. Only the scheme,
 *                  host, and port are used - the path is ignored.
 *
 * ## Usage
 * Preconnect to likely navigation targets:
 *
 * @code
 * // User is hovering over a link - preconnect to improve perceived performance
 * [webView _preconnectToServer:[NSURL URLWithString:@"https://example.com"]];
 * @endcode
 *
 * ## Performance
 * Preconnecting can save 100-500ms on the first request to a server,
 * especially on high-latency connections or when TLS is involved.
 *
 * ## Availability
 * macOS 11.0+, iOS 14.0+
 */
- (void)_preconnectToServer:(NSURL *)serverURL
    API_AVAILABLE(macos(11.0), ios(14.0));

#pragma mark - Page State

/**
 * Whether the web view's content is currently suspended.
 *
 * When suspended, the web view is not executing JavaScript and may have
 * reduced resource usage. This typically happens when:
 * - The app is backgrounded (iOS)
 * - System memory pressure causes tab suspension
 * - The web view is explicitly suspended via configuration
 */
@property (nonatomic, readonly) BOOL _isSuspended;

#pragma mark - Visual Properties

/**
 * The sampled color from the top of the page.
 *
 * WebKit samples the background color at the top of the page content.
 * Use this to:
 * - Match browser chrome (toolbar, title bar) to page content
 * - Create seamless visual transitions
 * - Implement dynamic theming based on page content
 *
 * @return The sampled color, or nil if not available.
 *
 * ## Note
 * This differs from `themeColor` which comes from `<meta name="theme-color">`.
 * This property is the actual rendered color at the top of the viewport.
 *
 * ## Availability
 * macOS 12.0+, iOS 15.0+
 */
@property (nonatomic, readonly, nullable) NSColor *_sampledPageTopColor
    API_AVAILABLE(macos(12.0));

/**
 * The overflow height for the top scroll edge effect.
 *
 * This value indicates the height of sticky/fixed-position content at the
 * top of the page. When greater than 0, it means the page has a sticky
 * header that should influence how the scroll edge effect is displayed.
 *
 * ## Usage
 * Use this to detect sticky headers and adapt blur effects:
 *
 * @code
 * if (webView._overflowHeightForTopScrollEdgeEffect > 0) {
 *     // Page has sticky header - use uniform blur
 * } else {
 *     // No sticky header - use gradient blur
 * }
 * @endcode
 *
 * ## Availability
 * macOS 26.0+
 */
@property (nonatomic, setter=_setOverflowHeightForTopScrollEdgeEffect:)
    CGFloat _overflowHeightForTopScrollEdgeEffect API_AVAILABLE(macos(26.0));

/**
 * Whether the scroll pocket prefers solid color (hard) blur over gradient (soft) blur.
 *
 * **Note:** This property only reflects client-explicit requests via
 * `_addReasonToPreferSolidColorHardPocket:`. It does NOT automatically reflect
 * WebKit's internal sticky header detection. To detect sticky headers, use
 * `_sampledTopFixedPositionContentColor` instead (non-nil = sticky header present).
 *
 * ## Availability
 * macOS 26.0+
 */
@property (nonatomic, setter=_setPrefersSolidColorHardScrollPocket:)
    BOOL _prefersSolidColorHardScrollPocket API_AVAILABLE(macos(26.0));

/**
 * The sampled color from fixed-position content at the top of the page.
 *
 * Returns the predominant color of any fixed/sticky position elements that
 * intersect the top edge of the viewport. This is used by the scroll pocket
 * system to match the color of sticky headers.
 *
 * **Use this for sticky header detection:** If this returns non-nil, the page
 * has a sticky header that WebKit has detected. Use uniform blur in this case.
 *
 * ## Prerequisites
 * For this property to return non-nil, the following must be true:
 * - `contentInsetBackgroundFillEnabled` preference must be enabled
 *   (automatically true when Liquid Glass is enabled in system)
 * - The page must have `position: fixed` or `position: sticky` elements
 * - The fixed elements must intersect the top of the viewport
 *
 * ## Usage
 * @code
 * if (webView._sampledTopFixedPositionContentColor != nil) {
 *     // Page has sticky header - use uniform blur
 * } else {
 *     // No sticky header - use gradient blur
 * }
 * @endcode
 *
 * ## Availability
 * macOS 26.0+
 */
@property (nonatomic, readonly, nullable) NSColor *_sampledTopFixedPositionContentColor
    API_AVAILABLE(macos(26.0));

/**
 * The top scroll pocket view, if one exists.
 *
 * Returns the NSScrollPocket that renders the scroll edge effect above the
 * web content. This is only created when:
 * - `contentInsetBackgroundFillEnabled` preference is true (automatic when Liquid Glass enabled)
 * - `_topContentInset > 0` OR `_overflowHeightForTopScrollEdgeEffect > 0`
 * - Either `_usesAutomaticContentInsetBackgroundFill` is YES or
 *   `_automaticallyAdjustsContentInsets` is YES
 *
 * If this returns nil but you've set up the prerequisites, check that the
 * WebKit `contentInsetBackgroundFillEnabled` preference is enabled (this
 * requires Liquid Glass to be enabled in the system).
 *
 * ## Availability
 * macOS 26.0+
 */
@property (nonatomic, readonly, nullable) NSView *_topScrollPocket API_AVAILABLE(macos(26.0));

/**
 * The edges that have fixed/sticky position content detected by WebKit.
 *
 * This is a bitmask of `_WKRectEdge` values indicating which viewport edges
 * have fixed or sticky position elements. When `_WKRectEdgeTop` is set,
 * `_sampledTopFixedPositionContentColor` will return a color.
 *
 * This is populated via IPC from the WebProcess when layout detects
 * viewport-constrained objects. If this returns `_WKRectEdgeNone` despite
 * having sticky headers, it means the WebProcess isn't detecting them.
 *
 * ## Prerequisites for detection:
 * - `contentInsetBackgroundFillEnabled` preference must be true
 * - `obscuredContentInsets().top() > 0` must be set BEFORE page layout
 * - Page must have `position: fixed` or `position: sticky` elements
 */
@property (nonatomic, readonly) _WKRectEdge _fixedContainerEdges;

/**
 * Whether the scroll pocket system is active (diagnostic property).
 *
 * Returns YES if ALL of these conditions are met:
 * 1. `contentInsetBackgroundFillEnabled` preference is YES (requires Liquid Glass)
 * 2. `obscuredContentInsets.top > 0` OR `overflowHeightForTopScrollEdgeEffect > 0`
 *
 * This is useful for diagnosing scroll pocket issues. If this returns NO
 * but you've set obscured insets, it means the WebKit preference is disabled
 * (system Liquid Glass might not be enabled).
 *
 * ## Availability
 * macOS 26.0+ (internal method, not in public headers)
 */
@property (nonatomic, readonly) BOOL scrollViewDrawsMagicPocket API_AVAILABLE(macos(26.0));

/**
 * Whether the web view draws its background.
 *
 * When NO, the web view's background is transparent, allowing underlying
 * views to show through. When YES (default), the web view draws its
 * configured background color.
 *
 * ## Usage
 * Use this for custom backgrounds behind web content:
 *
 * @code
 * webView._drawsBackground = NO;
 * // Now the web view is transparent
 * @endcode
 *
 * ## Note
 * Web page content with its own background colors will still render normally.
 * This only affects areas where the page has no explicit background.
 */
@property (nonatomic, setter=_setDrawsBackground:) BOOL _drawsBackground;

/**
 * Whether the web view automatically fills the content inset area with
 * a matching background color using the scroll pocket system.
 *
 * When YES:
 * - Enables the NSScrollPocket system (macOS 26+)
 * - Scroll pocket renders with `NSScrollPocketStyleAutomatic`
 * - WebKit automatically samples and adapts colors from page content
 * - Pocket may hide/show based on scroll position
 * - Enables sticky header detection via `_prefersSolidColorHardScrollPocket`
 *
 * When NO (default):
 * - Scroll pocket renders with `NSScrollPocketStyleHard` (solid color)
 * - Manual color management via `_overrideTopScrollEdgeEffectColor`
 * - More explicit control but requires manual management
 *
 * ## Prerequisites
 * For the scroll pocket to be created, you must also set:
 * - `_topContentInset > 0` OR `_overflowHeightForTopScrollEdgeEffect > 0`
 * - Call `_setObscuredContentInsets:immediate:` to trigger creation
 *
 * ## Usage
 * @code
 * // Enable automatic background fill
 * webView._usesAutomaticContentInsetBackgroundFill = YES;
 *
 * // Set top inset to trigger scroll pocket creation
 * [webView _setTopContentInset:44 immediate:YES];
 *
 * // Now _prefersSolidColorHardScrollPocket will work
 * @endcode
 *
 * ## Availability
 * macOS 26.0+
 */
@property (nonatomic, setter=_setUsesAutomaticContentInsetBackgroundFill:)
    BOOL _usesAutomaticContentInsetBackgroundFill API_AVAILABLE(macos(26.0));

/**
 * The obscured content insets for the web view.
 *
 * Represents areas of the web view that are obscured by overlaying UI (toolbars, etc).
 * Setting this with a non-zero top value triggers scroll pocket creation.
 *
 * ## Availability
 * macOS 26.0+
 */
@property (nonatomic, readonly) NSEdgeInsets _obscuredContentInsets API_AVAILABLE(macos(26.0));

/**
 * Sets the obscured content insets with optional immediate dispatch.
 *
 * This method triggers scroll pocket creation when top > 0. The `immediate` parameter
 * controls whether changes are dispatched synchronously to the web process.
 *
 * @param insets The edge insets to set.
 * @param immediate If YES, changes are dispatched immediately (synchronous).
 *                  If NO, changes are batched with other updates (better performance).
 *
 * ## Usage
 * @code
 * // Set insets to create scroll pocket
 * NSEdgeInsets insets = NSEdgeInsetsMake(44, 0, 0, 0);
 * [webView _setObscuredContentInsets:insets immediate:YES];
 * @endcode
 *
 * ## Availability
 * macOS 26.0+
 */
- (void)_setObscuredContentInsets:(NSEdgeInsets)insets
                        immediate:(BOOL)immediate API_AVAILABLE(macos(26.0));

/**
 * Sets the top content inset with optional immediate dispatch.
 *
 * Convenience method that only modifies the top component of obscured insets,
 * preserving any existing left/right/bottom values.
 *
 * @param inset The top inset value in points.
 * @param immediate If YES, changes are dispatched immediately.
 *
 * ## Usage
 * @code
 * // Set top inset for toolbar
 * [webView _setTopContentInset:44 immediate:YES];
 * @endcode
 *
 * ## Availability
 * macOS 15.4+
 */
- (void)_setTopContentInset:(CGFloat)inset
                  immediate:(BOOL)immediate API_AVAILABLE(macos(15.4));

/**
 * Whether the web view automatically adjusts content insets.
 *
 * When YES, the web view automatically adds content insets to account
 * for overlapping system UI elements like toolbars and safe areas.
 */
@property (nonatomic, setter=_setAutomaticallyAdjustsContentInsets:)
    BOOL _automaticallyAdjustsContentInsets;

#pragma mark - Content Insets

/**
 * The top content inset for the web view.
 *
 * Use this to offset web content below browser UI elements like toolbars.
 * The inset creates space at the top where page content won't render,
 * similar to safe area insets.
 */
@property (nonatomic, setter=_setTopContentInset:) CGFloat _topContentInset;

/**
 * Sets the top content inset with optional immediate application.
 *
 * @param topContentInset The inset value in points.
 * @param immediate If YES, applies the inset immediately without animation.
 *                  If NO, the change may be animated.
 *
 * ## When to Use `immediate:YES`
 * - During window resize operations
 * - When showing/hiding toolbars instantly
 * - To avoid visual glitches during rapid layout changes
 *
 * ## Availability
 * macOS 15.4+, iOS 18.4+
 */
- (void)_setTopContentInset:(CGFloat)topContentInset immediate:(BOOL)immediate
    API_AVAILABLE(macos(15.4), ios(18.4));

#pragma mark - Window Move Preparation

/**
 * Prepares the web view for being moved to a different window.
 *
 * Call this method before moving a WKWebView from one window to another to ensure
 * proper layer reparenting and avoid visual glitches. WebKit defers certain
 * view-in-window state changes during this process to prevent rendering artifacts.
 *
 * @param targetWindow The window the web view will be moved to. Pass nil if removing
 *                     from all windows.
 * @param completionHandler Called when the web view is ready to be moved.
 *
 * ## Usage
 * @code
 * [webView _prepareForMoveToWindow:newWindow completionHandler:^{
 *     [newWindow.contentView addSubview:webView];
 *     // Apply any content insets after the move
 *     [webView _setTopContentInset:52 immediate:YES];
 * }];
 * @endcode
 *
 * ## Availability
 * macOS 10.13+
 */
- (void)_prepareForMoveToWindow:(nullable NSWindow *)targetWindow
              completionHandler:(void (^)(void))completionHandler
    API_AVAILABLE(macos(10.13));

#pragma mark - PDF Support

/**
 * Takes a PDF snapshot of the web view content.
 *
 * Creates a PDF representation of the current page, suitable for printing
 * or saving as a document.
 *
 * @param snapshotConfiguration Configuration for the snapshot (rect, scale, etc.).
 *                              Pass nil for default configuration.
 * @param completionHandler Called with PDF data on success, or error on failure.
 *
 * ## Usage
 * @code
 * [webView _takePDFSnapshotWithConfiguration:nil completionHandler:^(NSData *pdfData, NSError *error) {
 *     if (pdfData) {
 *         [pdfData writeToURL:saveURL atomically:YES];
 *     }
 * }];
 * @endcode
 *
 * ## Availability
 * macOS 10.15.4+, iOS 13.4+
 */
- (void)_takePDFSnapshotWithConfiguration:(nullable WKSnapshotConfiguration *)snapshotConfiguration
                        completionHandler:(void (^)(NSData * _Nullable pdfData,
                                                    NSError * _Nullable error))completionHandler
    API_AVAILABLE(macos(10.15.4), ios(13.4));

#pragma mark - TLS Status

/**
 * Whether any resource on the page was loaded using legacy TLS (1.0 or 1.1).
 *
 * Use this to show security warnings when legacy TLS is in use, as these
 * versions have known vulnerabilities.
 *
 * ## KVO Compliance
 * This property is KVO-compliant. Observe changes to update security indicators.
 *
 * ## Availability
 * macOS 10.15.4+, iOS 13.4+
 */
@property (nonatomic, readonly) BOOL _negotiatedLegacyTLS
    API_AVAILABLE(macos(10.15.4), ios(13.4));

#pragma mark - Find in Page

/**
 * Whether the web view uses the platform's built-in find UI.
 *
 * When NO, the web view does not show the platform's find bar. Use this
 * when implementing a custom find UI with NSTextFinder.
 *
 * Default is YES.
 *
 * ## Usage
 * @code
 * webView._usePlatformFindUI = NO;
 * // Now set up custom NSTextFinder with web view as client
 * @endcode
 */
@property (nonatomic, setter=_setUsePlatformFindUI:) BOOL _usePlatformFindUI;

/**
 * Hides any visible find UI highlights in the web view.
 *
 * Call this when dismissing the find bar to clear any visible search
 * highlights from the web content.
 */
- (void)_hideFindUI;

#pragma mark - Scroll Geometry Updates

/**
 * Enables or disables scroll geometry change notifications.
 *
 * When enabled, the UI delegate will receive `_webView:geometryDidChange:`
 * callbacks with `WKScrollGeometry` data.
 *
 * @param value YES to enable scroll geometry updates, NO to disable.
 */
- (void)_setNeedsScrollGeometryUpdates:(BOOL)value;

#pragma mark - Visual Identification

/**
 * The name shown in the visual identification overlay for debugging.
 *
 * Override this in subclasses to provide custom identification.
 */
@property (nonatomic, readonly, nullable) NSString *_nameForVisualIdentificationOverlay;

#pragma mark - Process Control

/**
 * Immediately terminates the web content process backing this web view.
 *
 * Unlike `_requestWebProcessTermination` (which is advisory and may be ignored),
 * this method directly kills the process. After termination, the tab enters
 * `.notRunning` state and can be restored by reloading.
 *
 * @warning This affects ALL web views sharing the same process. All tabs hosted
 *          in the terminated process will enter `.notRunning` state.
 */
- (void)_killWebContentProcess;

#pragma mark - Page Suspension

/// Suspends (freezes) the page execution.
///
/// Pauses JavaScript execution, timers, animations, and network activity.
/// Memory is preserved — the page can be resumed instantly without reload.
///
/// - Parameter completionHandler: Called with YES if suspension succeeded.
- (void)_suspendPage:(void (^)(BOOL))completionHandler API_AVAILABLE(macos(12.0), ios(15.0));

/// Resumes a previously suspended page.
///
/// Restores JavaScript execution, timers, and network activity.
///
/// - Parameter completionHandler: Called with YES if resume succeeded.
- (void)_resumePage:(void (^)(BOOL))completionHandler API_AVAILABLE(macos(12.0), ios(15.0));

#pragma mark - Scrolling Control (macOS)

/**
 * Whether the web view always bounces vertically regardless of content size.
 */
@property (nonatomic, setter=_setAlwaysBounceVertical:) BOOL _alwaysBounceVertical;

/**
 * Whether the web view always bounces horizontally regardless of content size.
 */
@property (nonatomic, setter=_setAlwaysBounceHorizontal:) BOOL _alwaysBounceHorizontal;

/**
 * The edges for which rubber-band scrolling is enabled.
 *
 * This is an option set that can include .top, .bottom, .left, .right.
 */
@property (nonatomic, setter=_setRubberBandingEnabled:) _WKRectEdge _rubberBandingEnabled;

/**
 * Sets the content offset programmatically.
 *
 * @param x The new X offset, or nil to keep current.
 * @param y The new Y offset, or nil to keep current.
 * @param animated Whether to animate the change.
 */
- (void)_setContentOffsetX:(nullable NSNumber *)x
                         y:(nullable NSNumber *)y
                  animated:(BOOL)animated;

/**
 * Scrolls to the specified edge.
 *
 * @param edge The edge to scroll to.
 * @param animated Whether to animate the scroll.
 */
- (void)_scrollTo:(_WKRectEdge)edge animated:(BOOL)animated;

#pragma mark - JavaScript Evaluation

/**
 * Evaluates JavaScript without synthesizing a user gesture.
 *
 * The public `evaluateJavaScript`/`callAsyncJavaScript` APIs run scripts inside
 * a forced user gesture and then STRIP the window's transient activation when
 * the script finishes (WebCore ScriptController, RemoveTransientActivation).
 * Background/read-only evaluation through those APIs therefore erases the
 * activation a real user click just granted, breaking activation-gated APIs
 * the page may call next (fullscreen, popups, PiP).
 *
 * Use this variant for any evaluation that merely observes the page.
 * Main frame, page content world only.
 */
- (void)_evaluateJavaScriptWithoutUserGesture:(NSString *)javaScriptString
                            completionHandler:(void (^_Nullable)(id _Nullable, NSError *_Nullable))completionHandler
    API_AVAILABLE(macos(10.13));

@end

NS_ASSUME_NONNULL_END
