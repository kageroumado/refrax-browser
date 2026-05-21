/**
 * WKDelegatesPrivate.h
 * Refrax Browser
 *
 * Private WebKit delegate protocols for advanced browser functionality.
 *
 * This header declares private delegate protocols that provide browser-essential
 * functionality not available through public APIs:
 *
 * - `_WKInputDelegate`: Form input session handling and autofill integration
 * - `_WKIconLoadingDelegate`: Native favicon detection and loading
 * - `WKHistoryDelegatePrivate`: Title updates and navigation tracking
 * - `WKUIDelegatePrivate` additions: Context menus, autoplay, fullscreen
 *
 * ## Thread Safety
 * All delegate methods are called on the main thread.
 *
 * ## Source References
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKInputDelegate.h
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKIconLoadingDelegate.h
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKHistoryDelegatePrivate.h
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKUIDelegatePrivate.h
 *
 * Last verified: WebKit trunk (December 2024)
 */

#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Forward Declarations

@class _WKHitTestResult;
@class _WKContextMenuElementInfo;
@class _WKLinkIconParameters;
@class WKNavigationData;
@class SSBLookupResult;
@protocol _WKFocusedElementInfo;
@protocol _WKFormInputSession;

#pragma mark - Display Capture Permission

/**
 * Permission decision for display (screen/window) capture requests.
 *
 * Used by `_webView:requestDisplayCapturePermissionForOrigin:initiatedByFrame:withSystemAudio:decisionHandler:`.
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKUIDelegatePrivate.h
 *
 * ## Availability
 * macOS 13.0+, iOS 16.0+
 */
typedef NS_ENUM(NSInteger, WKDisplayCapturePermissionDecision) {
    /** Deny the request without showing any UI. */
    WKDisplayCapturePermissionDecisionDeny,

    /** Show the system screen picker to select a screen to capture. */
    WKDisplayCapturePermissionDecisionScreenPrompt,

    /** Show the system window picker to select a window to capture. */
    WKDisplayCapturePermissionDecisionWindowPrompt,
} API_AVAILABLE(macos(13.0), ios(16.0));

#pragma mark - Same Document Navigation Type

/**
 * Types of same-document (in-page) navigations.
 *
 * Same-document navigations occur when JavaScript changes the URL without
 * loading a new document. Used by `WKNavigationDelegatePrivate` to report
 * History API and anchor navigations.
 *
 * ## Source
 * WebKit/Source/WebKit/Shared/API/Cocoa/_WKSameDocumentNavigationType.h
 *
 * ## Availability
 * macOS 10.10+, iOS 8.0+
 */
typedef NS_ENUM(NSInteger, _WKSameDocumentNavigationType) {
    /** Anchor/hash navigation (e.g., clicking `<a href="#section">`). */
    _WKSameDocumentNavigationTypeAnchorNavigation,

    /** JavaScript `history.pushState()` call. */
    _WKSameDocumentNavigationTypeSessionStatePush,

    /** JavaScript `history.replaceState()` call. */
    _WKSameDocumentNavigationTypeSessionStateReplace,

    /** Browser back/forward navigation within history state. */
    _WKSameDocumentNavigationTypeSessionStatePop,
} API_AVAILABLE(macos(10.10), ios(8.0));

#pragma mark - Input Type Enumeration

/**
 * Types of input elements that can receive focus.
 *
 * Used by `_WKFocusedElementInfo` to identify the type of input field
 * for autofill and keyboard customization.
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKFocusedElementInfo.h
 */
