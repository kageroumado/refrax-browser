/*
 * WebKitPrivate.h
 * Refrax Browser
 *
 * Bridging header for WebKit private APIs used in Refrax.
 *
 * ## Swift Helpers
 *
 * Some APIs in this header have Swift-friendly async/await wrappers in
 * `WKWebView+PrivateHelpers.swift`. Prefer using those extensions when calling
 * from Swift code, as they provide better ergonomics with Swift concurrency.
 *
 * ## Overview
 *
 * This header declares WebKit private APIs that are not available in the public SDK.
 * These APIs provide functionality essential for building a full-featured browser:
 *
 * - Context menu customization with hit test results
 * - Immediate action (Force Touch / link preview) support
 * - Audio playback state and muting
 * - Media capture state (camera, microphone, screen sharing)
 * - Display/screen capture control
 * - Web Inspector control
 * - Fullscreen management
 * - Autoplay event handling
 * - Tab thumbnail/preview generation
 * - Form input session and autofill hooks
 * - WebAuthentication (Passkeys/FIDO) management
 * - Data detection (addresses, phone numbers, dates) on macOS
 *
 * ## Important Notes
 *
 * 1. **Stability**: Private APIs may change between macOS versions. Test thoroughly
 *    on each new OS release.
 *
 * 2. **App Store**: These APIs are NOT allowed in App Store submissions. This browser
 *    is distributed outside the App Store.
 *
 * 3. **Availability**: Some properties have minimum macOS version requirements noted
 *    in comments. Check availability before use.
 *
 * 4. **Thread Safety**: All WebKit APIs must be called on the main thread.
 *
 * ## Source References
 *
 * Declarations are derived from WebKit source code:
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/WKUIDelegatePrivate.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebViewPrivate.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/WKPreferencesPrivate.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKContextMenuElementInfo.h
 * - WebKit/Source/WebKit/Shared/API/Cocoa/_WKHitTestResult.h
 * - WebKit/Source/WebCore/PAL/pal/spi/mac/NSImmediateActionGestureRecognizerSPI.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKThumbnailView.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKInputDelegate.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKFormInputSession.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKFocusedElementInfo.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKWebAuthenticationPanel.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKIconLoadingDelegate.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKLinkIconParameters.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/WKHistoryDelegatePrivate.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/WKNavigationData.h
 *
 * Last verified against: WebKit trunk (December 2024)
 */

#import <WebKit/WebKit.h>
#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - Forward Declarations

@class _WKHitTestResult;
@class _WKContextMenuElementInfo;
@class _WKInspector;
@class _WKThumbnailView;
@class _WKWebAuthenticationPanel;
@class _WKLinkIconParameters;
@class WKNavigationData;
@class SSBLookupResult;
@class NSScrollPocket;
@class LAContext;
@protocol _WKFocusedElementInfo;
@protocol _WKFormInputSession;
@protocol _WKIconLoadingDelegate;
@protocol WKHistoryDelegatePrivate;

// MARK: - _WKHitTestResultElementType

/// Element type for hit test results.
///
/// Used to determine if the hit test target is a media element.
///
/// ## Source
/// WebKit/Source/WebKit/Shared/API/Cocoa/_WKHitTestResult.h
///
/// ## Availability
/// macOS 14.4+
typedef NS_ENUM(NSInteger, _WKHitTestResultElementType) {
    /// No specific element type (default for most elements).
    _WKHitTestResultElementTypeNone,

    /// An `<audio>` element.
    _WKHitTestResultElementTypeAudio,

    /// A `<video>` element.
    _WKHitTestResultElementTypeVideo,
} API_AVAILABLE(macos(14.4));

// MARK: - _WKImmediateActionType

/// Types of immediate actions (Force Touch previews).
///
/// Returned by WebKit when performing immediate action hit tests to indicate
/// what type of content was found at the target location.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebViewPrivate.h
///
/// ## Availability
/// macOS 10.12+
typedef NS_ENUM(NSInteger, _WKImmediateActionType) {
    /// No immediate action available for this content.
    _WKImmediateActionNone,

    /// Link preview - shows a preview of the linked page.
    /// Triggered for HTTP/HTTPS links.
    _WKImmediateActionLinkPreview,

    /// Data detector item - shows actions for detected data.
    /// Examples: addresses, phone numbers, dates.
    _WKImmediateActionDataDetectedItem,

    /// Dictionary lookup - shows definition for selected text.
    _WKImmediateActionLookupText,

    /// Mailto link - shows email composition preview.
    _WKImmediateActionMailtoLink,

    /// Tel link - shows phone call action.
    _WKImmediateActionTelLink
} API_AVAILABLE(macos(10.12));

// MARK: - _WKMediaMutedState

/// Media mute state flags for WKWebView.
///
/// These flags control which types of media are muted in the web view.
/// Multiple flags can be combined using bitwise OR.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebViewPrivate.h
///
/// ## Usage
/// ```objc
/// // Mute audio only
/// [webView _setPageMuted:_WKMediaAudioMuted];
///
/// // Mute everything
/// [webView _setPageMuted:_WKMediaAudioMuted | _WKMediaCaptureDevicesMuted];
/// ```
typedef NS_OPTIONS(NSUInteger, _WKMediaMutedState) {
    /// No media is muted.
    _WKMediaNoneMuted = 0,

    /// Audio playback is muted.
    /// This affects `<audio>` and `<video>` elements.
    _WKMediaAudioMuted = 1 << 0,

    /// Capture devices (microphone, camera) are muted.
    _WKMediaCaptureDevicesMuted = 1 << 1,

    /// Screen capture is muted.
    /// This affects screen/window sharing via getDisplayMedia().
    /// By default, WebKit mutes screen capture audio when sharing - set this to unmute.
    _WKMediaScreenCaptureMuted = 1 << 2,
} API_AVAILABLE(macos(10.13));

// MARK: - WKDisplayCaptureState

/// Display capture state for screen/window sharing.
///
/// Used with `_displayCaptureState` and `_setDisplayCaptureState:completionHandler:`
/// to control screen sharing audio.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebViewPrivate.h
typedef NS_ENUM(NSInteger, WKDisplayCaptureState) {
    /// No display capture is active.
    WKDisplayCaptureStateNone,

    /// Display capture is active and audio is enabled.
    WKDisplayCaptureStateActive,

    /// Display capture is active but audio is muted.
    WKDisplayCaptureStateMuted,
} API_AVAILABLE(macos(13.0));

// MARK: - WKSystemAudioCaptureState

/// System audio capture state for tab audio sharing.
///
/// Used with `_systemAudioCaptureState` and `_setSystemAudioCaptureState:completionHandler:`
/// to control system audio capture during screen sharing.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebViewPrivate.h
typedef NS_ENUM(NSInteger, WKSystemAudioCaptureState) {
    /// No system audio capture is active.
    WKSystemAudioCaptureStateNone,

    /// System audio capture is active.
    WKSystemAudioCaptureStateActive,

    /// System audio capture is muted.
    WKSystemAudioCaptureStateMuted,
} API_AVAILABLE(macos(13.0));

// MARK: - _WKAutoplayEvent

/// Autoplay events reported by WebKit.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/WKUIDelegatePrivate.h
typedef NS_ENUM(NSInteger, _WKAutoplayEvent) {
    /// Media was prevented from autoplaying.
    _WKAutoplayEventDidPreventFromAutoplaying,

    /// Media was played with user gesture.
    _WKAutoplayEventDidPlayMediaWithUserGesture,

    /// Media autoplayed past threshold without user interference.
    _WKAutoplayEventDidAutoplayMediaPastThresholdWithoutUserInterference,

    /// User interfered with playback.
    _WKAutoplayEventUserDidInterfereWithPlayback,
} API_AVAILABLE(macos(10.13.4));

// MARK: - _WKAutoplayEventFlags

/// Flags providing additional context for autoplay events.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/WKUIDelegatePrivate.h
typedef NS_OPTIONS(NSUInteger, _WKAutoplayEventFlags) {
    _WKAutoplayEventFlagsNone = 0,

    /// The media has audio.
    _WKAutoplayEventFlagsHasAudio = 1 << 0,

    /// Playback was prevented.
    _WKAutoplayEventFlagsPlaybackWasPrevented = 1 << 1,

    /// Media is the main content of the page.
    _WKAutoplayEventFlagsMediaIsMainContent = 1 << 2,
} API_AVAILABLE(macos(10.13.4));

// MARK: - _WKMediaCaptureStateDeprecated

/// Deprecated media capture state (use _WKMediaMutedState instead).
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebViewPrivate.h
typedef NS_OPTIONS(NSUInteger, _WKMediaCaptureStateDeprecated) {
    _WKMediaCaptureStateDeprecatedNone = 0,
    _WKMediaCaptureStateDeprecatedActiveMicrophone = 1 << 0,
    _WKMediaCaptureStateDeprecatedActiveCamera = 1 << 1,
    _WKMediaCaptureStateDeprecatedMutedMicrophone = 1 << 2,
    _WKMediaCaptureStateDeprecatedMutedCamera = 1 << 3,
} API_AVAILABLE(macos(10.15));

// MARK: - _WKWebProcessState

/// Web process lifecycle state for monitoring tab resource usage.
///
/// This enum represents the current state of the web process associated
/// with a WKWebView. It's useful for:
/// - Showing visual indicators for unloaded/suspended tabs
/// - Understanding which tabs are consuming resources
/// - Implementing tab discarding/restoration UI
///
/// ## KVO Compliance
/// The `_webProcessState` property on WKWebView is KVO-compliant, but only
/// sends updates when there are registered observers. WebKit uses observer
/// registration to determine whether to notify about state changes.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebViewPrivate.h
///
/// ## Availability
/// macOS 15.4+
typedef NS_ENUM(NSInteger, _WKWebProcessState) {
    /// The web process is not running.
    ///
    /// This state indicates the tab's content has been discarded from memory.
    /// The tab can be restored by loading the URL again. Common causes:
    /// - System terminated the process due to memory pressure
    /// - User manually discarded the tab
    /// - The process crashed
    _WKWebProcessStateNotRunning,

    /// The web process is running in the foreground.
    ///
    /// This is the normal state for the active tab.
    /// The process has full CPU and memory priority.
    _WKWebProcessStateForeground,

    /// The web process is running in the background.
    ///
    /// The process is still alive but has reduced priority.
    /// Background tabs enter this state when not visible.
    _WKWebProcessStateBackground,

    /// The web process is suspended.
    ///
    /// The process is frozen and not executing code.
    /// This saves CPU but maintains memory state.
    /// Common on iOS when the app is backgrounded.
    _WKWebProcessStateSuspended,
} API_AVAILABLE(macos(15.4));

// MARK: - WKLinkIconType

/// Type of favicon/icon linked from a web page.
///
/// Web pages can specify multiple icon types via `<link>` elements.
/// This enum identifies the type of icon for appropriate handling.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKLinkIconParameters.h
///
/// ## Usage with _WKIconLoadingDelegate
/// When implementing the icon loading delegate, check the icon type to
/// determine which icons to load (you may want all favicons but skip
/// touch icons, or vice versa).
///
/// ## Availability
/// macOS 10.12.4+
typedef NS_ENUM(NSInteger, WKLinkIconType) {
    /// Standard favicon (16x16 to 48x48).
    ///
    /// The classic favicon, typically specified as:
    /// `<link rel="icon" href="favicon.ico">`
    /// `<link rel="shortcut icon" href="favicon.png">`
    WKLinkIconTypeFavicon,

    /// Apple Touch Icon (for iOS home screen).
    ///
    /// Higher resolution icon for iOS devices:
    /// `<link rel="apple-touch-icon" href="icon.png">`
    ///
    /// Note: "touch icon" means iOS will apply visual effects (rounded corners, gloss).
    WKLinkIconTypeTouchIcon,

    /// Precomposed Apple Touch Icon (no effects applied).
    ///
    /// Same as touch icon but iOS won't add visual effects:
    /// `<link rel="apple-touch-icon-precomposed" href="icon.png">`
    WKLinkIconTypeTouchPrecomposedIcon,
} API_AVAILABLE(macos(10.12.4));

