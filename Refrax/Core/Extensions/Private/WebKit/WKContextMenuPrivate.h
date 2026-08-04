/**
 * WKContextMenuPrivate.h
 * Refrax Browser
 *
 * Private WebKit APIs for context menu customization and hit testing.
 *
 * This header provides comprehensive context menu functionality:
 * - `_WKHitTestResult`: Detailed element information at a point
 * - `_WKContextMenuElementInfo`: Context menu-specific element data
 * - `WKUIDelegatePrivate` context menu methods
 * - Immediate action (Force Touch) support
 *
 * ## Architecture
 * When the user right-clicks, WebKit performs a hit test and provides:
 * 1. `_WKContextMenuElementInfo` - wrapper with context menu data
 * 2. `_WKHitTestResult` - detailed element information
 *
 * ## Thread Safety
 * All APIs must be called on the main thread.
 *
 * ## Source References
 * WebKit/Source/WebKit/Shared/API/Cocoa/_WKHitTestResult.h
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKContextMenuElementInfo.h
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKUIDelegatePrivate.h
 *
 * Last verified: WebKit trunk (December 2024)
 */

#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Forward Declarations

@class _WKInspector;

#pragma mark - Hit Test Result Element Type

/**
 * Element type for media elements in hit test results.
 *
 * Used to identify if the hit test target is an audio or video element.
 *
 * ## Source
 * WebKit/Source/WebKit/Shared/API/Cocoa/_WKHitTestResult.h
 *
 * ## Availability
 * macOS 14.4+, iOS 17.4+
 */
typedef NS_ENUM(NSInteger, _WKHitTestResultElementType) {
    /** Not a media element (default). */
    _WKHitTestResultElementTypeNone,

    /** An `<audio>` element. */
    _WKHitTestResultElementTypeAudio,

    /** A `<video>` element. */
    _WKHitTestResultElementTypeVideo,
} API_AVAILABLE(macos(14.4), ios(17.4));

#pragma mark - Immediate Action Type

/**
 * Types of immediate actions (Force Touch previews).
 *
 * Returned by WebKit when performing immediate action hit tests to indicate
 * what type of content was found at the target location.
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebViewPrivate.h
 *
 * ## Availability
 * macOS 10.12+
 */
typedef NS_ENUM(NSInteger, _WKImmediateActionType) {
    /** No immediate action available for this content. */
    _WKImmediateActionNone,

    /** Link preview - shows a preview of the linked page. */
    _WKImmediateActionLinkPreview,

    /** Data detector item - actions for detected data (addresses, phones, dates). */
    _WKImmediateActionDataDetectedItem,

    /** Dictionary lookup - definition for selected text. */
    _WKImmediateActionLookupText,

    /** Mailto link - email composition preview. */
    _WKImmediateActionMailtoLink,

    /** Tel link - phone call action. */
    _WKImmediateActionTelLink,
} API_AVAILABLE(macos(10.12));

#pragma mark - _WKHitTestResult

/**
 * Contains detailed information about the element at a specific point.
 *
 * Provides comprehensive information about what the user clicked/tapped on,
 * including URLs, text content, state, and geometry.
 *
 * ## Thread Safety
 * Must be accessed on the main thread only.
 *
 * ## Usage
 * @code
 * if (hitTestResult.absoluteLinkURL) {
 *     [self addOpenInNewTabItem:hitTestResult.absoluteLinkURL];
 * }
 *
 * if (hitTestResult.absoluteImageURL) {
 *     [self addSaveImageItem:hitTestResult.absoluteImageURL];
 * }
 *
 * if (hitTestResult.contentEditable) {
 *     [self addPasteItem];
 * }
 * @endcode
 *
 * ## Source
 * WebKit/Source/WebKit/Shared/API/Cocoa/_WKHitTestResult.h
 *
 * ## Availability
 * macOS 10.12+, iOS 10.0+
 */
API_AVAILABLE(macos(10.12), ios(10.0))
@interface _WKHitTestResult : NSObject <NSCopying>

#pragma mark URL Properties

/**
 * The absolute URL of an image element (`<img>` src or `<video>` poster).
 *
 * Returns nil if the hit test did not target an image.
 */
@property (nonatomic, readonly, copy, nullable) NSURL *absoluteImageURL;