typedef NS_ENUM(NSInteger, WKInputType) {
    /** No input type (unfocused). */
    WKInputTypeNone,

    /** Content editable element (`contenteditable="true"`). */
    WKInputTypeContentEditable,

    /** Standard text input (`<input type="text">`). */
    WKInputTypeText,

    /** Password input (`<input type="password">`). */
    WKInputTypePassword,

    /** Textarea (`<textarea>`). */
    WKInputTypeTextArea,

    /** Search input (`<input type="search">`). */
    WKInputTypeSearch,

    /** Email input (`<input type="email">`). */
    WKInputTypeEmail,

    /** URL input (`<input type="url">`). */
    WKInputTypeURL,

    /** Phone input (`<input type="tel">`). */
    WKInputTypePhone,

    /** Number input (`<input type="number">`). */
    WKInputTypeNumber,

    /** Number pad input (iOS-specific behavior). */
    WKInputTypeNumberPad,

    /** Date input (`<input type="date">`). */
    WKInputTypeDate,

    /** DateTime input (`<input type="datetime">`). */
    WKInputTypeDateTime,

    /** DateTime-local input (`<input type="datetime-local">`). */
    WKInputTypeDateTimeLocal,

    /** Month input (`<input type="month">`). */
    WKInputTypeMonth,

    /** Week input (`<input type="week">`). */
    WKInputTypeWeek,

    /** Time input (`<input type="time">`). */
    WKInputTypeTime,

    /** Select dropdown (`<select>`). */
    WKInputTypeSelect,

    /** Color picker (`<input type="color">`). */
    WKInputTypeColor,

    /** Drawing input (iOS-specific). */
    WKInputTypeDrawing,
};

#pragma mark - Link Icon Type

/**
 * Type of favicon/icon linked from a web page.
 *
 * Web pages can specify multiple icon types via `<link>` elements.
 * This enum identifies the type for appropriate handling.
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKLinkIconParameters.h
 *
 * ## Availability
 * macOS 10.12.4+, iOS 10.3+
 */
typedef NS_ENUM(NSInteger, WKLinkIconType) {
    /**
     * Standard favicon (typically 16x16 to 48x48).
     *
     * Specified as:
     * - `<link rel="icon" href="favicon.ico">`
     * - `<link rel="shortcut icon" href="favicon.png">`
     */
    WKLinkIconTypeFavicon,

    /**
     * Apple Touch Icon (for iOS home screen).
     *
     * Higher resolution icon for iOS devices:
     * `<link rel="apple-touch-icon" href="icon.png">`
     *
     * iOS will apply visual effects (rounded corners, gloss).
     */
    WKLinkIconTypeTouchIcon,

    /**
     * Precomposed Apple Touch Icon (no effects applied).
     *
     * `<link rel="apple-touch-icon-precomposed" href="icon.png">`
     *
     * iOS won't add visual effects to this icon.
     */
    WKLinkIconTypeTouchPrecomposedIcon,
} API_AVAILABLE(macos(10.12.4), ios(10.3));

#pragma mark - _WKFocusedElementInfo Protocol

/**
 * Information about a focused form element.
 *
 * Provides details about an input element when it receives focus,
 * enabling autofill integration and custom input handling.
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKFocusedElementInfo.h
 */
@protocol _WKFocusedElementInfo <NSObject>

/** The type of input element that was focused. */
@property (nonatomic, readonly) WKInputType type;

/** The current value of the input element (may be nil). */
@property (nonatomic, readonly, copy, nullable) NSString *value;

/** The placeholder text of the input element (may be nil). */
@property (nonatomic, readonly, copy, nullable) NSString *placeholder;

/** The label text associated with the input from `<label>` element (may be nil). */
@property (nonatomic, readonly, copy, nullable) NSString *label;

/**
 * Whether the focus was initiated by user interaction.
 *
 * YES if the user clicked/tapped the element.
 * NO if focus was set programmatically (e.g., via JavaScript `focus()`).
 */
@property (nonatomic, readonly, getter=isUserInitiated) BOOL userInitiated;

/**
 * Additional user object for custom data.
 *
 * ## Availability
 * macOS 10.13.4+, iOS 11.3+
 */
@property (nonatomic, readonly, nullable) NSObject<NSSecureCoding> *userObject
    API_AVAILABLE(macos(10.13.4), ios(11.3));

/**
 * The frame containing the focused element.
 *
 * ## Availability
 * macOS 26.0+
 */
@property (nonatomic, readonly, copy, nullable) WKFrameInfo *frame
    API_AVAILABLE(macos(26.0));

@end

#pragma mark - _WKFormInputSession Protocol

/**
 * Represents an active form input session.
 *
 * A form input session is created when a user focuses on an input element.
 * Use this to customize the input experience or track form state.
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKFormInputSession.h
 */
@protocol _WKFormInputSession <NSObject>

/** Whether the session is still valid (the element is still focused). */
@property (nonatomic, readonly, getter=isValid) BOOL valid;

