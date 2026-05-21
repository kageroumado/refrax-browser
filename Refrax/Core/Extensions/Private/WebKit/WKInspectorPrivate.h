/**
 * WKInspectorPrivate.h
 * Refrax Browser
 *
 * Private WebKit APIs for Web Inspector control.
 *
 * This header provides programmatic access to the Web Inspector,
 * enabling developer tools functionality in the browser.
 *
 * ## Prerequisites
 * Web Inspector must be enabled via WKPreferences before use:
 * @code
 * webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
 * @endcode
 *
 * ## Thread Safety
 * All APIs must be called on the main thread.
 *
 * ## Source Reference
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKInspector.h
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebViewPrivate.h
 *
 * Last verified: WebKit trunk (December 2024)
 */

#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - _WKInspector

/**
 * The Web Inspector controller for a WKWebView.
 *
 * Provides programmatic control over the Web Inspector, allowing:
 * - Show/hide inspector window
 * - Navigate to specific panels (Console, Elements, Network)
 * - Toggle profiling and element selection
 *
 * ## Access
 * Get the inspector via `WKWebView._inspector`:
 * @code
 * _WKInspector *inspector = webView._inspector;
 * [inspector show];
 * @endcode
 *
 * ## Lifecycle
 * The inspector is lazily created on first access to `_inspector`.
 * It remains associated with the web view until the web view is closed.
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKInspector.h
 *
 * ## Availability
 * macOS 10.14.4+, iOS 12.2+
 */
@class _WKInspector;

#pragma mark - _WKInspectorDelegate

/**
 * Delegate protocol for Web Inspector events.
 *
 * Implement this protocol to receive notifications about inspector state changes
 * and to handle inspector-initiated actions like opening URLs.
 */
@protocol _WKInspectorDelegate <NSObject>
@optional

/**
 * Called when the inspector requests to open a URL externally.
 *
 * This occurs when clicking links in the inspector that should open in a new window
 * (e.g., documentation links, resource URLs).
 *
 * @param inspector The inspector making the request.
 * @param url The URL to open externally.
 */
- (void)inspector:(_WKInspector *)inspector openURLExternally:(NSURL *)url;

/**
 * Called when the inspector frontend has finished loading.
 *
 * @param inspector The inspector that finished loading.
 */
- (void)inspectorFrontendLoaded:(_WKInspector *)inspector;

@end

#pragma mark - _WKInspector

API_AVAILABLE(macos(10.14.4), ios(12.2))
@interface _WKInspector : NSObject

- (instancetype)init NS_UNAVAILABLE;

#pragma mark - Delegate

/**
 * The delegate for inspector events.
 *
 * Set this to receive notifications about visibility changes and URL opening requests.
 *
 * ## Availability
 * macOS 12.0+, iOS 15.0+
 */
@property (nonatomic, weak, nullable) id<_WKInspectorDelegate> delegate
    API_AVAILABLE(macos(12.0), ios(15.0));

#pragma mark - Associated Web View

/**
 * The web view this inspector is associated with.
 *
 * @return The WKWebView being inspected.
 */
@property (nonatomic, readonly) WKWebView *webView;

#pragma mark - State Properties

/**
 * Whether the Web Inspector is connected to the web view.
 *
 * The inspector becomes connected when it's first shown and remains
 * connected until the web view is closed.
 *
 * @return YES if connected, NO otherwise.
 */
@property (nonatomic, readonly) BOOL isConnected;

/**
 * Whether the Web Inspector window is currently visible.
 *
 * @return YES if the inspector is shown, NO otherwise.
 */
@property (nonatomic, readonly) BOOL isVisible;

/**
 * Whether the Web Inspector window is the frontmost window.
 *
 * @return YES if the inspector is frontmost, NO otherwise.
 */
@property (nonatomic, readonly) BOOL isFront;

/**
 * Whether Timeline profiling is currently active.
 *
 * @return YES if recording performance data, NO otherwise.
 */
@property (nonatomic, readonly) BOOL isProfilingPage;

/**
 * Whether element selection mode is active.
 *
 * When active, hovering over elements in the web view highlights them
 * and clicking selects them in the Elements panel.
 *
 * @return YES if selection mode is active, NO otherwise.
 */
@property (nonatomic, readonly) BOOL isElementSelectionActive;

#pragma mark - Connection

/**
 * Connects the inspector to the web view.
 *
 * This is typically called automatically when the inspector is shown.
 */
- (void)connect;

#pragma mark - Show/Hide

/**
 * Shows the Web Inspector window.
 *
 * Opens the inspector in its default state (usually the Elements panel).
 * If already visible, brings the inspector window to front.
 *
 * ## Example
 * @code
 * // Show inspector when user presses Cmd+Option+I
 * - (void)toggleInspector:(id)sender {
 *     _WKInspector *inspector = webView._inspector;
 *     if (inspector.isVisible) {
 *         [inspector close];
 *     } else {
 *         [inspector show];
 *     }
 * }
 * @endcode
 */
- (void)show;

/**
 * Shows the Web Inspector focused on a specific frame's resources.
 *
 * @param frame The frame to inspect (pass main frame for the main document).
 *
 * ## Note
 * The frame parameter is typically obtained from navigation events or
 * WKFrameInfo objects.
 */
- (void)showMainResourceForFrame:(id)frame;

/**
 * Hides the Web Inspector window.
 *
 * Hides the inspector but maintains its connection to the web view.
 * State is preserved for when the inspector is shown again.
 *
 * ## Note
 * The actual WebKit API uses `hide`, but we also provide a `close` alias
 * for semantic clarity in browser contexts.
 */