// MARK: - _WKCaptureDevices

/// Capture device types for permission requests.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebViewPrivate.h
typedef NS_OPTIONS(NSUInteger, _WKCaptureDevices) {
    _WKCaptureDeviceMicrophone = 1 << 0,
    _WKCaptureDeviceCamera = 1 << 1,
    _WKCaptureDeviceDisplay = 1 << 2,
} API_AVAILABLE(macos(10.13));

// MARK: - _WKHitTestResult

/// Contains detailed information about the element at a specific point in a web view.
///
/// This class is returned by WebKit when performing hit tests (e.g., for context menus
/// or immediate actions). It provides comprehensive information about what the user
/// clicked or tapped on.
///
/// ## Thread Safety
/// Must be accessed on the main thread only.
///
/// ## Source
/// WebKit/Source/WebKit/Shared/API/Cocoa/_WKHitTestResult.h
///
/// ## Example Usage
/// ```swift
/// // In context menu delegate:
/// if let linkURL = hitTestResult.absoluteLinkURL {
///     // User clicked on a link
///     addOpenInNewTabMenuItem(for: linkURL)
/// }
///
/// if let imageURL = hitTestResult.absoluteImageURL {
///     // User clicked on an image
///     addSaveImageMenuItem(for: imageURL)
/// }
///
/// if hitTestResult.isContentEditable {
///     // User clicked in an editable area
///     addPasteMenuItem()
/// }
/// ```
API_AVAILABLE(macos(10.12))
@interface _WKHitTestResult : NSObject <NSCopying>

// MARK: URL Properties

/// The absolute URL of an image element, if present.
///
/// This is the resolved `src` attribute of an `<img>` element or the
/// `poster` attribute of a `<video>` element.
///
/// Returns `nil` if the hit test did not target an image.
@property (nonatomic, readonly, copy, nullable) NSURL *absoluteImageURL;

/// The MIME type of the image, if available.
///
/// Examples: "image/png", "image/jpeg", "image/gif"
///
/// ## Availability
/// macOS 14.4+
@property (nonatomic, readonly, copy, nullable) NSString *imageMIMEType API_AVAILABLE(macos(14.4));

/// The absolute URL of a PDF element, if present.
///
/// Returns `nil` if the hit test did not target a PDF.
@property (nonatomic, readonly, copy, nullable) NSURL *absolutePDFURL;

/// The absolute URL of a link element, if present.
///
/// This is the resolved `href` attribute of an `<a>` element.
/// Returns `nil` if the hit test did not target a link.
@property (nonatomic, readonly, copy, nullable) NSURL *absoluteLinkURL;

/// The absolute URL of a media element, if present.
///
/// This is the resolved `src` attribute of an `<audio>` or `<video>` element.
/// Returns `nil` if the hit test did not target a media element.
@property (nonatomic, readonly, copy, nullable) NSURL *absoluteMediaURL;

/// The local resource response for link URLs, if available.
///
/// When a link points to a local resource that WebKit has cached,
/// this property provides the response metadata.
///
/// ## Availability
/// macOS 26.0+
@property (nonatomic, readonly, copy, nullable) NSURLResponse *linkLocalResourceResponse API_AVAILABLE(macos(26.0));

// MARK: Link Properties

/// The visible text content of a link element.
///
/// For `<a>Some Text</a>`, this returns "Some Text".
/// Returns an empty string if the link has no text content.
@property (nonatomic, readonly, copy, nullable) NSString *linkLabel;

/// The `title` attribute of a link element.
///
/// This is often displayed as a tooltip when hovering over the link.
/// Returns `nil` if no title attribute is present.
@property (nonatomic, readonly, copy, nullable) NSString *linkTitle;

/// A suggested filename for downloading the linked resource.
///
/// Derived from the `download` attribute or the URL path.
///
/// ## Availability
/// macOS 15.0+
@property (nonatomic, readonly, copy, nullable) NSString *linkSuggestedFilename API_AVAILABLE(macos(15.0));

/// Whether the link has a target frame specified.
///
/// `YES` if the link has a `target` attribute.
///
/// ## Availability
/// macOS 26.0+ (WK_MAC_TBA)
@property (nonatomic, readonly) BOOL linkHasTargetFrame;

/// Whether the link's target frame is the same as the link's containing frame.
///
/// `YES` if target="_self" or equivalent.
///
/// ## Availability
/// macOS 26.0+ (WK_MAC_TBA)
@property (nonatomic, readonly) BOOL linkTargetFrameIsSameAsLinkFrame;

/// Whether the link's target frame is in a different WKWebView.
///
/// `YES` if the link opens in a different web view.
///
/// ## Availability
/// macOS 26.0+ (WK_MAC_TBA)
@property (nonatomic, readonly) BOOL linkTargetFrameIsInDifferentWebView;

// MARK: Image Properties

/// A suggested filename for downloading the image.
///
/// Derived from the URL path or content-disposition header.
///
/// ## Availability
/// macOS 15.0+
@property (nonatomic, readonly, copy, nullable) NSString *imageSuggestedFilename API_AVAILABLE(macos(15.0));

// MARK: Text Properties

/// Text suitable for dictionary lookup.
///
/// When the user clicks on or selects text, this property contains the
/// text that can be looked up in the dictionary.
///
/// Returns `nil` if no lookupable text is available.
@property (nonatomic, readonly, copy, nullable) NSString *lookupText;

// MARK: State Properties

/// Whether the hit test target is in an editable region.
///
/// `YES` for:
/// - `<input>` and `<textarea>` elements
/// - Elements with `contenteditable="true"`
/// - Elements inside a `designMode="on"` document
@property (nonatomic, readonly, getter=isContentEditable) BOOL contentEditable;

/// Whether text is currently selected at the hit test location.
///
/// `YES` if there is an active text selection that includes the hit point.
///
/// ## Availability
/// macOS 14.4+
@property (nonatomic, readonly, getter=isSelected) BOOL selected API_AVAILABLE(macos(14.4));

/// Whether the media element is downloadable.
///
/// `YES` if the media element's source can be downloaded.
/// May be `NO` for streaming sources or DRM-protected content.
///
/// ## Availability
/// macOS 14.4+
@property (nonatomic, readonly, getter=isMediaDownloadable) BOOL mediaDownloadable API_AVAILABLE(macos(14.4));

/// Whether the media element is currently in fullscreen mode.
///
/// ## Availability
/// macOS 14.4+
@property (nonatomic, readonly, getter=isMediaFullscreen) BOOL mediaFullscreen API_AVAILABLE(macos(14.4));

// MARK: Geometry

/// The bounding box of the hit element in view coordinates.
///
/// This rectangle represents the visual bounds of the element that was hit.
/// Useful for positioning context menus or popovers relative to the element.
@property (nonatomic, readonly) CGRect elementBoundingBox;

// MARK: Element Type

/// The type of media element, if applicable.
///
/// Returns `_WKHitTestResultElementTypeNone` for non-media elements.
///
/// ## Availability
/// macOS 14.4+
@property (nonatomic, readonly) _WKHitTestResultElementType elementType API_AVAILABLE(macos(14.4));

// MARK: Frame Information

/// Information about the frame containing the hit element.
///
/// Useful for determining if the element is in the main frame or an iframe.
///
/// ## Availability
/// macOS 14.4+
@property (nonatomic, readonly, nullable) WKFrameInfo *frameInfo API_AVAILABLE(macos(14.4));

@end

// MARK: - _WKContextMenuElementInfo

/// Contains context menu element information for macOS.
///
/// This class is passed to the UI delegate's context menu callback and provides
/// access to the hit test result along with additional context menu-specific
/// information.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKContextMenuElementInfo.h
///
/// ## Note
/// This class is only available on macOS (not iOS).
///
/// ## Example Usage
/// ```swift
/// // In WKUIDelegatePrivate implementation:
/// func _webView(_ webView: WKWebView,
///               getContextMenuFromProposedMenu menu: NSMenu,
///               for element: _WKContextMenuElementInfo,
///               userInfo: Any?,
///               completionHandler: @escaping (NSMenu?) -> Void) {
///
///     let hitTest = element.hitTestResult
///
///     // Check for QR code
///     if let qrPayload = element.qrCodePayloadString {
///         // Add "Open QR Code" menu item
///     }
///
///     completionHandler(menu)
/// }
/// ```
#if TARGET_OS_OSX
API_AVAILABLE(macos(10.12))
@interface _WKContextMenuElementInfo : NSObject <NSCopying>

/// The hit test result containing detailed element information.
///
/// This property provides access to all the information about what the user
/// right-clicked on (links, images, media, text, etc.).
///
/// ## Availability
/// macOS 13.3+
@property (nonatomic, readonly, copy, nullable) _WKHitTestResult *hitTestResult API_AVAILABLE(macos(13.3));

/// The payload string of a detected QR code, if present.
///
/// When the user right-clicks on a QR code that WebKit has detected,
/// this property contains the decoded payload (usually a URL or text).
///
/// Returns `nil` if no QR code was detected at the click location.
///
/// ## Availability
/// macOS 14.0+
@property (nonatomic, readonly, copy, nullable) NSString *qrCodePayloadString API_AVAILABLE(macos(14.0));

/// Whether the entire image is visible in the viewport.
///
/// `YES` if the clicked image is fully visible without scrolling.
/// Useful for determining if "View Full Image" should be offered.
///
/// ## Availability
/// macOS 14.0+
@property (nonatomic, readonly) BOOL hasEntireImage API_AVAILABLE(macos(14.0));

/// Whether following the link is allowed.
///
/// May be `NO` due to content security policy or other restrictions.
///
/// ## Availability
/// macOS 26.0+
@property (nonatomic, readonly) BOOL allowsFollowingLink API_AVAILABLE(macos(26.0));

/// Whether following the image URL is allowed.
///
/// May be `NO` due to content security policy or other restrictions.
///
/// ## Availability
/// macOS 26.0+
@property (nonatomic, readonly) BOOL allowsFollowingImageURL API_AVAILABLE(macos(26.0));

@end
#endif

// MARK: - _WKLinkIconParameters

/// Contains information about a favicon or touch icon from a web page.
///
/// When a web page includes `<link rel="icon">` or `<link rel="apple-touch-icon">`
/// elements, WebKit parses them and provides this information through the
/// `_WKIconLoadingDelegate`.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKLinkIconParameters.h
///
/// ## Example Usage
/// ```swift
/// // In _WKIconLoadingDelegate implementation:
/// func webView(_ webView: WKWebView,
///              shouldLoadIconWith parameters: _WKLinkIconParameters,
///              completionHandler: @escaping ((Data?) -> Void) -> Void) {
///
///     // Only load standard favicons
///     guard parameters.iconType == .favicon else {
///         completionHandler { _ in } // Skip touch icons
///         return
///     }
///
///     // Return a callback that WebKit will call with the icon data
///     completionHandler { [weak self] data in
///         if let data = data, let image = NSImage(data: data) {
///             self?.updateFavicon(image, for: parameters.url)
///         }
///     }
/// }
/// ```
///
/// ## Availability
/// macOS 10.12.4+
API_AVAILABLE(macos(10.12.4))
@interface _WKLinkIconParameters : NSObject

/// The URL of the icon.
///
/// This is the resolved URL from the `href` attribute of the link element.
@property (nonatomic, readonly, copy) NSURL *url;

/// The type of icon (favicon, touch icon, etc.).
@property (nonatomic, readonly) WKLinkIconType iconType;

