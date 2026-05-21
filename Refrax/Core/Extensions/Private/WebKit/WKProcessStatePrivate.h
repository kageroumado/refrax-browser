/**
 * WKProcessStatePrivate.h
 * Refrax Browser
 *
 * Private WebKit APIs for web process lifecycle monitoring.
 *
 * This header provides APIs for tracking the state of the web process
 * backing a WKWebView, enabling:
 * - Tab state indicators (running, suspended, crashed)
 * - Memory management decisions
 * - Crash recovery UI
 *
 * ## Process States
 * Web processes can be in one of four states:
 * - `NotRunning`: Process terminated, content discarded
 * - `Foreground`: Active with full resources
 * - `Background`: Running but deprioritized
 * - `Suspended`: Frozen, not executing code
 *
 * ## KVO Compliance
 * `_webProcessState` is KVO-compliant, but WebKit only sends notifications
 * when observers are registered. Without observers, state changes are silent.
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

#pragma mark - Web Process State

/**
 * Web process lifecycle state for resource monitoring.
 *
 * This enum represents the current state of the web process associated
 * with a WKWebView. Essential for:
 * - Showing visual indicators for unloaded/suspended tabs
 * - Understanding which tabs are consuming resources
 * - Implementing tab discarding/restoration UI
 *
 * ## State Transitions
 * @code
 * NotRunning ──────────────────────────► Foreground
 *     ▲                                      │
 *     │                                      │ (tab becomes inactive)
 *     │ (process crash/termination)          ▼
 *     │                               Background
 *     │                                      │
 *     │ (memory pressure)                    │ (memory pressure)
 *     └──────────────────────────────── Suspended
 * @endcode
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebViewPrivate.h
 *
 * ## Availability
 * macOS 15.4+, iOS 18.4+, visionOS 2.4+
 */
typedef NS_ENUM(NSInteger, _WKWebProcessState) {
    /**
     * The web process is not running.
     *
     * Content has been discarded from memory. Common causes:
     * - System terminated process due to memory pressure
     * - User manually discarded the tab
     * - Process crashed
     *
     * ## Recovery
     * The tab can be restored by reloading the URL. Most browsers show
     * a "Tab suspended" or "Reload to view" indicator in this state.
     *
     * ## Example
     * @code
     * if (webView._webProcessState == _WKWebProcessStateNotRunning) {
     *     [self showSuspendedTabIndicator];
     * }
     * @endcode
     */
    _WKWebProcessStateNotRunning,

    /**
     * The web process is running in the foreground.
     *
     * This is the normal state for the active tab. The process has:
     * - Full CPU priority
     * - Full memory allocation
     * - Active timer scheduling
     * - Network priority
     */
    _WKWebProcessStateForeground,

    /**
     * The web process is running in the background.
     *
     * The process is alive but has reduced priority:
     * - Lower CPU scheduling priority
     * - May have throttled timers
     * - Reduced network priority
     *
     * Background tabs enter this state when not visible.
     */
    _WKWebProcessStateBackground,

    /**
     * The web process is suspended (frozen).
     *
     * The process is frozen and not executing any code:
     * - No JavaScript execution
     * - No network activity
     * - Memory is preserved
     * - Can resume instantly
     *
     * This is more common on iOS when the app is backgrounded.
     * On macOS, this occurs under severe memory pressure.
     */
    _WKWebProcessStateSuspended,
} API_AVAILABLE(macos(15.4), ios(18.4), visionos(2.4));

#pragma mark - Process Termination Reason

/**
 * Reason for web content process termination.
 *
 * Used with `WKNavigationDelegatePrivate` to determine why a web content
 * process ended. This allows differentiated handling of crashes vs. OOM
 * vs. intentional termination.
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKNavigationDelegatePrivate.h
 *
 * ## Usage
 * @code
 * - (void)_webView:(WKWebView *)webView
 *     webContentProcessDidTerminateWithReason:(_WKProcessTerminationReason)reason {
 *     switch (reason) {
 *     case _WKProcessTerminationReasonExceededMemoryLimit:
 *         // Tab used too much memory - auto-reload may succeed
 *         [self handleOOMForWebView:webView];
 *         break;
 *     case _WKProcessTerminationReasonCrash:
 *         // Unexpected crash - notify user and auto-reload
 *         [self handleCrashForWebView:webView];
 *         break;
 *     case _WKProcessTerminationReasonRequestedByClient:
 *         // Intentional termination - no action needed
 *         break;
 *     default:
 *         break;
 *     }
 * }
 * @endcode
 *
 * ## Availability
 * macOS 10.14+
 */