- (void)hide;

/**
 * Closes the Web Inspector window (alias for hide).
 *
 * Provided for semantic clarity - functionally equivalent to `hide`.
 */
- (void)close;

#pragma mark - Attachment (Docking)

/**
 * Attaches the Web Inspector to the web view (docks it).
 *
 * When attached, the inspector shares the window with the web view,
 * typically at the bottom or side of the view.
 *
 * ## Note
 * The attachment side is determined by WebKit preferences or the last used side.
 * Use UserDefaults to control the initial attachment position.
 *
 * ## Availability
 * macOS 10.14.4+, iOS 12.2+
 */
- (void)attach API_AVAILABLE(macos(10.14.4), ios(12.2));

/**
 * Detaches the Web Inspector from the web view (undocks it).
 *
 * Opens the inspector in a separate floating window that can be
 * positioned independently from the browser window.
 *
 * ## Availability
 * macOS 10.14.4+, iOS 12.2+
 */
- (void)detach API_AVAILABLE(macos(10.14.4), ios(12.2));

#pragma mark - Panel Navigation

/**
 * Shows the Console panel.
 *
 * Opens the inspector (if not already visible) and switches to the
 * Console panel for viewing logs and executing JavaScript.
 *
 * ## Example
 * @code
 * // Show console when user presses Cmd+Option+C
 * - (void)showConsole:(id)sender {
 *     [webView._inspector showConsole];
 * }
 * @endcode
 */
- (void)showConsole;

/**
 * Shows the Resources (Sources) panel.
 *
 * Opens the inspector and switches to the panel showing page resources,
 * scripts, stylesheets, and the debugger.
 */
- (void)showResources;

#pragma mark - Profiling

/**
 * Toggles Timeline (performance) profiling.
 *
 * When enabled, records performance metrics including:
 * - JavaScript execution time
 * - Layout and rendering
 * - Network requests
 * - Memory usage
 *
 * ## Example
 * @code
 * // Start/stop profiling
 * - (void)toggleProfiling:(id)sender {
 *     [webView._inspector togglePageProfiling];
 *
 *     // Update UI
 *     self.profilingMenuItem.state = webView._inspector.isProfilingPage
 *         ? NSControlStateValueOn
 *         : NSControlStateValueOff;
 * }
 * @endcode
 */
- (void)togglePageProfiling;

#pragma mark - Element Selection

/**
 * Toggles element selection mode.
 *
 * When active:
 * - Moving the mouse over the web view highlights elements
 * - Clicking an element selects it in the Elements panel
 * - The inspector shows element details
 *
 * ## Example
 * @code
 * // Enable inspect element mode
 * - (void)inspectElement:(id)sender {
 *     _WKInspector *inspector = webView._inspector;
 *
 *     // Show inspector if hidden
 *     if (!inspector.isVisible) {
 *         [inspector show];
 *     }
 *
 *     // Enable element selection if not already active
 *     if (!inspector.isElementSelectionActive) {
 *         [inspector toggleElementSelection];
 *     }
 * }
 * @endcode
 */
- (void)toggleElementSelection;

#pragma mark - Console

/**
 * Prints an error message to the Web Inspector console.
 *
 * This allows the application to log errors that appear in the inspector's
 * console panel alongside JavaScript errors.
 *
 * @param error The error message to print.
 *
 * ## Example
 * @code
 * [webView._inspector printErrorToConsole:@"Failed to load resource"];
 * @endcode
 */
- (void)printErrorToConsole:(NSString *)error;

@end

#pragma mark - WKWebView Inspector Extension

/**
 * Private WKWebView extensions for Web Inspector access.
 */
@interface WKWebView (WKPrivateInspector)

/**
 * The Web Inspector instance for this web view.
 *
 * The inspector is lazily created on first access. Returns the same
 * instance on subsequent calls.
 *
 * ## Prerequisite
 * Developer extras must be enabled in WKPreferences:
 * @code
 * webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
 * @endcode
 *
 * ## Example
 * @code
 * // Show Web Inspector
 * [webView._inspector show];
 *
 * // Open Console directly
 * [webView._inspector showConsole];
 *
 * // Enable element inspection
 * [webView._inspector toggleElementSelection];
 * @endcode
 *
 * ## Availability
 * macOS 10.14.4+, iOS 12.2+
 */
@property (nonatomic, readonly, nullable) _WKInspector *_inspector
    API_AVAILABLE(macos(10.14.4), ios(12.2));

@end

#pragma mark - WKUIDelegatePrivate Inspector Methods

/**
 * Private UI delegate methods for Web Inspector events.
 *
 * Implement these to receive notifications about inspector state changes.
 */
@protocol WKUIDelegatePrivate_Inspector <NSObject>
@optional

/**
 * Called when a local Web Inspector is attached to the web view.
 *
 * @param webView The web view the inspector is attached to.
 * @param inspector The inspector instance.
 *
 * ## Availability
 * macOS 12.0+, iOS 15.0+
 */
- (void)_webView:(WKWebView *)webView
    didAttachLocalInspector:(_WKInspector *)inspector
    API_AVAILABLE(macos(12.0), ios(15.0));

/**
 * Called before a local Web Inspector is closed.
 *
 * @param webView The web view the inspector is attached to.
 * @param inspector The inspector instance being closed.
 *
 * ## Availability
 * macOS 12.0+, iOS 15.0+
 */
- (void)_webView:(WKWebView *)webView
    willCloseLocalInspector:(_WKInspector *)inspector
    API_AVAILABLE(macos(12.0), ios(15.0));

@end

NS_ASSUME_NONNULL_END