/// The MIME type of the icon, if specified.
///
/// May be `nil` if the page didn't specify a type attribute.
/// Example values: "image/png", "image/x-icon", "image/svg+xml"
@property (nonatomic, readonly, copy, nullable) NSString *mimeType;

/// The size hint for the icon, if specified.
///
/// From the `sizes` attribute, e.g., `<link rel="icon" sizes="32x32">`.
/// Contains just one dimension (assumes square icons).
/// May be `nil` if no size was specified.
@property (nonatomic, readonly, copy, nullable) NSNumber *size;

/// Additional attributes from the link element.
///
/// Contains all attributes as key-value pairs for custom handling.
///
/// ## Availability
/// macOS 10.14+
@property (nonatomic, readonly, copy, nullable) NSDictionary *attributes API_AVAILABLE(macos(10.14));

@end

// MARK: - WKNavigationData

/// Contains information about a navigation for history tracking.
///
/// This class is provided by `WKHistoryDelegatePrivate` callbacks to give
/// details about navigations for history management.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/WKNavigationData.h
///
/// ## Availability
/// macOS 10.10+
API_AVAILABLE(macos(10.10))
@interface WKNavigationData : NSObject

/// The title of the navigated page.
///
/// This is the value of the `<title>` element. May differ from the title
/// at page load completion if JavaScript modifies it.
@property (nonatomic, readonly, copy, nullable) NSString *title;

/// The original request that initiated the navigation.
///
/// Contains the URL, HTTP method, headers, etc. from the initial request.
@property (nonatomic, readonly, copy, nullable) NSURLRequest *originalRequest;

/// The final destination URL after any redirects.
///
/// If no redirects occurred, this equals `originalRequest.URL`.
@property (nonatomic, readonly, copy, nullable) NSURL *destinationURL;

/// The HTTP response from the server.
///
/// Contains status code, headers, and MIME type information.
@property (nonatomic, readonly, copy, nullable) NSURLResponse *response;

@end

// MARK: - _WKIconLoadingDelegate Protocol

/// Delegate for receiving native favicon/icon loading notifications.
///
/// Implement this protocol to receive callbacks when WebKit detects favicon
/// or touch icon links in web pages. This is more efficient than JavaScript-based
/// favicon detection because:
/// - WebKit notifies you directly when link elements are parsed
/// - No need to inject scripts or poll for changes
/// - Works even when JavaScript is disabled
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKIconLoadingDelegate.h
///
/// ## Setup
/// ```swift
/// // Set the delegate on your WKWebView
/// webView._setIconLoadingDelegate(self)
/// ```
///
/// ## Callback Pattern
/// The callback uses a double-completion-handler pattern:
/// 1. You receive parameters and a completion handler
/// 2. You call the completion handler with YOUR callback function
/// 3. WebKit calls your callback with the loaded icon data
///
/// This allows you to decide whether to load the icon at all, and
/// WebKit handles the actual network request.
///
/// ## Availability
/// macOS 10.12.4+
@protocol _WKIconLoadingDelegate <NSObject>
@optional

/// Called when WebKit discovers an icon link in a web page.
///
/// This method is called for each `<link rel="icon">` or `<link rel="apple-touch-icon">`
/// element found in the page's HTML.
///
/// @param webView The web view that found the icon.
/// @param parameters Information about the icon (URL, type, size).
/// @param completionHandler Call this with a callback to receive the icon data,
///                          or with an empty callback to skip loading.
///
/// ## Implementation Example
/// ```objc
/// - (void)webView:(WKWebView *)webView
///     shouldLoadIconWithParameters:(_WKLinkIconParameters *)parameters
///                completionHandler:(void (^)(void (^)(NSData *)))completionHandler {
///
///     // Only load favicons, skip touch icons
///     if (parameters.iconType != WKLinkIconTypeFavicon) {
///         completionHandler(^(NSData *data) { }); // No-op callback
///         return;
///     }
///
///     // Provide callback to receive the loaded icon data
///     completionHandler(^(NSData *iconData) {
///         if (iconData) {
///             NSImage *icon = [[NSImage alloc] initWithData:iconData];
///             [self updateTabIcon:icon forURL:webView.URL];
///         }
///     });
/// }
/// ```
- (void)webView:(WKWebView *)webView
    shouldLoadIconWithParameters:(_WKLinkIconParameters *)parameters
               completionHandler:(void (^)(void (^)(NSData * _Nullable)))completionHandler;

@end

// MARK: - WKHistoryDelegatePrivate Protocol

/// Private delegate for tracking navigation history events.
///
/// This protocol provides callbacks for history-related events that aren't
/// available through the public `WKNavigationDelegate`:
/// - Title updates after initial page load
/// - Client-side redirects (JavaScript `location.href` changes)
/// - Server-side redirects with both source and destination URLs
/// - Safe Browsing warnings (requires SafariSafeBrowsing.framework)
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/WKHistoryDelegatePrivate.h
///
/// ## Why This Exists
/// The public `WKNavigationDelegate` only provides the title at page load
/// completion. Many modern web apps update the title via JavaScript after
/// the initial load (e.g., email clients showing unread count).
/// This delegate provides `_webView:didUpdateHistoryTitle:forURL:` to
/// track those changes.
///
/// ## Setup
/// ```swift
/// // Set on WKWebView
/// webView._setHistoryDelegate(self)
/// ```
///
/// ## Availability
/// macOS 10.10+
@protocol WKHistoryDelegatePrivate <NSObject>
@optional

/// Called when a navigation completes with navigation data.
///
/// Use this to add entries to your browser's history.
///
/// @param webView The web view that navigated.
/// @param navigationData Details about the navigation.
- (void)_webView:(WKWebView *)webView
    didNavigateWithNavigationData:(WKNavigationData *)navigationData;

/// Called when a client-side redirect occurs.
///
/// Client-side redirects are caused by JavaScript (e.g., `location.href = "..."`),
/// `<meta http-equiv="refresh">`, or History API navigation.
///
/// @param webView The web view that redirected.
/// @param sourceURL The URL before the redirect.
/// @param destinationURL The URL after the redirect.
- (void)_webView:(WKWebView *)webView
    didPerformClientRedirectFromURL:(NSURL *)sourceURL
                              toURL:(NSURL *)destinationURL;

/// Called when a server-side redirect occurs.
///
/// Server-side redirects are HTTP 301, 302, 303, 307, or 308 responses.
///
/// @param webView The web view that redirected.
/// @param sourceURL The URL before the redirect.
/// @param destinationURL The URL after the redirect.
- (void)_webView:(WKWebView *)webView
    didPerformServerRedirectFromURL:(NSURL *)sourceURL
                              toURL:(NSURL *)destinationURL;

/// Called when the page title changes.
///
/// ## Important
/// This is called when the title changes AFTER initial page load, typically
/// via JavaScript `document.title = "..."`. The initial title is available
/// through `WKNavigationDelegate.webView:didFinishNavigation:` and
/// `webView.title`.
///
/// ## Use Case
/// Update your history database when SPAs (Single Page Apps) change their
/// title without full navigation. For example:
/// - Email clients: "Inbox (3)" → "Inbox (5)"
/// - Chat apps: Update with new message previews
/// - Music players: Show current track
///
/// @param webView The web view whose title changed.
/// @param title The new title.
/// @param URL The URL of the page (may differ from webView.URL for frames).
- (void)_webView:(WKWebView *)webView
    didUpdateHistoryTitle:(NSString *)title
                   forURL:(NSURL *)URL;

/// Called when Safe Browsing completes a lookup for a URL.
///
/// ## Requires
/// SafariSafeBrowsing.framework must be linked and available.
/// The `SSBLookupResult` class is from that framework.
///
/// ## Note
/// This is called for every navigation. The result indicates whether
/// the URL is flagged as malicious, phishing, etc.
///
/// @param webView The web view that navigated.
/// @param result The Safe Browsing lookup result.
/// @param URL The URL that was checked.
- (void)_webView:(WKWebView *)webView
    didReceiveSafeBrowsingResult:(SSBLookupResult *)result
                          forURL:(NSURL *)URL;

/// Called to check for a cached Safe Browsing result.
///
/// Implement this to provide cached Safe Browsing results to avoid
/// redundant network lookups.
///
/// @param webView The web view requesting the result.
/// @param URL The URL to check.
/// @param completionHandler Call with the cached result, or nil if not cached.
- (void)_webView:(WKWebView *)webView
    cachedSafeBrowsingResultForURL:(NSURL *)URL
                 completionHandler:(void (^)(SSBLookupResult * _Nullable, NSError * _Nullable error))completionHandler;

@end

// MARK: - NSImmediateActionGestureRecognizer Forward Declarations

/// Forward declare the protocols before they're used.
@protocol NSImmediateActionGestureRecognizerDelegate;
@protocol NSImmediateActionAnimationController;

// MARK: - NSImmediateActionGestureRecognizer

/// A gesture recognizer for Force Touch / Immediate Action gestures.
///
/// This gesture recognizer is used internally by WebKit to handle Force Touch
/// previews on supported trackpads. It triggers the link preview animation
/// when the user force-clicks on a link.
///
/// ## Source
/// WebKit/Source/WebCore/PAL/pal/spi/mac/NSImmediateActionGestureRecognizerSPI.h
///
/// ## Usage
/// The gesture recognizer is automatically installed on WKWebView when
/// `allowsLinkPreview` is enabled. For programmatic triggering, you can
/// access it via reflection or simulate its behavior.
///
/// ## Note
/// This is an Apple private class. It may not be available on all systems.
@interface NSImmediateActionGestureRecognizer : NSGestureRecognizer

// Note: The delegate property is inherited from NSGestureRecognizer.
// When working with this class, cast the delegate to id<NSImmediateActionGestureRecognizerDelegate>
// to access immediate action-specific delegate methods.

/// The animation controller for the current immediate action.
///
/// Set by the delegate during `willBeginAnimation:` to provide the
/// preview content. Can be:
/// - QLPreviewMenuItem for link previews
/// - NSPopover-based controller for dictionary lookups
/// - Custom animation controller
@property (strong, nullable) id<NSImmediateActionAnimationController> animationController;

/// The current progress of the immediate action animation (0.0 to 1.0).
///
/// - 0.0: Animation not started
/// - 0.5: Halfway through the reveal
/// - 1.0: Fully revealed
///
/// This value corresponds to Force Touch pressure levels.
@property (readonly) CGFloat animationProgress;

/// Whether the primary mouse button events should be delayed.
///
/// When `YES`, mouse down events are delayed to allow the gesture
/// recognizer to determine if this is an immediate action gesture.
/// Default is `YES` for Force Touch trackpads.
@property BOOL delaysPrimaryMouseButtonEvents;

@end

// MARK: - NSImmediateActionGestureRecognizerDelegate

/// Delegate protocol for handling immediate action gesture events.
///
/// Implement this protocol to receive callbacks during Force Touch / immediate
/// action gestures. The delegate is responsible for:
/// 1. Performing hit tests when the gesture begins
/// 2. Providing an animation controller with the preview content
/// 3. Handling animation state changes
///
/// ## Source
/// WebKit/Source/WebCore/PAL/pal/spi/mac/NSImmediateActionGestureRecognizerSPI.h
@protocol NSImmediateActionGestureRecognizerDelegate <NSGestureRecognizerDelegate>
@optional

/// Called when the gesture recognizer is preparing for an immediate action.
///
/// This is the time to perform hit testing at the gesture location.
/// The delegate should:
/// 1. Determine what content is at the gesture location
/// 2. Prepare the animation controller based on the content type
/// 3. Set `recognizer.animationController` to the appropriate controller
///
/// ## Timing
/// Called when Force Touch pressure is detected but before the threshold
/// for triggering the preview is reached.
- (void)immediateActionRecognizerWillPrepare:(NSImmediateActionGestureRecognizer *)immediateActionRecognizer;

