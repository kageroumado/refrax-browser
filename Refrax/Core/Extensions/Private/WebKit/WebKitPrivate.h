/**
 * WebKitPrivate.h
 * Refrax Browser
 *
 * Unified bridging header for WebKit private APIs.
 *
 * This header serves as the single import point for all private WebKit APIs
 * used by Refrax. It imports modular headers organized by functionality:
 *
 * ## Module Structure
 *
 * ### Core APIs (WKWebViewPrivate+Core.h)
 * - Page lifecycle (_close, _tryClose, _isClosed)
 * - Document detection (_isDisplayingPDF, _isDisplayingStandaloneImageDocument)
 * - Presentation updates (_doAfterNextPresentationUpdate:)
 * - Reload variants, content preloading
 *
 * ### Media APIs (WKWebViewPrivate+Media.h)
 * - Audio state and muting (_isPlayingAudio, _setPageMuted:)
 * - Display/screen capture control
 * - Picture-in-Picture and in-window video
 * - Media session control
 *
 * ### Interaction Control (WKWebViewPrivate+Interaction.h)
 * - Event blocking (_ignoresAllEvents, _ignoresNonWheelEvents)
 * - Mouse tracking control (_ignoresMouseMoveEvents)
 *
 * ### Thumbnail View (WKThumbnailViewPrivate.h)
 * - _WKThumbnailView class for efficient tab previews
 *
 * ### Delegates (WKDelegatesPrivate.h)
 * - _WKInputDelegate for form input handling
 * - _WKIconLoadingDelegate for favicon loading
 * - WKHistoryDelegatePrivate for title updates
 *
 * ### Context Menu (WKContextMenuPrivate.h)
 * - _WKHitTestResult for element information
 * - _WKContextMenuElementInfo for context menu data
 * - WKUIDelegatePrivate context menu methods
 *
 * ### Process State (WKProcessStatePrivate.h)
 * - _WKWebProcessState enumeration
 * - _webProcessState property for tab state monitoring
 *
 * ### Web Inspector (WKInspectorPrivate.h)
 * - _WKInspector class for developer tools
 *
 * ### WebAuthentication (WKWebAuthenticationPrivate.h)
 * - _WKWebAuthenticationPanel for passkey management
 *
 * ## App Store Notice
 * These APIs are NOT allowed in App Store submissions. Refrax is distributed
 * outside the App Store.
 *
 * ## Stability
 * Private APIs may change between macOS versions. Test thoroughly on each
 * new OS release. All APIs are derived from WebKit trunk source code.
 *
 * ## Thread Safety
 * All WebKit APIs must be called on the main thread.
 *
 * ## Source References
 * All declarations are derived from WebKit source:
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebViewPrivate.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/WKUIDelegatePrivate.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKThumbnailView.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKInputDelegate.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKIconLoadingDelegate.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/WKHistoryDelegatePrivate.h
 * - WebKit/Source/WebKit/Shared/API/Cocoa/_WKHitTestResult.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKContextMenuElementInfo.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKInspector.h
 * - WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKWebAuthenticationPanel.h
 *
 * Last verified: WebKit trunk (December 2024)
 */

#ifndef WebKitPrivate_h
#define WebKitPrivate_h

#import <WebKit/WebKit.h>

// Core WebKit private APIs
#import "WKWebViewPrivate+Core.h"

// Media playback and capture control
#import "WKWebViewPrivate+Media.h"

// User interaction control
#import "WKWebViewPrivate+Interaction.h"

// Efficient tab thumbnail generation
#import "WKThumbnailViewPrivate.h"

// Private delegate protocols
#import "WKDelegatesPrivate.h"

// Context menu and hit testing
#import "WKContextMenuPrivate.h"

// Web process state monitoring
#import "WKProcessStatePrivate.h"

// Web Inspector control
#import "WKInspectorPrivate.h"

// WebAuthentication (Passkeys) management
#import "WKWebAuthenticationPrivate.h"

// Editor state observation for autofill on macOS
#import "WKWebViewEditorStatePrivate.h"

// File input parameters for upload dialogs
#import "WKOpenPanelParametersPrivate.h"

// Per-navigation webpage preferences (autoplay policy)
#import "WKWebpagePreferencesPrivate.h"

// QuartzCore private layer APIs (CAPortalLayer, CALayerHost, CABackdropLayer)
#import "QuartzCoreSPI.h"

// CAContext private APIs for cross-window portal support
#import "CAContextPrivate.h"

// Text extraction and native content tree access
#import "WKTextExtractionPrivate.h"

// Process pool management and per-process metrics
#import "WKProcessPoolPrivate.h"
#import "WKProcessPoolBridge.h"

// MARK: - WKWebViewConfiguration (WKPrivate)

/// Private extensions to WKWebViewConfiguration for page color sampling.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebViewConfigurationPrivate.h
@interface WKWebViewConfiguration (WKPrivate)

/// The maximum Lab color difference allowed between consecutive page top samples.
///
/// When set to a positive value, enables page top color sampling on the web view.
/// The sampled color is available via `WKWebView._sampledPageTopColor`.
///
/// - Value of 0 disables sampling entirely
/// - Recommended value is 5.0 for most use cases
/// - Lower values require more uniform colors
/// - Higher values are more lenient but may produce odd colors
///
/// ## Usage
/// Set this before creating the WKWebView:
/// ```objc
/// configuration._sampledPageTopColorMaxDifference = 5.0;
/// WKWebView *webView = [[WKWebView alloc] initWithFrame:frame configuration:configuration];
/// ```
///
/// ## Availability
/// macOS 12.0+, iOS 15.0+
@property (nonatomic, setter=_setSampledPageTopColorMaxDifference:) double _sampledPageTopColorMaxDifference API_AVAILABLE(macos(12.0), ios(15.0));

