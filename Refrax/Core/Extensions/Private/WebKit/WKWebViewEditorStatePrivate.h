/**
 * WKWebViewEditorStatePrivate.h
 * Refrax Browser
 *
 * Private WKWebView methods for editor state observation.
 *
 * On macOS, WebKit does not call `_WKInputDelegate.didStartInputSession:` like on iOS.
 * Instead, it calls `_web_editorStateDidChange` when the editor state changes
 * (including when a form field gains or loses focus).
 *
 * This header exposes methods needed to:
 * 1. Swizzle `_web_editorStateDidChange` to detect form field focus
 * 2. Access secure input state via Carbon API to detect password fields
 *
 * ## Architecture on iOS vs macOS
 *
 * iOS:
 * - WebPage::elementDidFocus() sends ElementDidFocus IPC with FocusedElementInformation
 * - WebPageProxy::elementDidFocus() → pageClient→_elementDidFocus()
 * - Calls _WKInputDelegate._webView:didStartInputSession:
 *
 * macOS:
 * - WebPage::elementDidFocus() sends SetEditableElementIsFocused(bool) - just a boolean!
 * - WebPageProxy::setEditableElementIsFocused() → pageClient→setEditableElementIsFocused()
 * - Updates editorState.isInPasswordField and calls EnableSecureEventInput()/DisableSecureEventInput()
 * - Calls _web_editorStateDidChange but NOT _webView:didStartInputSession:
 *
 * ## Our Solution
 *
 * We swizzle `_web_editorStateDidChange` to:
 * 1. Detect when secure input state changes (password field focus)
 * 2. Query the focused element via JavaScript for complete field info
 * 3. Create a synthetic _WKFormInputSession and call our delegate
 *
 * ## Thread Safety
 * All methods must be called on the main thread.
 *
 * ## Source References
 * - WebKit/Source/WebKit/UIProcess/API/mac/WKWebViewMac.mm
 * - WebKit/Source/WebKit/UIProcess/mac/WebViewImpl.mm
 *
 * Last verified: WebKit trunk (December 2024)
 */

#import <WebKit/WebKit.h>
#import <Carbon/Carbon.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - WKWebView Editor State Methods

/**
 * Private WKWebView methods for editor state observation.
 *
 * These methods are called by WebKit internally when the editor state changes.
 * `_web_editorStateDidChange` is the Objective-C entry point that we can swizzle.
 */
@interface WKWebView (WKEditorStatePrivate)

/**
 * Called when the editor state changes.
 *
 * This is called whenever:
 * - An editable element receives focus
 * - An editable element loses focus
 * - The selection changes within an editable element
 * - Text is typed or deleted
 *
 * On macOS, this is the method we swizzle to detect form field focus
 * since `_webView:didStartInputSession:` is never called.
 *
 * ## Call Chain
 * 1. WebViewImpl::selectionDidChange() (C++)
 * 2. [m_view _web_editorStateDidChange] (Objective-C bridge)
 * 3. [self _didChangeEditorState] (internal)
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/mac/WKWebViewMac.mm:1388
 */
- (void)_web_editorStateDidChange;

/**
 * Called internally to process editor state changes.
 *
 * This method:
 * - Updates `_selectionAttributes`
 * - Calls `_webView:editorStateDidChange:` on the UI delegate (for testing only)
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebView.mm:2335
 */
- (void)_didChangeEditorState;

@end

#pragma mark - Secure Input State Functions

/**
 * Checks if macOS secure input mode is enabled.
 *
 * On macOS, when a password field gains focus, WebKit calls EnableSecureEventInput().
 * This function returns YES when a password field is currently focused.
 *
 * ## Usage
 * By comparing the return value before and after `_web_editorStateDidChange`,
 * we can detect when focus moves to or from a password field.
 *
 * ## Thread Safety
 * This is a Carbon API that should be called from the main thread.
 *
 * ## Source
 * Carbon/HIToolbox/CarbonEventsCore.h
 * WebKit/Source/WebKit/UIProcess/mac/WebViewImpl.mm:2630 (updateSecureInputState)
 */
static inline BOOL WKIsSecureInputEnabled(void) {
    return IsSecureEventInputEnabled() != 0;
}

NS_ASSUME_NONNULL_END