/// Called when the immediate action animation is about to begin.
///
/// At this point, the user has applied enough pressure to trigger the preview.
/// The animation controller should be fully configured.
///
/// ## Timing
/// Called when Force Touch pressure exceeds the activation threshold.
- (void)immediateActionRecognizerWillBeginAnimation:(NSImmediateActionGestureRecognizer *)immediateActionRecognizer;

/// Called when the animation progress changes.
///
/// Use `immediateActionRecognizer.animationProgress` to get the current
/// progress (0.0 to 1.0) and update visual feedback accordingly.
///
/// ## Timing
/// Called continuously as the user varies Force Touch pressure.
- (void)immediateActionRecognizerDidUpdateAnimation:(NSImmediateActionGestureRecognizer *)immediateActionRecognizer;

/// Called when the immediate action was cancelled.
///
/// This occurs when:
/// - User lifts finger before completing the gesture
/// - User moves finger outside the valid area
/// - System interrupts the gesture
///
/// Clean up any preview state and restore normal appearance.
- (void)immediateActionRecognizerDidCancelAnimation:(NSImmediateActionGestureRecognizer *)immediateActionRecognizer;

/// Called when the immediate action animation completed successfully.
///
/// The preview is now fully displayed. The animation controller takes
/// over handling of the preview content.
- (void)immediateActionRecognizerDidCompleteAnimation:(NSImmediateActionGestureRecognizer *)immediateActionRecognizer;

@end

// MARK: - NSImmediateActionAnimationController

/// Protocol for objects that control immediate action animations.
///
/// Animation controllers receive callbacks during the immediate action
/// lifecycle and are responsible for displaying preview content.
///
/// Common implementations:
/// - QLPreviewMenuItem: Quick Look preview for links
/// - NSPopover: Dictionary lookup popover
/// - Custom preview controllers
///
/// ## Source
/// WebKit/Source/WebCore/PAL/pal/spi/mac/NSImmediateActionGestureRecognizerSPI.h
@protocol NSImmediateActionAnimationController <NSObject>
@optional

/// Called when the animation is about to begin.
- (void)recognizerWillBeginAnimation:(NSImmediateActionGestureRecognizer *)recognizer;

/// Called when the animation progress changes.
- (void)recognizerDidUpdateAnimation:(NSImmediateActionGestureRecognizer *)recognizer;

/// Called when the animation was cancelled.
- (void)recognizerDidCancelAnimation:(NSImmediateActionGestureRecognizer *)recognizer;

/// Called when the animation completed successfully.
- (void)recognizerDidCompleteAnimation:(NSImmediateActionGestureRecognizer *)recognizer;

/// Called when the preview is dismissed.
- (void)recognizerDidDismissAnimation:(NSImmediateActionGestureRecognizer *)recognizer;

@end

// MARK: - WKWebView Private Extensions

/// Private WKWebView methods for browser functionality.
///
/// These methods extend WKWebView with capabilities needed for building
/// a full-featured web browser.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebViewPrivate.h
@interface WKWebView (WKPrivate)

// MARK: Audio State

/// Whether the web view is currently playing audio.
///
/// This property is KVO-compliant. Observe changes to update UI
/// (e.g., showing a speaker icon in the tab).
///
/// ## Key Path
/// Uses private `_isPlayingAudio` property internally.
///
/// ## Availability
/// macOS 10.13.4+
@property (nonatomic, readonly, getter=_isPlayingAudio) BOOL _playingAudio API_AVAILABLE(macos(10.13.4));

/// The current media mute state.
///
/// Returns a bitmask of `_WKMediaMutedState` values indicating which
/// media types are currently muted.
///
/// ## Availability
/// macOS 11.0+
@property (nonatomic, readonly) _WKMediaMutedState _mediaMutedState API_AVAILABLE(macos(11.0));

/// Sets the media mute state.
///
/// @param mutedState A bitmask of `_WKMediaMutedState` values.
///
/// ## Example
/// ```objc
/// // Mute audio only
/// [webView _setPageMuted:_WKMediaAudioMuted];
///
/// // Unmute everything
/// [webView _setPageMuted:_WKMediaNoneMuted];
/// ```
///
/// ## Note
/// This method does NOT trigger KVO notifications for `_mediaMutedState`.
/// Call your observer's refresh method manually after setting.
///
/// ## Availability
/// macOS 10.13+
- (void)_setPageMuted:(_WKMediaMutedState)mutedState API_AVAILABLE(macos(10.13));

// MARK: Web Inspector

/// The Web Inspector instance for this web view.
///
/// Access this property to show, hide, or configure the Web Inspector.
/// The inspector is lazily created on first access.
///
/// ## Availability
/// macOS 10.14.4+
@property (nonatomic, readonly, nullable) _WKInspector *_inspector API_AVAILABLE(macos(10.14.4));

// MARK: Immediate Action (Link Preview)

/// Provides a custom animation controller for immediate action gestures.
///
/// Called by WebKit when the user performs a Force Touch gesture on content.
/// Return values:
/// - `nil`: Use WebKit's default preview behavior
/// - `NSNull`: Disable immediate action for this content
/// - Custom controller: Use your own preview implementation
///
/// @param hitTestResult Information about the element under the gesture
/// @param type The type of immediate action detected
/// @param userData Additional data from the web content
/// @return An animation controller, NSNull, or nil
///
/// ## Example
/// ```objc
/// - (id)_immediateActionAnimationControllerForHitTestResult:(_WKHitTestResult *)hitTestResult
///                                                 withType:(_WKImmediateActionType)type
///                                                 userData:(id<NSSecureCoding>)userData {
///     if (type == _WKImmediateActionLinkPreview) {
///         // Use custom link preview
///         return [MyCustomPreviewController controllerForURL:hitTestResult.absoluteLinkURL];
///     }
///     return nil; // Use default behavior
/// }
/// ```
///
/// ## Availability
/// macOS 10.12+
- (nullable id)_immediateActionAnimationControllerForHitTestResult:(_WKHitTestResult *)hitTestResult
                                                          withType:(_WKImmediateActionType)type
                                                          userData:(nullable id<NSSecureCoding>)userData API_AVAILABLE(macos(10.12));

// MARK: Display Capture (Screen Sharing)

/// The current display capture state.
///
/// Returns the state of screen/window sharing for this web view.
/// Used to determine if getDisplayMedia() is active.
///
/// ## Availability
/// macOS 13.0+
@property (nonatomic, readonly) WKDisplayCaptureState _displayCaptureState API_AVAILABLE(macos(13.0));

/// Sets the display capture state.
///
/// Use this to mute/unmute screen sharing audio. When a web app initiates
/// screen capture, the audio is muted by default. Call this to enable audio.
///
/// @param state The desired display capture state
/// @param completionHandler Called when the state change is complete
///
/// ## Example
/// ```objc
/// // Enable audio during screen sharing
/// [webView _setDisplayCaptureState:WKDisplayCaptureStateActive completionHandler:^{
///     NSLog(@"Screen sharing audio enabled");
/// }];
///
/// // Mute screen sharing audio
/// [webView _setDisplayCaptureState:WKDisplayCaptureStateMuted completionHandler:nil];
/// ```
///
/// ## Availability
/// macOS 13.0+
- (void)_setDisplayCaptureState:(WKDisplayCaptureState)state
              completionHandler:(nullable void (^)(void))completionHandler API_AVAILABLE(macos(13.0));

/// The current system audio capture state.
///
/// Returns the state of system audio capture (tab audio sharing).
///
/// ## Availability
/// macOS 13.0+
@property (nonatomic, readonly) WKSystemAudioCaptureState _systemAudioCaptureState API_AVAILABLE(macos(13.0));

/// Sets the system audio capture state.
///
/// @param state The desired system audio capture state
/// @param completionHandler Called when the state change is complete
///
/// ## Availability
/// macOS 13.0+
- (void)_setSystemAudioCaptureState:(WKSystemAudioCaptureState)state
                  completionHandler:(nullable void (^)(void))completionHandler API_AVAILABLE(macos(13.0));

// MARK: Media Capture (Camera/Microphone)

/// The deprecated media capture state.
///
/// Use `_mediaMutedState` instead for newer APIs.
///
/// ## Availability
/// macOS 10.15+
@property (nonatomic, readonly) _WKMediaCaptureStateDeprecated _mediaCaptureState API_AVAILABLE(macos(10.15));

/// Whether media capture is enabled for this web view.
///
/// When `NO`, getUserMedia() will be denied.
///
/// ## Availability
/// macOS 10.13+
@property (nonatomic, setter=_setMediaCaptureEnabled:) BOOL _mediaCaptureEnabled API_AVAILABLE(macos(10.13));

/// Stops all active media capture (camera, microphone, screen).
///
/// ## Availability
/// macOS 10.15.4+
- (void)_stopMediaCapture API_AVAILABLE(macos(10.15.4));

// MARK: Media Playback Control

/// Whether the web view can toggle Picture-in-Picture mode.
@property (nonatomic, readonly) BOOL _canTogglePictureInPicture;

/// Whether Picture-in-Picture is currently active.
@property (nonatomic, readonly) BOOL _isPictureInPictureActive;

/// Toggles Picture-in-Picture mode for the current video.
- (void)_togglePictureInPicture;

/// Stops all media playback in the web view.
- (void)_stopAllMediaPlayback;

/// Suspends all media playback (can be resumed).
- (void)_suspendAllMediaPlayback;

/// Resumes all previously suspended media playback.
- (void)_resumeAllMediaPlayback;

/// Closes all media presentations (PiP, fullscreen video, etc.).
- (void)_closeAllMediaPresentations;

/// Gets the title and artist of the currently playing media.
///
/// Useful for displaying Now Playing information.
///
/// @param completionHandler Called with title and artist (may be nil)
- (void)_nowPlayingMediaTitleAndArtist:(void (^)(NSString * _Nullable title, NSString * _Nullable artist))completionHandler;

// MARK: Fullscreen

/// Whether the web view is currently in fullscreen mode.
///
/// ## Availability
/// macOS 10.12.4+
@property (nonatomic, readonly) BOOL _isInFullscreen API_AVAILABLE(macos(10.12.4));

/// Whether the web view can enter fullscreen mode.
///
/// ## Availability
/// macOS 15.0+
@property (nonatomic, readonly) BOOL _canEnterFullscreen API_AVAILABLE(macos(15.0));

/// Programmatically enters fullscreen mode.
///
/// ## Availability
/// macOS 15.0+
- (void)_enterFullscreen API_AVAILABLE(macos(15.0));

// MARK: Page State

/// Whether the web view is currently suspended (backgrounded).
@property (nonatomic, readonly) BOOL _isSuspended;

/// The sampled color from the top of the page.
///
/// Useful for matching browser UI to page content.
///
/// ## Availability
/// macOS 12.0+
@property (nonatomic, readonly, nullable) NSColor *_sampledPageTopColor API_AVAILABLE(macos(12.0));

// MARK: PDF Support

/// Takes a PDF snapshot of the web view content.
///
/// @param snapshotConfiguration Configuration for the snapshot
/// @param completionHandler Called with PDF data or error
///
/// ## Availability
/// macOS 10.15.4+
- (void)_takePDFSnapshotWithConfiguration:(nullable WKSnapshotConfiguration *)snapshotConfiguration
                        completionHandler:(void (^)(NSData * _Nullable pdfData, NSError * _Nullable error))completionHandler API_AVAILABLE(macos(10.15.4));

// MARK: Connection Preloading

