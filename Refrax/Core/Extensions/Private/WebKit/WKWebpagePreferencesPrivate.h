/**
 * WKWebpagePreferencesPrivate.h
 * Refrax Browser
 *
 * Private WebKit APIs for per-navigation webpage preferences.
 *
 * Provides access to autoplay policy control that WebKit enforces
 * natively during navigation, avoiding the need for manual media
 * suspension via autoplay event callbacks.
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebpagePreferencesPrivate.h
 */

#import <WebKit/WKWebpagePreferences.h>

#pragma mark - Autoplay Policy

/**
 * Per-navigation autoplay policy.
 *
 * Set on `WKWebpagePreferences` returned from
 * `decidePolicyFor:navigationAction:preferences:` to control
 * how WebKit handles media autoplay for that navigation.
 *
 * ## Availability
 * macOS 10.13+, iOS 11.0+
 */
typedef NS_ENUM(NSInteger, _WKWebsiteAutoplayPolicy) {
    /** Use the default autoplay behavior from WKWebViewConfiguration. */
    _WKWebsiteAutoplayPolicyDefault,

    /** Allow all autoplay (muted and unmuted). */
    _WKWebsiteAutoplayPolicyAllow,

    /** Allow muted autoplay only; require user gesture for sound. */
    _WKWebsiteAutoplayPolicyAllowWithoutSound,

    /** Block all autoplay; require user gesture for any playback. */
    _WKWebsiteAutoplayPolicyDeny
} API_AVAILABLE(macos(10.13), ios(11.0));

#pragma mark - WKWebpagePreferences Private Extensions

@interface WKWebpagePreferences (WKPrivate)

/** Per-navigation autoplay policy. Overrides the default from WKWebViewConfiguration. */
@property (nonatomic, setter=_setAutoplayPolicy:) _WKWebsiteAutoplayPolicy _autoplayPolicy API_AVAILABLE(macos(10.13), ios(11.0));

@end