/**
 * The MIME type of the image, if available.
 *
 * Examples: "image/png", "image/jpeg", "image/gif", "image/webp"
 *
 * ## Availability
 * macOS 14.4+, iOS 17.4+
 */
@property (nonatomic, readonly, copy, nullable) NSString *imageMIMEType
    API_AVAILABLE(macos(14.4), ios(17.4));

/** The absolute URL of a PDF element, if present. */
@property (nonatomic, readonly, copy, nullable) NSURL *absolutePDFURL;

/**
 * The absolute URL of a link element (`<a>` href).
 *
 * Returns nil if the hit test did not target a link.
 */
@property (nonatomic, readonly, copy, nullable) NSURL *absoluteLinkURL;

/**
 * The absolute URL of a media element (`<audio>` or `<video>` src).
 *
 * Returns nil if the hit test did not target a media element.
 */
@property (nonatomic, readonly, copy, nullable) NSURL *absoluteMediaURL;

#pragma mark Link Properties

/** The visible text content of a link element. */
@property (nonatomic, readonly, copy, nullable) NSString *linkLabel;

/** The `title` attribute of a link element (tooltip text). */
@property (nonatomic, readonly, copy, nullable) NSString *linkTitle;

/**
 * A suggested filename for downloading the linked resource.
 *
 * Derived from the `download` attribute or URL path.
 *
 * ## Availability
 * macOS 15.0+, iOS 18.0+
 */
@property (nonatomic, readonly, copy, nullable) NSString *linkSuggestedFilename
    API_AVAILABLE(macos(15.0), ios(18.0));

#pragma mark Image Properties

/**
 * A suggested filename for downloading the image.
 *
 * ## Availability
 * macOS 15.0+, iOS 18.0+
 */
@property (nonatomic, readonly, copy, nullable) NSString *imageSuggestedFilename
    API_AVAILABLE(macos(15.0), ios(18.0));

#pragma mark Text Properties

/**
 * Text suitable for dictionary lookup.
 *
 * When the user clicks on or selects text, this contains text that can
 * be looked up in the dictionary.
 */
@property (nonatomic, readonly, copy, nullable) NSString *lookupText;

#pragma mark State Properties

/**
 * Whether the hit test target is in an editable region.
 *
 * YES for `<input>`, `<textarea>`, `contenteditable` elements, or
 * documents with `designMode="on"`.
 */
@property (nonatomic, readonly, getter=isContentEditable) BOOL contentEditable;

/**
 * Whether text is selected at the hit test location.
 *
 * ## Availability
 * macOS 14.4+, iOS 17.4+
 */
@property (nonatomic, readonly, getter=isSelected) BOOL selected
    API_AVAILABLE(macos(14.4), ios(17.4));

/**
 * Whether the media element can be downloaded.
 *
 * May be NO for streaming sources or DRM-protected content.
 *
 * ## Availability
 * macOS 14.4+, iOS 17.4+
 */
@property (nonatomic, readonly, getter=isMediaDownloadable) BOOL mediaDownloadable
    API_AVAILABLE(macos(14.4), ios(17.4));

/**
 * Whether the media element is in fullscreen mode.
 *
 * ## Availability
 * macOS 14.4+, iOS 17.4+
 */
@property (nonatomic, readonly, getter=isMediaFullscreen) BOOL mediaFullscreen
    API_AVAILABLE(macos(14.4), ios(17.4));

#pragma mark Geometry

/**
 * The bounding box of the hit element in view coordinates.
 *
 * Useful for positioning context menus or popovers relative to the element.
 */
@property (nonatomic, readonly) CGRect elementBoundingBox;

#pragma mark Element Type

/**
 * The type of media element (audio, video, or none).
 *
 * ## Availability
 * macOS 14.4+, iOS 17.4+
 */
@property (nonatomic, readonly) _WKHitTestResultElementType elementType
    API_AVAILABLE(macos(14.4), ios(17.4));

#pragma mark Frame Information

/**
 * Information about the frame containing the hit element.
 *
 * Useful for determining if the element is in the main frame or an iframe.
 *
 * ## Availability
 * macOS 14.4+, iOS 17.4+
 */
@property (nonatomic, readonly, nullable) WKFrameInfo *frameInfo
    API_AVAILABLE(macos(14.4), ios(17.4));

@end

#pragma mark - _WKContextMenuElementInfo (macOS only)

#if TARGET_OS_OSX