/// Preconnects to a server for faster subsequent requests.
///
/// This establishes a connection (including TLS handshake) to the server
/// before a request is made, reducing latency for the first request.
///
/// @param serverURL The URL of the server to preconnect to
///
/// ## Availability
/// macOS 11.0+
- (void)_preconnectToServer:(NSURL *)serverURL API_AVAILABLE(macos(11.0));

// MARK: - Reload Variants

/// Reloads the page bypassing content blockers.
///
/// Use this when the user wants to temporarily disable content blocking
/// for a specific site. Common use cases:
/// - Site broken by ad blocker
/// - User wants to see blocked content
/// - Debugging content blocker rules
///
/// ## Implementation Note
/// This reload does NOT permanently disable content blockers. The next
/// navigation will apply content blockers normally.
///
/// ## Availability
/// macOS 10.12+
- (nullable WKNavigation *)_reloadWithoutContentBlockers API_AVAILABLE(macos(10.12));

/// Reloads only if cached resources have expired.
///
/// More efficient than a full reload - only fetches resources whose
/// cache headers indicate they're stale. Useful for:
/// - Checking for updates without full reload
/// - Implementing "soft refresh" functionality
///
/// ## Cache Behavior
/// - Resources with valid `Cache-Control` or `Expires` headers that haven't
///   expired are not re-fetched
/// - The main document is always checked (conditional GET)
/// - Resources without cache headers are re-fetched
///
/// ## Availability
/// macOS 10.13+
- (nullable WKNavigation *)_reloadExpiredOnly API_AVAILABLE(macos(10.13));

// MARK: - Web Process State

/// The current state of the web process.
///
/// Use this to track whether a tab is loaded, suspended, or has crashed.
/// This is essential for:
/// - Showing "unloaded" indicators on suspended tabs
/// - Detecting crashed tabs that need recovery
/// - Understanding memory usage across tabs
///
/// ## KVO Compliance
/// This property is KVO-compliant. Register an observer to receive
/// state change notifications:
/// ```swift
/// webView.addObserver(self, forKeyPath: "_webProcessState", options: [.new], context: nil)
/// ```
///
/// ## Important
/// WebKit only sends KVO notifications when observers are registered.
/// If no observers exist, state changes are not broadcast.
///
/// ## Availability
/// macOS 15.4+
@property (nonatomic, readonly) _WKWebProcessState _webProcessState API_AVAILABLE(macos(15.4));

// MARK: - Tab/Page Lifecycle

/// Closes the web view and releases resources.
///
/// Call this when permanently closing a tab. This:
/// - Terminates the web process
/// - Releases all resources
/// - Invalidates all pending loads
///
/// After calling this, the web view cannot be reused.
- (void)_close;

/// Attempts to close the web view gracefully.
///
/// Unlike `_close`, this method checks if the page has unsaved changes
/// (via `beforeunload` event) and may prevent closing.
///
/// @return `YES` if the close was initiated, `NO` if prevented
///
/// ## Use Case
/// Use this for user-initiated tab close requests where you want to
/// respect the page's `beforeunload` handler.
///
/// ## Availability
/// macOS 10.15.4+
- (BOOL)_tryClose API_AVAILABLE(macos(10.15.4));

/// Whether the web view has been closed.
///
/// @return `YES` if `_close` or a successful `_tryClose` was called
///
/// ## Availability
/// macOS 10.15.4+
- (BOOL)_isClosed API_AVAILABLE(macos(10.15.4));

// MARK: - Document Type Detection

/// Whether the web view is displaying a PDF document.
///
/// `YES` when the main frame is showing a PDF file.
/// Useful for showing PDF-specific toolbar controls.
///
/// ## Availability
/// macOS 15.0+
@property (nonatomic, readonly, getter=_isDisplayingPDF) BOOL _displayingPDF API_AVAILABLE(macos(15.0));

/// Whether the web view is displaying a standalone image.
///
/// `YES` when navigated directly to an image file (not HTML with images).
/// Useful for showing image-specific controls (zoom, rotate, save).
@property (nonatomic, readonly, getter=_isDisplayingStandaloneImageDocument) BOOL _displayingStandaloneImageDocument;

// MARK: - In-Window Video Viewer (Safari-style)

/// Whether the in-window video viewer is currently active.
///
/// The in-window viewer is Safari's alternative to true fullscreen,
/// where video fills the web view area but the browser chrome remains
/// visible. This provides a less immersive but more accessible experience.
@property (nonatomic, readonly) BOOL _isInWindowActive;

/// Toggles the in-window video viewer.
///
/// If a video is playing, this switches between normal and in-window mode.
/// If no video is playing, this has no effect.
- (void)_toggleInWindow;

/// Enters in-window video viewer mode.
///
/// Expands the current video to fill the web view while keeping
/// browser chrome visible. Unlike true fullscreen, this:
/// - Doesn't hide the dock/menu bar
/// - Doesn't create a separate fullscreen space
/// - Allows tab switching while video plays
- (void)_enterInWindow;

/// Exits in-window video viewer mode.
///
/// Returns the video to its original inline position.
- (void)_exitInWindow;

// MARK: - Media Session Control

/// Plays the predominant media session or resumes Now Playing.
///
/// This is the programmatic equivalent of pressing play on a media session.
/// It will:
/// 1. Resume paused media if any
/// 2. Start the predominant video/audio if multiple exist
/// 3. Activate Now Playing if registered
///
/// @param completionHandler Called with `YES` if playback started
///
/// ## Availability
/// macOS 15.0+
- (void)_playPredominantOrNowPlayingMediaSession:(void(^)(BOOL success))completionHandler API_AVAILABLE(macos(15.0));

/// Pauses the current Now Playing media session.
///
/// @param completionHandler Called with `YES` if playback was paused
///
/// ## Availability
/// macOS 15.0+
- (void)_pauseNowPlayingMediaSession:(void(^)(BOOL success))completionHandler API_AVAILABLE(macos(15.0));

// MARK: - Image Analysis (Visual Lookup / Live Text)

/// Starts image analysis for Visual Lookup / Live Text.
///
/// Triggers Apple's image analysis framework on an element, enabling:
/// - Live Text (selectable text in images)
/// - Visual Lookup (identify objects, plants, pets, landmarks)
/// - Subject lifting (copy subject from photo)
///
/// ## Parameters
/// @param identifier The identifier for the analysis request
/// @param targetIdentifier The target element identifier to analyze
///
/// ## Context Menu Integration
/// This is typically triggered from a context menu when right-clicking
/// an image. WebKit provides a default "Look Up" menu item that calls this.
///
/// ## Availability
/// macOS 13.0+
- (void)_startImageAnalysis:(NSString *)identifier target:(NSString *)targetIdentifier API_AVAILABLE(macos(13.0));

// MARK: - Content Insets

/// The top content inset for the web view.
///
/// Use this to offset web content below browser UI elements like toolbars.
/// The inset creates space at the top where the page content won't render.
@property (nonatomic, setter=_setTopContentInset:) CGFloat _topContentInset;

/// Sets the top content inset with optional immediate application.
///
/// @param topContentInset The inset value in points
/// @param immediate If YES, applies instantly without animation
///
/// ## When to Use `immediate:YES`
/// - During resize operations
/// - When showing/hiding toolbars instantly
/// - To avoid visual glitches during rapid layout changes
///
/// ## Availability
/// macOS 15.4+
- (void)_setTopContentInset:(CGFloat)topContentInset immediate:(BOOL)immediate API_AVAILABLE(macos(15.4));

/// The obscured content insets from all edges.
///
/// Unlike `_topContentInset` which only handles the top, this property
/// handles insets from all four edges. Use this when you have:
/// - Floating toolbars at the bottom
/// - Side panels overlapping content
/// - Non-rectangular safe areas
///
/// ## Availability
/// macOS 26.0+ (Tahoe)
@property (nonatomic, readonly) NSEdgeInsets _obscuredContentInsets API_AVAILABLE(macos(26.0));

/// Sets obscured content insets with optional immediate application.
///
/// @param insets The edge insets to apply
/// @param immediate If YES, applies instantly without animation
///
/// ## Implementation Details (from WebKit cpp)
/// This calls `WebPageProxy::setObscuredInsets()` which:
/// 1. Notifies the web process of the new insets
/// 2. Updates layout constraints
/// 3. Adjusts fixed position elements
/// 4. Triggers a compositing update if needed
///
/// ## Availability
/// macOS 26.0+ (Tahoe)
- (void)_setObscuredContentInsets:(NSEdgeInsets)insets immediate:(BOOL)immediate API_AVAILABLE(macos(26.0));

/// Whether automatic background fill for content insets is enabled.
///
/// When YES, WebKit automatically fills the inset areas with an appropriate
/// background color (typically the page's background color or theme color).
///
/// ## Availability
/// macOS 26.0+ (Tahoe)
@property (nonatomic, setter=_setUsesAutomaticContentInsetBackgroundFill:) BOOL _usesAutomaticContentInsetBackgroundFill API_AVAILABLE(macos(26.0));

/// Override color for the top scroll edge effect.
///
/// In macOS 26.0 (Tahoe) with Liquid Glass design, scroll views have
/// edge effects. Set this to customize the color shown at the top edge
/// when content is scrolled.
///
/// ## Liquid Glass Integration
/// This color is used in the rubber-band effect and the scroll pocket
/// background when overscrolling at the top.
///
/// ## Availability
/// macOS 26.0+ (Tahoe)
@property (nonatomic, copy, setter=_setOverrideTopScrollEdgeEffectColor:, nullable) NSColor *_overrideTopScrollEdgeEffectColor API_AVAILABLE(macos(26.0));

/// The top scroll pocket view.
///
/// In macOS 26.0 (Tahoe), `NSScrollPocket` is a new view type that
/// provides the "Liquid Glass" visual effect for toolbar areas that
/// scroll with content. This property gives access to the web view's
/// top scroll pocket for customization.
///
/// ## What is NSScrollPocket?
/// A scroll pocket is the area behind a transparent toolbar that shows
/// blurred, tinted content as the page scrolls underneath. It's part of
/// Apple's new "Liquid Glass" design language.
///
/// ## Usage
/// Access this to customize the pocket's appearance or to coordinate
/// animations with the pocket's state.
///
/// ## Availability
/// macOS 26.0+ (Tahoe)
@property (nonatomic, readonly, nullable) NSScrollPocket *_topScrollPocket API_AVAILABLE(macos(26.0));

// MARK: - Delegates

/// The history delegate for navigation history events.
///
/// Set this to receive callbacks for title changes, redirects, and
/// Safe Browsing results.
@property (nonatomic, weak, setter=_setHistoryDelegate:, nullable) id<WKHistoryDelegatePrivate> _historyDelegate;

/// The icon loading delegate for favicon notifications.
///
/// Set this to receive callbacks when the page declares favicon links.
@property (nonatomic, weak, setter=_setIconLoadingDelegate:, nullable) id<_WKIconLoadingDelegate> _iconLoadingDelegate;

// MARK: - Presentation Updates

/// Executes a block after the next presentation update completes.
///
/// Use this to ensure the web view has finished rendering before taking
/// snapshots or performing other operations that require accurate visual state.
///
/// @param updateBlock The block to execute after the presentation update.
///
/// ## Use Cases
/// - Taking accurate screenshots after navigation
/// - Capturing thumbnails for tab previews
/// - Synchronizing UI updates with web content changes
///
/// ## Availability
/// macOS 10.12+
- (void)_doAfterNextPresentationUpdate:(void (^)(void))updateBlock API_AVAILABLE(macos(10.12));

@end

// MARK: - WKUIDelegatePrivate Protocol

/// Private UI delegate methods for advanced browser functionality.
///
/// Implement this protocol on your WKUIDelegate to receive callbacks for
/// private WebKit functionality.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/WKUIDelegatePrivate.h
///
/// ## Note
/// Methods in this protocol are optional and may not be called if the
/// delegate does not respond to them.
@protocol WKUIDelegatePrivate <WKUIDelegate>
@optional