/** Custom user object associated with the session. */
@property (nonatomic, readonly, nullable) NSObject<NSSecureCoding> *userObject;

/**
 * Information about the focused element.
 *
 * ## Availability
 * macOS 10.12+, iOS 10.0+
 */
@property (nonatomic, readonly, nullable) id<_WKFocusedElementInfo> focusedElementInfo
    API_AVAILABLE(macos(10.12), ios(10.0));

@end

#pragma mark - _WKInputDelegate Protocol

/**
 * Delegate for handling form input events.
 *
 * Implement this protocol to receive notifications about form input sessions
 * and to customize form submission behavior. Essential for:
 * - Password manager integration
 * - Custom autofill
 * - Form validation
 *
 * ## Setup
 * @code
 * [webView _setInputDelegate:self];
 * @endcode
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKInputDelegate.h
 */
@protocol _WKInputDelegate <NSObject>
@optional

/**
 * Called when an input session starts (element receives focus).
 *
 * Use this to detect password field focus for autofill prompts.
 *
 * @param webView The web view containing the input element.
 * @param inputSession The input session that started.
 *
 * ## Example
 * @code
 * - (void)_webView:(WKWebView *)webView didStartInputSession:(id<_WKFormInputSession>)inputSession {
 *     if (inputSession.focusedElementInfo.type == WKInputTypePassword) {
 *         [self showAutofillSuggestions];
 *     }
 * }
 * @endcode
 */
- (void)_webView:(WKWebView *)webView
    didStartInputSession:(id<_WKFormInputSession>)inputSession;

/**
 * Called when a form is about to be submitted.
 *
 * This is the opportunity to:
 * - Save form data (for autofill)
 * - Store credentials (for password management)
 * - Validate form data
 *
 * @param webView The web view containing the form.
 * @param values Dictionary of form field names to values.
 * @param userObject Custom user object if set.
 * @param submissionHandler You MUST call this handler to allow form submission.
 *
 * ## Important
 * You must call `submissionHandler()` to allow the form to submit.
 * Failing to call it will block form submission indefinitely.
 *
 * ## Example
 * @code
 * - (void)_webView:(WKWebView *)webView
 *     willSubmitFormValues:(NSDictionary *)values
 *               userObject:(NSObject<NSSecureCoding> *)userObject
 *        submissionHandler:(void (^)(void))submissionHandler {
 *
 *     // Check for credentials to save
 *     NSString *username = values[@"username"];
 *     NSString *password = values[@"password"];
 *
 *     if (username && password) {
 *         [self offerToSaveCredentials:username password:password forURL:webView.URL];
 *     }
 *
 *     // Must call to allow form submission
 *     submissionHandler();
 * }
 * @endcode
 */
- (void)_webView:(WKWebView *)webView
    willSubmitFormValues:(NSDictionary *)values
              userObject:(nullable NSObject<NSSecureCoding> *)userObject
       submissionHandler:(void (^)(void))submissionHandler;

@end

#pragma mark - WKWebView Input Delegate Extension

/**
 * Private methods for managing the input delegate.
 */
@interface WKWebView (WKInputDelegatePrivate)

/**
 * Sets the input delegate for form handling.
 *
 * @param delegate The delegate to receive input events, or nil to remove.
 */
- (void)_setInputDelegate:(nullable id<_WKInputDelegate>)delegate;

/**
 * Gets the current input delegate.
 *
 * @return The current input delegate, or nil if not set.
 */
- (nullable id<_WKInputDelegate>)_inputDelegate;

@end

#pragma mark - _WKLinkIconParameters

/**
 * Contains information about a favicon or touch icon from a web page.
 *
 * Passed to `_WKIconLoadingDelegate` when WebKit discovers icon link elements.
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKLinkIconParameters.h
 *
 * ## Availability
 * macOS 10.12.4+, iOS 10.3+
 */
API_AVAILABLE(macos(10.12.4), ios(10.3))
@interface _WKLinkIconParameters : NSObject

/** The resolved URL of the icon from the `href` attribute. */
@property (nonatomic, readonly, copy) NSURL *url;

/** The type of icon (favicon, touch icon, etc.). */
@property (nonatomic, readonly) WKLinkIconType iconType;