/// The minimum height in points for the sampled region at the top of the page.
///
/// This controls how tall the sampling area must be to produce a valid color.
/// A minimum height ensures the sampled region is representative of the page's
/// intended top color rather than just a thin strip.
///
/// - Value of 0 disables the minimum height check
/// - Safari uses a value of 5
/// - Larger values require more of the page to be uniformly colored
///
/// ## Note
/// Both this and `_sampledPageTopColorMaxDifference` must be set for sampling
/// to work. Setting only one will not enable color sampling.
///
/// ## Availability
/// macOS 12.0+, iOS 15.0+
@property (nonatomic, setter=_setSampledPageTopColorMinHeight:) double _sampledPageTopColorMinHeight API_AVAILABLE(macos(12.0), ios(15.0));

/// Whether cross-origin access control checks are enabled.
///
/// When set to `NO`, CORS preflight requests are skipped and cross-origin
/// fetches succeed regardless of server headers. This effectively disables
/// the Same-Origin Policy for network requests.
///
/// - Warning: Disabling CORS is a significant security reduction. Only use
///   for trusted development environments or when explicitly requested by the user.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebViewConfigurationPrivate.h
@property (nonatomic, setter=_setCrossOriginAccessControlCheckEnabled:) BOOL _crossOriginAccessControlCheckEnabled API_AVAILABLE(macos(11.0), ios(14.0));

@end

// MARK: - WKSnapshotConfiguration (WKPrivate)

/// Private extensions to WKSnapshotConfiguration for advanced snapshot customization.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/WKSnapshotConfigurationPrivate.h
@interface WKSnapshotConfiguration (WKPrivate)

/// Whether to include selection highlighting in the snapshot.
///
/// When YES, any selected text will have its selection highlight rendered
/// in the snapshot. When NO, the snapshot shows the page without selection.
///
/// ## Availability
/// macOS 13.3+
@property (nonatomic, setter=_setIncludesSelectionHighlighting:) BOOL _includesSelectionHighlighting API_AVAILABLE(macos(13.3));

/// Whether to use a transparent background for the snapshot.
///
/// When YES, the snapshot will have a transparent background instead of
/// the page's background color. Useful for compositing or overlay effects.
///
/// ## Availability
/// macOS 14.2+
@property (nonatomic, setter=_setUsesTransparentBackground:) BOOL _usesTransparentBackground API_AVAILABLE(macos(14.2));

/// Whether to use the contents rect for the snapshot region.
///
/// When YES, the snapshot captures the entire scrollable content of the page
/// rather than just the visible viewport. The `rect` property is interpreted
/// as a region within the full content coordinate space.
///
/// ## Availability
/// macOS 15.0+
@property (nonatomic, setter=_setUsesContentsRect:) BOOL _usesContentsRect API_AVAILABLE(macos(15.0));

@end

@class _WKFeature;

// MARK: - WKPreferences (WKPrivate)

/// Private extensions to WKPreferences for media playback control.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/WKPreferencesPrivate.h
@interface WKPreferences (WKPrivate)

/// Whether Picture-in-Picture media playback is allowed.
///
/// When enabled, videos can be displayed in a floating window that stays
/// on top of other windows. This must be enabled for `_togglePictureInPicture`
/// to work on WKWebView.
///
/// The default value in WebKit is YES for macOS and iOS, NO for watchOS.
///
/// ## Availability
/// macOS 10.13+, iOS 11.0+
@property (nonatomic, setter=_setAllowsPictureInPictureMediaPlayback:) BOOL _allowsPictureInPictureMediaPlayback
    API_AVAILABLE(macos(10.13), ios(11.0));

/// Returns all configurable WebKit features (stable, unstable, internal, etc.).
///
/// Each feature has a `key` (e.g., "LocalNetworkAccessEnabled"), `name`, `status`,
/// and `defaultValue`. Use `-_setEnabled:forFeature:` to toggle features.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/WKPreferencesPrivate.h
///
/// ## Availability
/// macOS 13.3+, iOS 16.4+
+ (NSArray<_WKFeature *> *)_features API_AVAILABLE(macos(13.3), ios(16.4));

/// Returns whether a given feature is currently enabled on this preferences instance.
- (BOOL)_isEnabledForFeature:(_WKFeature *)feature API_AVAILABLE(macos(10.12), ios(10.0));

/// Enables or disables a feature on this preferences instance.
- (void)_setEnabled:(BOOL)enabled forFeature:(_WKFeature *)feature API_AVAILABLE(macos(10.12), ios(10.0));

@end

// MARK: - _WKFeature

/// A configurable WebKit feature flag.
///
/// Instances are obtained from `[WKPreferences _features]`. Each feature has a
/// unique `key`, human-readable `name`, and `status` indicating its maturity.
///
/// ## Source
/// WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKFeature.h
API_AVAILABLE(macos(13.3), ios(16.4))
@interface _WKFeature : NSObject

/// The unique identifier for this feature (e.g., "LocalNetworkAccessEnabled").
@property (nonatomic, readonly, copy) NSString *key;

/// Human-readable name (e.g., "Local Network Access").
@property (nonatomic, readonly, copy) NSString *name;

/// Whether this feature is enabled by default.
@property (nonatomic, readonly) BOOL defaultValue;

@end

#endif /* WebKitPrivate_h */