// MARK: Context Menu

/// Called to customize the context menu before it is displayed.
///
/// This method allows you to modify, replace, or extend the default
/// context menu that WebKit provides. You receive:
/// - The proposed menu with WebKit's default items
/// - Information about what the user right-clicked on
/// - Optional user data from web content
///
/// Call the completion handler with:
/// - The modified menu to display
/// - `nil` to cancel the context menu entirely
///
/// @param webView The web view requesting the context menu
/// @param menu The proposed menu with default items
/// @param element Information about the clicked element
/// @param userInfo Optional data from web content
/// @param completionHandler Call with the final menu (or nil to cancel)
///
/// ## Example
/// ```objc
/// - (void)_webView:(WKWebView *)webView
///     getContextMenuFromProposedMenu:(NSMenu *)menu
///                         forElement:(_WKContextMenuElementInfo *)element
///                           userInfo:(id<NSSecureCoding>)userInfo
///                  completionHandler:(void (^)(NSMenu *))completionHandler {
///
///     _WKHitTestResult *hitTest = element.hitTestResult;
///     NSMutableArray *newItems = [NSMutableArray arrayWithArray:menu.itemArray];
///
///     // Add custom item for links
///     if (hitTest.absoluteLinkURL) {
///         NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Open in New Tab"
///                                                       action:@selector(openInNewTab:)
///                                                keyEquivalent:@""];
///         item.representedObject = hitTest.absoluteLinkURL;
///         [newItems insertObject:item atIndex:0];
///         [newItems insertObject:[NSMenuItem separatorItem] atIndex:1];
///     }
///
///     NSMenu *customMenu = [[NSMenu alloc] init];
///     [customMenu setItemArray:newItems];
///     completionHandler(customMenu);
/// }
/// ```
///
/// ## Availability
/// macOS 10.14+
- (void)_webView:(WKWebView *)webView
    getContextMenuFromProposedMenu:(NSMenu *)menu
                        forElement:(_WKContextMenuElementInfo *)element
                          userInfo:(nullable id<NSSecureCoding>)userInfo
                 completionHandler:(void (^)(NSMenu * _Nullable))completionHandler API_AVAILABLE(macos(10.14));

// MARK: Immediate Action (Link Preview) Delegates

/// Called before immediate action animation begins.
///
/// Use this to prepare your UI for the preview animation.
/// For example, you might want to highlight the link being previewed.
///
/// ## Availability
/// macOS 10.13.4+
- (void)_prepareForImmediateActionAnimationForWebView:(WKWebView *)webView API_AVAILABLE(macos(10.13.4));

/// Called when immediate action animation is cancelled.
///
/// Clean up any UI state that was set during `_prepareForImmediateActionAnimationForWebView:`.
///
/// ## Availability
/// macOS 10.13.4+
- (void)_cancelImmediateActionAnimationForWebView:(WKWebView *)webView API_AVAILABLE(macos(10.13.4));

/// Called when immediate action animation completes.
///
/// The preview is now fully displayed. You can update UI state accordingly.
///
/// ## Availability
/// macOS 10.13.4+
- (void)_completeImmediateActionAnimationForWebView:(WKWebView *)webView API_AVAILABLE(macos(10.13.4));

// MARK: Mouse Tracking

/// Called when the mouse moves over an element.
///
/// This method provides live hit test information as the mouse moves.
/// Useful for:
/// - Updating status bar with link URLs
/// - Showing custom tooltips
/// - Tracking mouse position for analytics
///
/// @param webView The web view receiving the mouse event
/// @param hitTestResult Information about the element under the mouse
/// @param flags Keyboard modifier flags (Shift, Control, etc.)
/// @param userInfo Optional data from web content
///
/// ## Availability
/// macOS 10.12+
- (void)_webView:(WKWebView *)webView
    mouseDidMoveOverElement:(_WKHitTestResult *)hitTestResult
                  withFlags:(NSEventModifierFlags)flags
                   userInfo:(nullable id<NSSecureCoding>)userInfo API_AVAILABLE(macos(10.12));

// MARK: Download Handling

/// Called when a context menu action creates a download.
///
/// This private method is called when the user selects "Download Linked File"
/// or similar options from the context menu.
///
/// @param webView The web view that initiated the download
/// @param download The download object to configure
///
/// ## Note
/// You must set a delegate on the download to provide a destination URL.
/// Without a delegate, the download will fail with a sandbox error.
///
/// ## Selector
/// `_webView:contextMenuDidCreateDownload:`
- (void)_webView:(WKWebView *)webView contextMenuDidCreateDownload:(WKDownload *)download;

// MARK: Fullscreen Events

/// Called when the web view is about to enter fullscreen.
///
/// ## Availability
/// macOS 26.0+
- (void)_webViewWillEnterFullscreen:(WKWebView *)webView API_AVAILABLE(macos(26.0));

/// Called when the web view has entered fullscreen.
///
/// ## Availability
/// macOS 10.11+
- (void)_webViewDidEnterFullscreen:(WKWebView *)webView API_AVAILABLE(macos(10.11));

/// Called when the web view has exited fullscreen.
///
/// ## Availability
/// macOS 10.11+
- (void)_webViewDidExitFullscreen:(WKWebView *)webView API_AVAILABLE(macos(10.11));

/// Called when fullscreen may return to inline (PiP transition).
- (void)_webViewFullscreenMayReturnToInline:(WKWebView *)webView;

// MARK: Picture-in-Picture

/// Called when the web view's PiP state changes.
///
/// @param hasVideoInPictureInPicture YES if video is now in PiP mode
- (void)_webView:(WKWebView *)webView hasVideoInPictureInPictureDidChange:(BOOL)hasVideoInPictureInPicture API_AVAILABLE(macos(10.13));

// MARK: Autoplay Events

/// Called when an autoplay event occurs.
///
/// Use this to track autoplay behavior and show UI when autoplay is blocked.
///
/// @param webView The web view
/// @param event The type of autoplay event
/// @param flags Additional context about the event
///
/// ## Availability
/// macOS 10.13.4+
- (void)_webView:(WKWebView *)webView handleAutoplayEvent:(_WKAutoplayEvent)event withFlags:(_WKAutoplayEventFlags)flags API_AVAILABLE(macos(10.13.4));

// MARK: Media Capture Permission

/// Called when a page requests media capture permission.
///
/// @param webView The web view
/// @param devices The types of devices requested (camera, microphone, display)
/// @param url The URL of the requesting page
/// @param mainFrameURL The URL of the main frame
/// @param decisionHandler Call with YES to allow, NO to deny
///
/// ## Availability
/// macOS 10.13+
- (void)_webView:(WKWebView *)webView
    requestUserMediaAuthorizationForDevices:(_WKCaptureDevices)devices
                                        url:(NSURL *)url
                               mainFrameURL:(NSURL *)mainFrameURL
                            decisionHandler:(void (^)(BOOL authorized))decisionHandler API_AVAILABLE(macos(10.13));

// MARK: Window Management

/// Called when the web view wants to close.
- (void)_webViewClose:(WKWebView *)webView;

/// Called to show the web view window.
- (void)_showWebView:(WKWebView *)webView API_AVAILABLE(macos(10.13.4));

/// Called to focus the web view.
- (void)_focusWebView:(WKWebView *)webView API_AVAILABLE(macos(10.13.4));

/// Called to unfocus the web view.
- (void)_unfocusWebView:(WKWebView *)webView API_AVAILABLE(macos(10.13.4));

/// Called when the web view scrolls.
- (void)_webViewDidScroll:(WKWebView *)webView API_AVAILABLE(macos(10.13.4));

/// Called to get the window frame.
- (void)_webView:(WKWebView *)webView getWindowFrameWithCompletionHandler:(void (^)(CGRect))completionHandler API_AVAILABLE(macos(10.13.4));

/// Called to set the window frame.
- (void)_webView:(WKWebView *)webView setWindowFrame:(CGRect)frame API_AVAILABLE(macos(10.13.4));

/// Called to set whether the window is resizable.
- (void)_webView:(WKWebView *)webView setResizable:(BOOL)isResizable API_AVAILABLE(macos(10.13.4));

// MARK: File Saving

/// Called when the web view wants to save data to a file.
///
/// Implement this to show a save panel for downloads.
///
/// @param webView The web view
/// @param data The data to save
/// @param suggestedFilename A suggested filename
/// @param mimeType The MIME type of the data
/// @param url The originating URL
- (void)_webView:(WKWebView *)webView
    saveDataToFile:(NSData *)data
    suggestedFilename:(NSString *)suggestedFilename
            mimeType:(NSString *)mimeType
      originatingURL:(NSURL *)url API_AVAILABLE(macos(10.13.4));

// MARK: Web Inspector

/// Called when a local Web Inspector is attached.
- (void)_webView:(WKWebView *)webView didAttachLocalInspector:(_WKInspector *)inspector API_AVAILABLE(macos(12.0));

/// Called before a local Web Inspector is closed.
- (void)_webView:(WKWebView *)webView willCloseLocalInspector:(_WKInspector *)inspector API_AVAILABLE(macos(12.0));

@end

// MARK: - _WKInspector

/// The Web Inspector controller for a WKWebView.
///
/// This class provides programmatic control over the Web Inspector,
/// allowing you to show, hide, and configure it.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKInspector.h
///
/// ## Note
/// The inspector must be enabled via `WKPreferences.developerExtrasEnabled`
/// before it can be shown.
API_AVAILABLE(macos(10.14.4))
@interface _WKInspector : NSObject

/// Whether the inspector is currently visible.
@property (nonatomic, readonly, getter=isVisible) BOOL visible;

/// Whether the inspector is currently connected.
@property (nonatomic, readonly, getter=isConnected) BOOL connected;

/// Whether page profiling (Timeline) is active.
@property (nonatomic, readonly, getter=isProfilingPage) BOOL profilingPage;

/// Whether element selection mode is active.
@property (nonatomic, readonly, getter=isElementSelectionActive) BOOL elementSelectionActive;

/// Shows the Web Inspector.
- (void)show;

/// Shows the Web Inspector focused on a specific frame's resources.
- (void)showMainResourceForFrame:(id)frame;

/// Closes the Web Inspector.
- (void)close;

/// Shows the Console panel.
- (void)showConsole;

/// Shows the Resources/Sources panel.
- (void)showResources;

/// Toggles Timeline recording on/off.
- (void)togglePageProfiling;

/// Toggles element selection mode on/off.
- (void)toggleElementSelection;

/// Sets the delegate for inspector events.
- (void)setDelegate:(nullable id)delegate;

@end

// MARK: - _WKThumbnailView

/// A view that displays a thumbnail/preview of a WKWebView's content.
///
/// Use this class to create tab previews or page thumbnails for your browser.
/// The thumbnail is rendered asynchronously and scaled based on the configured
/// `maximumSnapshotSize` and `scale` properties.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKThumbnailView.h
///
/// ## Example Usage
/// ```swift
/// let thumbnail = _WKThumbnailView(frame: .zero, from: webView)
/// thumbnail.maximumSnapshotSize = CGSize(width: 200, height: 150)
/// thumbnail.scale = 0.25
/// thumbnail.requestSnapshot()
/// containerView.addSubview(thumbnail)
/// ```
///
/// ## Availability
/// macOS 10.10+ (only available on macOS, not iOS)
#if TARGET_OS_OSX
API_AVAILABLE(macos(10.10))
@interface _WKThumbnailView : NSView

/// Creates a thumbnail view from a WKWebView.
///
/// @param frame The frame rectangle for the view.
/// @param webView The web view to create a thumbnail of.
- (instancetype)initWithFrame:(NSRect)frame fromWKWebView:(WKWebView *)webView;