/**
 * Contains context menu element information for macOS.
 *
 * Passed to the UI delegate's context menu callback, providing access to
 * hit test results and additional context menu-specific information.
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKContextMenuElementInfo.h
 *
 * ## Availability
 * macOS 10.12+ (macOS only)
 */
API_AVAILABLE(macos(10.12))
@interface _WKContextMenuElementInfo : NSObject <NSCopying>

/**
 * The hit test result with detailed element information.
 *
 * ## Availability
 * macOS 13.3+
 */
@property (nonatomic, readonly, copy, nullable) _WKHitTestResult *hitTestResult
    API_AVAILABLE(macos(13.3));

/**
 * The decoded payload of a detected QR code, if present.
 *
 * When right-clicking on a QR code that WebKit detected, this contains
 * the decoded payload (usually a URL or text).
 *
 * ## Availability
 * macOS 14.0+
 */
@property (nonatomic, readonly, copy, nullable) NSString *qrCodePayloadString
    API_AVAILABLE(macos(14.0));

/**
 * Whether the entire image is visible in the viewport.
 *
 * YES if the clicked image is fully visible without scrolling.
 *
 * ## Availability
 * macOS 14.0+
 */
@property (nonatomic, readonly) BOOL hasEntireImage
    API_AVAILABLE(macos(14.0));

/**
 * Whether following the link is allowed by content security policy.
 *
 * ## Availability
 * macOS 26.0+
 */
@property (nonatomic, readonly) BOOL allowsFollowingLink
    API_AVAILABLE(macos(26.0));

/**
 * Whether following the image URL is allowed by content security policy.
 *
 * ## Availability
 * macOS 26.0+
 */
@property (nonatomic, readonly) BOOL allowsFollowingImageURL
    API_AVAILABLE(macos(26.0));

@end

#endif /* TARGET_OS_OSX */

#pragma mark - WKUIDelegatePrivate Context Menu Methods

/**
 * Private UI delegate methods for context menu customization.
 *
 * Implement these on your WKUIDelegate to customize context menus.
 */
@protocol WKUIDelegatePrivate <WKUIDelegate>
@optional

#if TARGET_OS_OSX

/**
 * Called to customize the context menu before display.
 *
 * @param webView The web view requesting the context menu.
 * @param menu The proposed menu with WebKit's default items.
 * @param element Information about the clicked element.
 * @param userInfo Optional data from web content.
 * @param completionHandler Call with the final menu, or nil to cancel.
 *
 * ## Example
 * @code
 * - (void)_webView:(WKWebView *)webView
 *     getContextMenuFromProposedMenu:(NSMenu *)menu
 *                         forElement:(_WKContextMenuElementInfo *)element
 *                           userInfo:(id<NSSecureCoding>)userInfo
 *                  completionHandler:(void (^)(NSMenu *))completionHandler {
 *
 *     NSMutableArray *items = [menu.itemArray mutableCopy];
 *
 *     // Add custom items for links
 *     if (element.hitTestResult.absoluteLinkURL) {
 *         NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Open in New Tab"
 *                                                       action:@selector(openInNewTab:)
 *                                                keyEquivalent:@""];
 *         item.representedObject = element.hitTestResult.absoluteLinkURL;
 *         [items insertObject:item atIndex:0];
 *         [items insertObject:[NSMenuItem separatorItem] atIndex:1];
 *     }
 *
 *     NSMenu *customMenu = [[NSMenu alloc] init];
 *     [customMenu setItemArray:items];
 *     completionHandler(customMenu);
 * }
 * @endcode
 *
 * ## Availability
 * macOS 10.14+
 */
- (void)_webView:(WKWebView *)webView
    getContextMenuFromProposedMenu:(NSMenu *)menu
                        forElement:(_WKContextMenuElementInfo *)element
                          userInfo:(nullable id<NSSecureCoding>)userInfo
                 completionHandler:(void (^)(NSMenu * _Nullable))completionHandler
    API_AVAILABLE(macos(10.14));

/**
 * Called when a context menu action creates a download.
 *
 * This is called when the user selects "Download Linked File" or similar.
 *
 * @param webView The web view that initiated the download.
 * @param download The download object to configure.
 *
 * ## Important
 * You must set a delegate on the download to provide a destination URL.
 */
- (void)_webView:(WKWebView *)webView
    contextMenuDidCreateDownload:(WKDownload *)download;