typedef NS_ENUM(NSInteger, _WKProcessTerminationReason) {
    /**
     * Process exceeded its memory limit.
     *
     * Common cause: Memory leak in web page JavaScript or excessive DOM.
     * The system terminated the process to prevent overall system instability.
     *
     * Recovery: Auto-reload usually succeeds, but page may crash again
     * if it has a memory leak. Consider tracking OOM frequency per domain.
     */
    _WKProcessTerminationReasonExceededMemoryLimit = 0,

    /**
     * Process exceeded its CPU time limit.
     *
     * Common cause: Infinite loop, very expensive computation, or crypto mining.
     * WebKit enforces CPU limits to prevent runaway pages from consuming resources.
     *
     * Recovery: May succeed but consider warning user. Repeated CPU limit
     * violations likely indicate problematic site.
     */
    _WKProcessTerminationReasonExceededCPULimit = 1,

    /**
     * Client explicitly requested termination.
     *
     * Common cause: Tab was closed, session evicted, or app terminated.
     * This is an intentional termination initiated by the browser.
     *
     * Recovery: Not applicable - intentional termination.
     */
    _WKProcessTerminationReasonRequestedByClient = 2,

    /**
     * Process crashed unexpectedly.
     *
     * Common cause: WebKit bug, malformed content, hardware issue,
     * or illegal instruction. This is an uncontrolled termination.
     *
     * Recovery: Auto-reload usually succeeds. Log for diagnostics.
     */
    _WKProcessTerminationReasonCrash = 3,

    /**
     * Too many crashes in shared process.
     *
     * Common cause: A problematic site in a process that serves multiple
     * tabs caused repeated crashes, exceeding the threshold.
     *
     * Recovery: Reload in new process via `_WKNavigationActionPolicyAllowInNewProcess`.
     * Consider isolating this site in its own process.
     *
     * ## Availability
     * macOS 15.2+
     */
    _WKProcessTerminationReasonExceededSharedProcessCrashLimit API_AVAILABLE(macos(15.2)) = 4,
} API_AVAILABLE(macos(10.14));

#pragma mark - WKWebView Process State Extension

/**
 * Private WKWebView extensions for process state monitoring.
 */
@interface WKWebView (WKPrivateProcessState)

/**
 * The current state of the web process.
 *
 * Use this to track whether a tab is loaded, suspended, or crashed.
 *
 * ## KVO Compliance
 * This property is KVO-compliant. Register an observer to receive
 * state change notifications:
 *
 * @code
 * [webView addObserver:self
 *           forKeyPath:@"_webProcessState"
 *              options:NSKeyValueObservingOptionNew
 *              context:nil];
 * @endcode
 *
 * ## Important
 * WebKit only sends KVO notifications when observers are registered.
 * If no observers exist, state changes are not broadcast. This is an
 * optimization to avoid unnecessary IPC when no one is listening.
 *
 * ## Usage
 * @code
 * switch (webView._webProcessState) {
 *     case _WKWebProcessStateNotRunning:
 *         [self showSuspendedIndicator];
 *         break;
 *     case _WKWebProcessStateForeground:
 *         [self showActiveIndicator];
 *         break;
 *     case _WKWebProcessStateBackground:
 *         [self showBackgroundIndicator];
 *         break;
 *     case _WKWebProcessStateSuspended:
 *         [self showSuspendedIndicator];
 *         break;
 * }
 * @endcode
 *
 * ## Availability
 * macOS 15.4+, iOS 18.4+, visionOS 2.4+
 */
@property (nonatomic, readonly) _WKWebProcessState _webProcessState
    API_AVAILABLE(macos(15.4), ios(18.4), visionos(2.4));

@end

#pragma mark - WKNavigationDelegatePrivate Protocol

/**
 * Private navigation delegate protocol for process lifecycle callbacks.
 *
 * These methods provide more detailed information about process termination
 * and responsiveness than the public `WKNavigationDelegate`.
 *
 * ## Implementation
 * Implement these methods on your `WKNavigationDelegate` object. WebKit will
 * call them via dynamic dispatch if they're present.
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKNavigationDelegatePrivate.h
 */
@protocol WKNavigationDelegatePrivate <WKNavigationDelegate>
@optional

/**
 * Called when the web content process terminates with a specific reason.
 *
 * This provides more detail than the public `webViewWebContentProcessDidTerminate:`
 * by including the termination reason.
 *
 * @param webView The web view whose process terminated.
 * @param reason The reason for termination (OOM, CPU limit, crash, etc.).
 */
- (void)_webView:(WKWebView *)webView
    webContentProcessDidTerminateWithReason:(_WKProcessTerminationReason)reason;

/**
 * Called when the web process becomes unresponsive.
 *
 * A web process is considered unresponsive when it fails to respond to
 * IPC messages within a timeout period (typically 3 seconds).
 *
 * @param webView The web view whose process became unresponsive.
 */
- (void)_webViewWebProcessDidBecomeUnresponsive:(WKWebView *)webView;

/**
 * Called when an unresponsive web process becomes responsive again.
 *
 * @param webView The web view whose process became responsive.
 */
- (void)_webViewWebProcessDidBecomeResponsive:(WKWebView *)webView;

/**
 * Legacy callback for process crashes (deprecated in favor of reason-based callback).
 *
 * @param webView The web view whose process crashed.
 */
- (void)_webViewWebProcessDidCrash:(WKWebView *)webView;

@end

NS_ASSUME_NONNULL_END