/// The scale factor for the thumbnail.
///
/// A scale of 0.25 means the thumbnail will be 1/4 the size of the original.
/// This affects how the thumbnail is rendered for performance optimization.
@property (nonatomic) CGFloat scale;

/// The current size of the rendered snapshot.
///
/// This may differ from the view's frame size based on scale and content.
@property (nonatomic, readonly) CGSize snapshotSize;

/// The maximum size for snapshots.
///
/// Snapshots larger than this will be scaled down. Use this to limit
/// memory usage for tab previews.
@property (nonatomic) CGSize maximumSnapshotSize;

/// Whether the view should exclusively use the snapshot.
///
/// When YES, the view only displays the snapshot and doesn't try to
/// render live content. Useful for tab switcher implementations.
@property (nonatomic) BOOL exclusivelyUsesSnapshot;

/// Whether to keep the snapshot when the view is removed from its superview.
///
/// Default is NO. Set to YES to cache thumbnails for reuse.
@property (nonatomic) BOOL shouldKeepSnapshotWhenRemovedFromSuperview;

/// Override background color for the thumbnail.
///
/// Use this to set a consistent background while the snapshot loads.
@property (strong, nonatomic, nullable) NSColor *overrideBackgroundColor;

/// Requests a new snapshot of the web view's content.
///
/// The snapshot is rendered asynchronously. The view will update
/// when the snapshot is complete.
- (void)requestSnapshot;

@end
#endif

// MARK: - WKInputType

/// Types of input elements that can receive focus.
///
/// Used by `_WKFocusedElementInfo` to identify the type of input field.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKFocusedElementInfo.h
typedef NS_ENUM(NSInteger, WKInputType) {
    /// No input type (unfocused).
    WKInputTypeNone,

    /// Content editable element (`contenteditable="true"`).
    WKInputTypeContentEditable,

    /// Standard text input (`<input type="text">`).
    WKInputTypeText,

    /// Password input (`<input type="password">`).
    WKInputTypePassword,

    /// Textarea (`<textarea>`).
    WKInputTypeTextArea,

    /// Search input (`<input type="search">`).
    WKInputTypeSearch,

    /// Email input (`<input type="email">`).
    WKInputTypeEmail,

    /// URL input (`<input type="url">`).
    WKInputTypeURL,

    /// Phone input (`<input type="tel">`).
    WKInputTypePhone,

    /// Number input (`<input type="number">`).
    WKInputTypeNumber,

    /// Number pad input (iOS-specific behavior).
    WKInputTypeNumberPad,

    /// Date input (`<input type="date">`).
    WKInputTypeDate,

    /// DateTime input (`<input type="datetime">`).
    WKInputTypeDateTime,

    /// DateTime-local input (`<input type="datetime-local">`).
    WKInputTypeDateTimeLocal,

    /// Month input (`<input type="month">`).
    WKInputTypeMonth,

    /// Week input (`<input type="week">`).
    WKInputTypeWeek,

    /// Time input (`<input type="time">`).
    WKInputTypeTime,

    /// Select dropdown (`<select>`).
    WKInputTypeSelect,

    /// Color picker (`<input type="color">`).
    WKInputTypeColor,

    /// Drawing input (iOS-specific).
    WKInputTypeDrawing,
};

// MARK: - _WKFocusedElementInfo Protocol

/// Information about a focused form element.
///
/// This protocol provides details about an input element when it receives focus.
/// Use this to:
/// - Identify password fields for autofill
/// - Provide custom keyboards or input accessories
/// - Track form field focus for analytics
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKFocusedElementInfo.h
@protocol _WKFocusedElementInfo <NSObject>

/// The type of input element that was focused.
@property (nonatomic, readonly) WKInputType type;

/// The current value of the input element.
@property (nonatomic, readonly, copy, nullable) NSString *value;

/// The placeholder text of the input element.
@property (nonatomic, readonly, copy, nullable) NSString *placeholder;

/// The label text associated with the input (from `<label>` element).
@property (nonatomic, readonly, copy, nullable) NSString *label;

/// The frame containing the focused element.
///
/// ## Availability
/// macOS 26.0+
@property (nonatomic, readonly, copy, nullable) WKFrameInfo *frame API_AVAILABLE(macos(26.0));

/// Whether the focus was initiated by user interaction.
///
/// `YES` if the user clicked/tapped the element.
/// `NO` if focus was set programmatically (e.g., via JavaScript `focus()`).
@property (nonatomic, readonly, getter=isUserInitiated) BOOL userInitiated;

/// Additional user object for custom data.
///
/// ## Availability
/// macOS 10.13.4+
@property (nonatomic, readonly, nullable) NSObject<NSSecureCoding> *userObject API_AVAILABLE(macos(10.13.4));

@end

// MARK: - _WKFormInputSession Protocol

/// Represents an active form input session.
///
/// A form input session is created when a user focuses on an input element.
/// Use this to customize the input experience with custom keyboards,
/// accessory views, or suggestions.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKFormInputSession.h
@protocol _WKFormInputSession <NSObject>

/// Whether the session is still valid (the element is still focused).
@property (nonatomic, readonly, getter=isValid) BOOL valid;

/// Custom user object associated with the session.
@property (nonatomic, readonly, nullable) NSObject<NSSecureCoding> *userObject;

/// Information about the focused element.
///
/// ## Availability
/// macOS 10.12+
@property (nonatomic, readonly, nullable) id<_WKFocusedElementInfo> focusedElementInfo API_AVAILABLE(macos(10.12));

@end

// MARK: - _WKInputDelegate Protocol

/// Delegate for handling form input events.
///
/// Implement this protocol to receive notifications about form input sessions
/// and to customize form submission behavior.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKInputDelegate.h
///
/// ## Usage
/// Set as the input delegate on WKWebView:
/// ```objc
/// [webView _setInputDelegate:self];
/// ```
@protocol _WKInputDelegate <NSObject>
@optional

/// Called when an input session starts.
///
/// Use this to set up custom input UI or track focused fields.
///
/// @param webView The web view containing the input element.
/// @param inputSession The input session that started.
- (void)_webView:(WKWebView *)webView didStartInputSession:(id<_WKFormInputSession>)inputSession;

/// Called when a form is about to be submitted.
///
/// This is the opportunity to:
/// - Save form data (for autofill)
/// - Store credentials (for password management)
/// - Validate form data
///
/// You MUST call the submissionHandler when finished processing.
///
/// @param webView The web view containing the form.
/// @param values Dictionary of form field names to values.
/// @param userObject Custom user object if set.
/// @param submissionHandler Call this to allow the form to submit.
- (void)_webView:(WKWebView *)webView
    willSubmitFormValues:(NSDictionary *)values
              userObject:(nullable NSObject<NSSecureCoding> *)userObject
       submissionHandler:(void (^)(void))submissionHandler;

/// Called when a form is about to be submitted (with frame info).
///
/// Extended version with frame information for cross-origin handling.
///
/// ## Availability
/// macOS 26.0+
- (void)_webView:(WKWebView *)webView
    willSubmitFormValues:(NSDictionary *)values
               frameInfo:(WKFrameInfo *)frameInfo
         sourceFrameInfo:(WKFrameInfo *)sourceFrameInfo
              userObject:(nullable NSObject<NSSecureCoding> *)userObject
       submissionHandler:(void (^)(void))submissionHandler API_AVAILABLE(macos(26.0));

/// Called when a form is about to be submitted (with request URL and method).
///
/// Most detailed form submission callback with full request information.
///
/// ## Availability
/// macOS 26.0+
- (void)_webView:(WKWebView *)webView
    willSubmitFormValues:(NSDictionary *)values
               frameInfo:(WKFrameInfo *)frameInfo
         sourceFrameInfo:(WKFrameInfo *)sourceFrameInfo
              userObject:(nullable NSObject<NSSecureCoding> *)userObject
              requestURL:(NSURL *)requestURL
                  method:(NSString *)method
       submissionHandler:(void (^)(void))submissionHandler API_AVAILABLE(macos(26.0));

@end

// MARK: - WKWebView Input Delegate Extension

/// Private methods for setting the input delegate.
@interface WKWebView (WKInputDelegatePrivate)

/// Sets the input delegate for form handling.
///
/// @param delegate The delegate to receive input events.
- (void)_setInputDelegate:(nullable id<_WKInputDelegate>)delegate;

/// Gets the current input delegate.
- (nullable id<_WKInputDelegate>)_inputDelegate;

@end

// MARK: - _WKWebAuthenticationPanel

/// WebAuthentication (FIDO2/Passkeys) panel controller.
///
/// This class provides access to WebAuthn functionality, including:
/// - Creating and managing passkeys
/// - Authenticating with existing credentials
/// - Managing local authenticator credentials
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKWebAuthenticationPanel.h
///
/// ## Example Usage
/// ```swift
/// // Get all stored passkeys
/// let credentials = _WKWebAuthenticationPanel.getAllLocalAuthenticatorCredentials()
///
/// // Delete a specific passkey
/// _WKWebAuthenticationPanel.deleteLocalAuthenticatorCredential(withID: credentialID)
///
/// // Check if platform authenticator is available
/// let available = _WKWebAuthenticationPanel.isUserVerifyingPlatformAuthenticatorAvailable()
/// ```
///
/// ## Availability
/// macOS 10.15.4+
API_AVAILABLE(macos(10.15.4))
@interface _WKWebAuthenticationPanel : NSObject

// MARK: Credential Management (Class Methods)

/// Returns all locally stored authenticator credentials.
///
/// Use this to display a list of saved passkeys to the user.
///
/// @return Array of dictionaries containing credential information.
///         Keys include: _WKLocalAuthenticatorCredentialNameKey,
///         _WKLocalAuthenticatorCredentialIDKey, etc.
///
/// ## Availability
/// macOS 12.0+
+ (NSArray<NSDictionary *> *)getAllLocalAuthenticatorCredentials API_AVAILABLE(macos(12.0));

/// Returns credentials for a specific relying party ID.
///
/// @param rpID The relying party ID (usually the website domain).
///
/// ## Availability
/// macOS 13.0+
+ (NSArray<NSDictionary *> *)getAllLocalAuthenticatorCredentialsWithRPID:(NSString *)rpID API_AVAILABLE(macos(13.0));

/// Returns credentials matching a specific credential ID.
///
/// @param credentialID The credential ID to search for.
///
/// ## Availability
/// macOS 13.0+
+ (NSArray<NSDictionary *> *)getAllLocalAuthenticatorCredentialsWithCredentialID:(NSData *)credentialID API_AVAILABLE(macos(13.0));

/// Deletes a credential by its ID.
///
/// @param credentialID The credential ID to delete.
///
/// ## Availability
/// macOS 12.0+
+ (void)deleteLocalAuthenticatorCredentialWithID:(NSData *)credentialID API_AVAILABLE(macos(12.0));

/// Deletes a credential by group and ID.
///
/// @param group The credential group (can be nil).
/// @param credentialID The credential ID to delete.
///
/// ## Availability
/// macOS 12.0+
+ (void)deleteLocalAuthenticatorCredentialWithGroupAndID:(nullable NSString *)group
                                              credential:(NSData *)credentialID API_AVAILABLE(macos(12.0));

/// Clears all locally stored authenticator credentials.
///
/// ## Warning
/// This permanently deletes all stored passkeys.
///
/// ## Availability
/// macOS 12.0+
+ (void)clearAllLocalAuthenticatorCredentials API_AVAILABLE(macos(12.0));

/// Updates the display name for a credential.
///
/// @param group The credential group (can be nil).
/// @param credentialID The credential ID.
/// @param displayName The new display name.
///
/// ## Availability
/// macOS 13.0+
+ (void)setDisplayNameForLocalCredentialWithGroupAndID:(nullable NSString *)group
                                            credential:(NSData *)credentialID
                                           displayName:(NSString *)displayName API_AVAILABLE(macos(13.0));

