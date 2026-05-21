/**
 * WKWebViewPrivate+Interaction.h
 * Refrax Browser
 *
 * Private WebKit APIs for user interaction control.
 *
 * This header provides native mechanisms for controlling user interaction
 * with WKWebView content, eliminating the need for JavaScript-based hacks.
 *
 * ## Available Controls
 * - `_ignoresAllEvents`: Block ALL user interactions
 * - `_ignoresNonWheelEvents`: Block everything except scroll wheel
 * - `_ignoresMouseMoveEvents`: Block only mouse move tracking
 *
 * ## Use Cases
 * - Layout mode: Prevent accidental clicks during tab rearrangement
 * - Screenshot capture: Freeze interaction during visual capture
 * - Modal overlays: Disable background web view interaction
 *
 * ## Advantages Over JavaScript
 * - Immediate effect (no async script injection)
 * - Works during page load
 * - No page modification or cleanup required
 * - Cannot be circumvented by page scripts
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

#pragma mark - WKWebView Interaction Control

/**
 * Private WKWebView extensions for user interaction control.
 *
 * These methods provide native, WebKit-level control over user events,
 * bypassing the need for CSS `pointer-events: none` or JavaScript hacks.
 */
@interface WKWebView (WKPrivateInteraction)

#pragma mark - Event Blocking

/**
 * Whether the web view ignores ALL user events.
 *
 * When YES, the web view does not process:
 * - Mouse clicks and drags
 * - Mouse movement
 * - Scroll wheel events
 * - Keyboard input
 * - Touch events (iOS)
 * - Gesture recognizer events
 *
 * The web view becomes completely non-interactive, similar to setting
 * `userInteractionEnabled = NO` on a UIKit view, but with WebKit-specific
 * handling that properly manages internal state.
 *
 * ## Performance
 * Setting this property is a synchronous, immediate operation. Events
 * are blocked at the WKWebView level before reaching the web process,
 * ensuring no side effects from partial event handling.
 *
 * ## Use Cases
 * - Tab rearrangement mode
 * - Screenshot/thumbnail capture
 * - Dragging web view between windows
 * - Modal presentation over web content
 *
 * ## Example
 * @code
 * // Enter layout mode - block all interaction
 * webView._ignoresAllEvents = YES;
 *
 * // ... perform layout operations ...
 *
 * // Exit layout mode - restore interaction
 * webView._ignoresAllEvents = NO;
 * @endcode
 *
 * ## WebKit Implementation
 * Internally, this sets a flag that causes `hitTest:withEvent:` and related
 * methods to return nil/NO, preventing event dispatch to the web content.
 *
 * ## Availability
 * macOS 10.13.4+, iOS 11.3+
 */
@property (nonatomic, setter=_setIgnoresAllEvents:) BOOL _ignoresAllEvents
    API_AVAILABLE(macos(10.13.4), ios(11.3));

/**
 * Whether the web view ignores non-wheel events.
 *
 * When YES, the web view only processes scroll wheel events, ignoring:
 * - Mouse clicks and drags
 * - Mouse movement
 * - Keyboard input
 *
 * This allows users to scroll content while preventing accidental clicks
 * or other interactions. Useful for preview modes where content should
 * be viewable but not interactive.
 *
 * ## Use Cases
 * - Tab preview overlays (allow scroll to preview content)
 * - Read-only mode with scroll
 * - Content inspection without interaction
 *
 * ## Example
 * @code
 * // Enable scroll-only mode
 * webView._ignoresNonWheelEvents = YES;
 *
 * // User can scroll but not click links or interact
 *
 * // Restore full interaction
 * webView._ignoresNonWheelEvents = NO;
 * @endcode
 *
 * ## Availability
 * macOS 10.13.4+
 */
@property (nonatomic, readwrite, setter=_setIgnoresNonWheelEvents:) BOOL _ignoresNonWheelEvents
    API_AVAILABLE(macos(10.13.4));

/**
 * Whether the web view ignores mouse move events.
 *
 * When YES, the web view does not process mouse movement, preventing:
 * - Hover effects (CSS :hover)
 * - mouseover/mouseout events
 * - mousemove event dispatch
 * - Cursor changes based on content
 *
 * Clicks and other interactions still work normally.
 *
 * ## Use Cases
 * - Reduce CPU usage when mouse tracking isn't needed
 * - Prevent hover effects during animations
 * - Stabilize UI during drag operations
 *
 * ## Performance Benefit
 * Mouse move events can fire hundreds of times per second during mouse
 * movement. Disabling them reduces CPU usage and IPC traffic to the
 * web process, especially on pages with complex hover handlers.
 *
 * ## Example
 * @code
 * // Disable hover effects during animation
 * webView._ignoresMouseMoveEvents = YES;
 *
 * [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
 *     // Animate web view
 * } completionHandler:^{
 *     // Re-enable hover effects
 *     webView._ignoresMouseMoveEvents = NO;
 * }];
 * @endcode
 *
 * ## Availability
 * macOS 13.0+
 */
@property (nonatomic, readwrite, setter=_setIgnoresMouseMoveEvents:) BOOL _ignoresMouseMoveEvents
    API_AVAILABLE(macos(13.0));

@end

NS_ASSUME_NONNULL_END