/**
 * The MIME type of the icon, if specified.
 *
 * Example values: "image/png", "image/x-icon", "image/svg+xml"
 * May be nil if not specified in the link element.
 */
@property (nonatomic, readonly, copy, nullable) NSString *mimeType;

/**
 * The size hint for the icon from the `sizes` attribute.
 *
 * For `<link rel="icon" sizes="32x32">`, this would be @32.
 * Assumes square icons. May be nil if not specified.
 */
@property (nonatomic, readonly, copy, nullable) NSNumber *size;

/**
 * Additional attributes from the link element.
 *
 * Contains all attributes as key-value pairs.
 *
 * ## Availability
 * macOS 10.14+, iOS 12.0+
 */
@property (nonatomic, readonly, copy, nullable) NSDictionary *attributes
    API_AVAILABLE(macos(10.14), ios(12.0));

@end

#pragma mark - _WKIconLoadingDelegate Protocol

/**
 * Delegate for receiving native favicon/icon loading notifications.
 *
 * More efficient than JavaScript-based favicon detection because:
 * - WebKit notifies you directly when link elements are parsed
 * - No need to inject scripts or poll for changes
 * - Works even when JavaScript is disabled
 *
 * ## Setup
 * @code
 * [webView _setIconLoadingDelegate:self];
 * @endcode
 *
 * ## Callback Pattern
 * Uses a double-completion-handler pattern:
 * 1. You receive icon parameters and a completion handler
 * 2. You call the completion handler with YOUR callback function
 * 3. WebKit loads the icon and calls your callback with the data
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKIconLoadingDelegate.h
 *
 * ## Availability
 * macOS 10.12.4+, iOS 10.3+
 */
@protocol _WKIconLoadingDelegate <NSObject>
@optional

/**
 * Called when WebKit discovers an icon link in a web page.
 *
 * @param webView The web view that found the icon.
 * @param parameters Information about the icon (URL, type, size).
 * @param completionHandler Call with a callback to receive icon data,
 *                          or with an empty callback `^(NSData *data) { }` to skip.
 *
 * ## Example Implementation
 * @code
 * - (void)webView:(WKWebView *)webView
 *     shouldLoadIconWithParameters:(_WKLinkIconParameters *)parameters
 *                completionHandler:(void (^)(void (^)(NSData *)))completionHandler {
 *
 *     // Only load standard favicons, skip touch icons
 *     if (parameters.iconType != WKLinkIconTypeFavicon) {
 *         completionHandler(^(NSData *data) { }); // Empty callback - skip
 *         return;
 *     }
 *
 *     // Prefer larger icons
 *     NSInteger preferredSize = parameters.size.integerValue;
 *     if (preferredSize > 0 && preferredSize < 32) {
 *         completionHandler(^(NSData *data) { }); // Too small - skip
 *         return;
 *     }
 *
 *     // Provide callback to receive loaded icon data
 *     completionHandler(^(NSData *iconData) {
 *         if (iconData) {
 *             NSImage *icon = [[NSImage alloc] initWithData:iconData];
 *             [self updateFavicon:icon forURL:webView.URL];
 *         }
 *     });
 * }
 * @endcode
 */
- (void)webView:(WKWebView *)webView
    shouldLoadIconWithParameters:(_WKLinkIconParameters *)parameters
               completionHandler:(void (^)(void (^)(NSData * _Nullable)))completionHandler;

@end

#pragma mark - WKNavigationData

/**
 * Contains information about a navigation for history tracking.
 *
 * Provided by `WKHistoryDelegatePrivate` callbacks.
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKNavigationData.h
 *
 * ## Availability
 * macOS 10.10+, iOS 8.0+
 */
API_AVAILABLE(macos(10.10), ios(8.0))
@interface WKNavigationData : NSObject

/** The title of the navigated page (from `<title>` element). */
@property (nonatomic, readonly, copy, nullable) NSString *title;

/** The original request that initiated the navigation. */
@property (nonatomic, readonly, copy, nullable) NSURLRequest *originalRequest;

/** The final destination URL after any redirects. */
@property (nonatomic, readonly, copy, nullable) NSURL *destinationURL;

/** The HTTP response from the server. */
@property (nonatomic, readonly, copy, nullable) NSURLResponse *response;

@end