/**
 * Called when the user saves content WebKit already holds in memory.
 *
 * The PDF viewer HUD's download button delivers the document through this
 * method — no WKDownload is created. WebKit drops the action silently when
 * the delegate does not implement this selector
 * (`UIDelegate::UIClient::saveDataToFileInDownloadsFolder`).
 *
 * @param webView The web view the content belongs to.
 * @param data The file contents.
 * @param suggestedFilename Sanitized filename to save under.
 * @param mimeType MIME type of the data.
 * @param url The URL the content was loaded from.
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKUIDelegatePrivate.h
 *
 * ## Availability
 * macOS 10.13.4+
 */
- (void)_webView:(WKWebView *)webView
    saveDataToFile:(NSData *)data
    suggestedFilename:(NSString *)suggestedFilename
    mimeType:(NSString *)mimeType
    originatingURL:(NSURL *)url
    API_AVAILABLE(macos(10.13.4));

#endif /* TARGET_OS_OSX */

#pragma mark Mouse Tracking

/**
 * Called when the mouse moves over an element.
 *
 * Provides live hit test information as the mouse moves.
 *
 * @param webView The web view receiving the mouse event.
 * @param hitTestResult Information about the element under the mouse.
 * @param flags Keyboard modifier flags.
 * @param userInfo Optional data from web content.
 *
 * ## Usage
 * Update status bar with link URLs:
 * @code
 * - (void)_webView:(WKWebView *)webView
 *     mouseDidMoveOverElement:(_WKHitTestResult *)hitTestResult
 *                   withFlags:(NSEventModifierFlags)flags
 *                    userInfo:(id<NSSecureCoding>)userInfo {
 *
 *     if (hitTestResult.absoluteLinkURL) {
 *         self.statusBar.text = hitTestResult.absoluteLinkURL.absoluteString;
 *     } else {
 *         self.statusBar.text = @"";
 *     }
 * }
 * @endcode
 *
 * ## Availability
 * macOS 10.12+
 */
- (void)_webView:(WKWebView *)webView
    mouseDidMoveOverElement:(_WKHitTestResult *)hitTestResult
                  withFlags:(NSEventModifierFlags)flags
                   userInfo:(nullable id<NSSecureCoding>)userInfo
    API_AVAILABLE(macos(10.12));

#pragma mark Immediate Action (Force Touch)

/**
 * Called before immediate action animation begins.
 *
 * Prepare UI for the preview animation (e.g., highlight the link).
 *
 * ## Availability
 * macOS 10.13.4+
 */
- (void)_prepareForImmediateActionAnimationForWebView:(WKWebView *)webView
    API_AVAILABLE(macos(10.13.4));

/**
 * Called when immediate action animation is cancelled.
 *
 * Clean up any UI state from `_prepareForImmediateActionAnimationForWebView:`.
 *
 * ## Availability
 * macOS 10.13.4+
 */
- (void)_cancelImmediateActionAnimationForWebView:(WKWebView *)webView
    API_AVAILABLE(macos(10.13.4));

/**
 * Called when immediate action animation completes.
 *
 * The preview is now fully displayed.
 *
 * ## Availability
 * macOS 10.13.4+
 */
- (void)_completeImmediateActionAnimationForWebView:(WKWebView *)webView
    API_AVAILABLE(macos(10.13.4));

@end

#pragma mark - WKWebView Immediate Action Extension

/**
 * Private WKWebView methods for immediate action (Force Touch) handling.
 */
@interface WKWebView (WKPrivateImmediateAction)

/**
 * Provides a custom animation controller for immediate action gestures.
 *
 * Called when the user performs a Force Touch gesture on content.
 *
 * @param hitTestResult Information about the element under the gesture.
 * @param type The type of immediate action detected.
 * @param userData Additional data from web content.
 * @return An animation controller, [NSNull null] to disable, or nil for default.
 *
 * ## Return Values
 * - `nil`: Use WebKit's default preview behavior
 * - `[NSNull null]`: Disable immediate action for this content
 * - Custom controller: Use your own preview implementation
 *
 * ## Availability
 * macOS 10.12+
 */
- (nullable id)_immediateActionAnimationControllerForHitTestResult:(_WKHitTestResult *)hitTestResult
                                                          withType:(_WKImmediateActionType)type
                                                          userData:(nullable id<NSSecureCoding>)userData
    API_AVAILABLE(macos(10.12));

@end

NS_ASSUME_NONNULL_END