/// Updates the name for a credential.
///
/// @param group The credential group (can be nil).
/// @param credentialID The credential ID.
/// @param name The new name.
///
/// ## Availability
/// macOS 13.0+
+ (void)setNameForLocalCredentialWithGroupAndID:(nullable NSString *)group
                                     credential:(NSData *)credentialID
                                           name:(NSString *)name API_AVAILABLE(macos(13.0));

// MARK: Credential Export/Import

/// Exports a credential to a portable format.
///
/// @param credentialID The credential ID to export.
/// @param error On failure, contains error information.
/// @return The exported credential data, or nil on failure.
///
/// ## Availability
/// macOS 13.0+
+ (nullable NSData *)exportLocalAuthenticatorCredentialWithID:(NSData *)credentialID
                                                        error:(NSError **)error API_AVAILABLE(macos(13.0));

/// Imports a credential from exported data.
///
/// @param credentialBlob The exported credential data.
/// @param error On failure, contains error information.
/// @return The imported credential ID, or nil on failure.
///
/// ## Availability
/// macOS 13.0+
+ (nullable NSData *)importLocalAuthenticatorCredential:(NSData *)credentialBlob
                                                  error:(NSError **)error API_AVAILABLE(macos(13.0));

// MARK: Platform Authenticator

/// Whether a user-verifying platform authenticator (Touch ID/Face ID) is available.
///
/// ## Availability
/// macOS 12.0+
+ (BOOL)isUserVerifyingPlatformAuthenticatorAvailable API_AVAILABLE(macos(12.0));

// MARK: Instance Methods

- (instancetype)init;

/// Cancels the current authentication operation.
- (void)cancel;

// MARK: Properties

/// The relying party ID for the current operation.
@property (nonatomic, readonly, copy, nullable) NSString *relyingPartyID;

/// The available transports for authentication.
@property (nonatomic, readonly, copy, nullable) NSSet *transports;

/// The user name for the current operation.
@property (nonatomic, readonly, copy, nullable) NSString *userName;

@end

// MARK: - WebAuthn Credential Keys

/// Key for credential name in credential dictionaries.
WK_EXTERN NSString * const _WKLocalAuthenticatorCredentialNameKey API_AVAILABLE(macos(12.0));

/// Key for credential display name in credential dictionaries.
WK_EXTERN NSString * const _WKLocalAuthenticatorCredentialDisplayNameKey API_AVAILABLE(macos(12.0));

/// Key for credential ID in credential dictionaries.
WK_EXTERN NSString * const _WKLocalAuthenticatorCredentialIDKey API_AVAILABLE(macos(12.0));

/// Key for relying party ID in credential dictionaries.
WK_EXTERN NSString * const _WKLocalAuthenticatorCredentialRelyingPartyIDKey API_AVAILABLE(macos(12.0));

/// Key for credential creation date in credential dictionaries.
WK_EXTERN NSString * const _WKLocalAuthenticatorCredentialCreationDateKey API_AVAILABLE(macos(12.0));

/// Key for credential last modification date in credential dictionaries.
WK_EXTERN NSString * const _WKLocalAuthenticatorCredentialLastModificationDateKey API_AVAILABLE(macos(12.0));

/// Key for credential group in credential dictionaries.
WK_EXTERN NSString * const _WKLocalAuthenticatorCredentialGroupKey API_AVAILABLE(macos(12.0));

/// Key for credential synchronizable flag in credential dictionaries.
WK_EXTERN NSString * const _WKLocalAuthenticatorCredentialSynchronizableKey API_AVAILABLE(macos(12.0));

/// Key for user handle in credential dictionaries.
WK_EXTERN NSString * const _WKLocalAuthenticatorCredentialUserHandleKey API_AVAILABLE(macos(12.0));

/// Key for credential last used date in credential dictionaries.
WK_EXTERN NSString * const _WKLocalAuthenticatorCredentialLastUsedDateKey API_AVAILABLE(macos(12.0));

// MARK: - Data Detection on macOS

/// Note on WKDataDetectorTypes for macOS:
///
/// The public `WKDataDetectorTypes` API is officially iOS-only. However, WebKit
/// internally uses `ENABLE(DATA_DETECTION)` on macOS, and the underlying
/// data detection functionality exists.
///
/// ## Current State (macOS)
///
/// On macOS, data detection is handled differently than iOS:
/// 1. The `dataDetectorTypes` property on `WKWebViewConfiguration` is not
///    exposed in the public API for macOS.
/// 2. WebKit uses `handleClickForDataDetectionResult:` internally for macOS.
/// 3. Data detection for phone numbers, addresses, etc. uses system Data Detectors.
///
/// ## Private Access (if needed)
///
/// The configuration's page configuration stores data detector types internally.
/// You can attempt to set them via KVC, but this is fragile:
///
/// ```objc
/// // EXPERIMENTAL - may break in future versions
/// WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
/// [config setValue:@(1 << 0 | 1 << 1) forKeyPath:@"_pageConfiguration.dataDetectorTypes"];
/// ```
///
/// ## Recommended Approach
///
/// For macOS, implement data detection via:
/// 1. NSDataDetector in your own code for text processing
/// 2. Context menu customization to add actions for detected data
/// 3. WKUIDelegate for handling clicks on detected data
///
/// ## iOS Reference Types
///
/// On iOS, these types are available:
/// - WKDataDetectorTypePhoneNumber = 1 << 0
/// - WKDataDetectorTypeLink = 1 << 1
/// - WKDataDetectorTypeAddress = 1 << 2
/// - WKDataDetectorTypeCalendarEvent = 1 << 3
/// - WKDataDetectorTypeTrackingNumber = 1 << 4
/// - WKDataDetectorTypeFlightNumber = 1 << 5
/// - WKDataDetectorTypeLookupSuggestion = 1 << 6

// MARK: - _WKProcessTerminationReason

/// Reason for web content process termination.
///
/// Used with `WKNavigationDelegatePrivate` to determine why a web content
/// process ended. This allows differentiated handling of crashes vs. OOM
/// vs. intentional termination.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/WKNavigationDelegatePrivate.h
///
/// ## Usage
/// ```objc
/// - (void)_webView:(WKWebView *)webView
///     webContentProcessDidTerminateWithReason:(_WKProcessTerminationReason)reason {
///     switch (reason) {
///     case _WKProcessTerminationReasonExceededMemoryLimit:
///         // Tab used too much memory - auto-reload may succeed
///         [self handleOOMForWebView:webView];
///         break;
///     case _WKProcessTerminationReasonCrash:
///         // Unexpected crash - notify user and auto-reload
///         [self handleCrashForWebView:webView];
///         break;
///     case _WKProcessTerminationReasonRequestedByClient:
///         // Intentional termination - no action needed
///         break;
///     default:
///         break;
///     }
/// }
/// ```
typedef NS_ENUM(NSInteger, _WKProcessTerminationReason) {
    /// Process exceeded its memory limit.
    ///
    /// Common cause: Memory leak in web page JavaScript or excessive DOM.
    /// The system terminated the process to prevent overall system instability.
    ///
    /// Recovery: Auto-reload usually succeeds, but page may crash again
    /// if it has a memory leak. Consider tracking OOM frequency per domain.
    _WKProcessTerminationReasonExceededMemoryLimit = 0,

    /// Process exceeded its CPU time limit.
    ///
    /// Common cause: Infinite loop, very expensive computation, or crypto mining.
    /// WebKit enforces CPU limits to prevent runaway pages from consuming resources.
    ///
    /// Recovery: May succeed but consider warning user. Repeated CPU limit
    /// violations likely indicate problematic site.
    _WKProcessTerminationReasonExceededCPULimit = 1,

    /// Client explicitly requested termination.
    ///
    /// Common cause: Tab was closed, session evicted, or app terminated.
    /// This is an intentional termination initiated by the browser.
    ///
    /// Recovery: Not applicable - intentional termination.
    _WKProcessTerminationReasonRequestedByClient = 2,

    /// Process crashed unexpectedly.
    ///
    /// Common cause: WebKit bug, malformed content, hardware issue,
    /// or illegal instruction. This is an uncontrolled termination.
    ///
    /// Recovery: Auto-reload usually succeeds. Log for diagnostics.
    _WKProcessTerminationReasonCrash = 3,

    /// Too many crashes in shared process.
    ///
    /// Common cause: A problematic site in a process that serves multiple
    /// tabs caused repeated crashes, exceeding the threshold.
    ///
    /// Recovery: Reload in new process via `_WKNavigationActionPolicyAllowInNewProcess`.
    /// Consider isolating this site in its own process.
    ///
    /// ## Availability
    /// macOS 15.2+
    _WKProcessTerminationReasonExceededSharedProcessCrashLimit API_AVAILABLE(macos(15.2)) = 4,
} API_AVAILABLE(macos(10.14));

// MARK: - WKNavigationDelegatePrivate Protocol

/// Private navigation delegate methods for process lifecycle and crash handling.
///
/// Implement this protocol on your `WKNavigationDelegate` to receive callbacks
/// for web content process termination with detailed reasons, and responsiveness
/// state changes.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/WKNavigationDelegatePrivate.h
///
/// ## Setup
/// The same object should conform to both `WKNavigationDelegate` and
/// `WKNavigationDelegatePrivate`. Set it as the web view's navigation delegate.
///
/// ## Important
/// These methods are called on the main thread.
@protocol WKNavigationDelegatePrivate <WKNavigationDelegate>
@optional

/// Called when the web content process terminates with a specific reason.
///
/// This method provides more detail than the public
/// `webViewWebContentProcessDidTerminate:` by including the termination reason,
/// allowing differentiated handling of crashes, OOM, CPU limits, etc.
///
/// @param webView The web view whose process terminated.
/// @param reason The reason for termination (crash, OOM, CPU limit, etc.).
///
/// ## Implementation Notes
/// - Called immediately when WebKit detects process termination
/// - The web view's content is no longer valid after this call
/// - Call `reload` to recover the tab's content
/// - Track termination frequency to detect problematic sites
///
/// ## Availability
/// macOS 10.14+
- (void)_webView:(WKWebView *)webView
    webContentProcessDidTerminateWithReason:(_WKProcessTerminationReason)reason
    API_AVAILABLE(macos(10.14));

/// Called when the web process becomes unresponsive.
///
/// A web process is considered unresponsive when it fails to respond to
/// IPC messages within a timeout period (typically 3-5 seconds). This
/// usually indicates JavaScript is blocked in an infinite loop or very
/// expensive computation.
///
/// @param webView The web view whose process became unresponsive.
///
/// ## UI Recommendations
/// - Show a "page unresponsive" indicator
/// - Offer user choice: "Wait" or "Kill page"
/// - Consider auto-terminating after extended period (e.g., 30 seconds)
///
/// ## Availability
/// macOS 10.12+
- (void)_webViewWebProcessDidBecomeUnresponsive:(WKWebView *)webView
    API_AVAILABLE(macos(10.12));

/// Called when an unresponsive web process becomes responsive again.
///
/// The process recovered and is now responding to IPC messages.
/// Hide any "page unresponsive" indicator.
///
/// @param webView The web view whose process became responsive.
///
/// ## Availability
/// macOS 10.12+
- (void)_webViewWebProcessDidBecomeResponsive:(WKWebView *)webView
    API_AVAILABLE(macos(10.12));

/// Called when the web process crashes (legacy callback).
///
/// This is the older crash notification without reason information.
/// Prefer `_webView:webContentProcessDidTerminateWithReason:` when available.
///
/// @param webView The web view whose process crashed.
- (void)_webViewWebProcessDidCrash:(WKWebView *)webView;

@end

NS_ASSUME_NONNULL_END