#pragma mark - WKHistoryDelegatePrivate Protocol

/**
 * Private delegate for tracking navigation history events.
 *
 * Provides callbacks not available through public `WKNavigationDelegate`:
 * - Title updates after initial page load (JavaScript changes)
 * - Client-side redirect tracking
 * - Server-side redirect tracking
 * - Safe Browsing integration
 *
 * ## Setup
 * @code
 * webView._historyDelegate = self;
 * // or
 * [webView _setHistoryDelegate:self];
 * @endcode
 *
 * ## Why This Exists
 * The public `WKNavigationDelegate` only provides the title at page load
 * completion. Modern web apps frequently update titles via JavaScript
 * (e.g., email clients showing "Inbox (3)" → "Inbox (5)").
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKHistoryDelegatePrivate.h
 *
 * ## Availability
 * macOS 10.10+, iOS 8.0+
 */
@protocol WKHistoryDelegatePrivate <NSObject>
@optional

/**
 * Called when a navigation completes with full navigation data.
 *
 * Use this to add entries to your browser's history.
 *
 * @param webView The web view that navigated.
 * @param navigationData Details about the navigation.
 */
- (void)_webView:(WKWebView *)webView
    didNavigateWithNavigationData:(WKNavigationData *)navigationData;

/**
 * Called when a client-side redirect occurs.
 *
 * Client-side redirects are caused by:
 * - JavaScript `location.href = "..."`
 * - `<meta http-equiv="refresh">`
 * - History API navigation
 *
 * @param webView The web view that redirected.
 * @param sourceURL The URL before the redirect.
 * @param destinationURL The URL after the redirect.
 */
- (void)_webView:(WKWebView *)webView
    didPerformClientRedirectFromURL:(NSURL *)sourceURL
                              toURL:(NSURL *)destinationURL;

/**
 * Called when a server-side redirect occurs.
 *
 * Server-side redirects are HTTP 301, 302, 303, 307, or 308 responses.
 *
 * @param webView The web view that redirected.
 * @param sourceURL The URL before the redirect.
 * @param destinationURL The URL after the redirect.
 */
- (void)_webView:(WKWebView *)webView
    didPerformServerRedirectFromURL:(NSURL *)sourceURL
                              toURL:(NSURL *)destinationURL;

/**
 * Called when the page title changes after initial load.
 *
 * ## Important
 * This is called for title changes AFTER initial page load, typically
 * via JavaScript `document.title = "..."`. The initial title is available
 * through `WKNavigationDelegate` and `webView.title`.
 *
 * ## Use Case
 * Update history entries when SPAs change their title:
 * - Email clients: "Inbox (3)" → "Inbox (5)"
 * - Chat apps: Show new message previews
 * - Music players: Show current track
 *
 * @param webView The web view whose title changed.
 * @param title The new title.
 * @param URL The URL of the page.
 */
- (void)_webView:(WKWebView *)webView
    didUpdateHistoryTitle:(NSString *)title
                   forURL:(NSURL *)URL;

/**
 * Called when Safe Browsing completes a lookup for a URL.
 *
 * @param webView The web view that navigated.
 * @param result The Safe Browsing lookup result.
 * @param URL The URL that was checked.
 *
 * ## Note
 * Requires SafariSafeBrowsing.framework to be linked.
 */
- (void)_webView:(WKWebView *)webView
    didReceiveSafeBrowsingResult:(SSBLookupResult *)result
                          forURL:(NSURL *)URL;

@end

#pragma mark - WKWebView History Delegate Extension

/**
 * Private property for the history delegate.
 */
@interface WKWebView (WKHistoryDelegatePrivate)

/**
 * The history delegate for navigation history events.
 *
 * Set this to receive callbacks for title changes, redirects, and
 * Safe Browsing results.
 */
@property (nonatomic, weak, setter=_setHistoryDelegate:, nullable)
    id<WKHistoryDelegatePrivate> _historyDelegate;

/**
 * The icon loading delegate for favicon notifications.
 *
 * Set this to receive callbacks when the page declares favicon links.
 */
@property (nonatomic, weak, setter=_setIconLoadingDelegate:, nullable)
    id<_WKIconLoadingDelegate> _iconLoadingDelegate;

@end

NS_ASSUME_NONNULL_END
