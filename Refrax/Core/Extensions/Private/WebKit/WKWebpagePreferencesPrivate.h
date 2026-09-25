/**
 * WKWebpagePreferencesPrivate.h
 * Refrax Browser
 *
 * Private WebKit APIs for per-navigation webpage preferences.
 *
 * Provides the autoplay policy WebKit enforces natively during navigation,
 * and Safari's advanced privacy protections (fingerprinting noise and
 * link decoration filtering).
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

#pragma mark - Advanced Privacy Protections

/**
 * Safari's per-navigation advanced privacy protections.
 *
 * The flag names do not describe what they enable (EnhancedTelemetry sends
 * nothing anywhere); `WKWebpagePreferences.mm` maps each flag onto
 * `WebCore::AdvancedPrivacyProtections`:
 *
 * | Flag                          | WebCore protection                        |
 * |-------------------------------|-------------------------------------------|
 * | Enabled                       | BaselineProtections                       |
 * | HTTPSFirst / HTTPSOnly        | HTTPSFirst / HTTPSOnly                    |
 * | FailClosed                    | FailClosedForUnreachableHosts             |
 * | EnhancedTelemetry             | FingerprintingProtections (Safari's AFP)  |
 * | RequestValidation             | EnhancedNetworkPrivacy                    |
 * | SanitizeLookalikeCharacters   | LinkDecorationFiltering                   |
 *
 * `FingerprintingProtections` injects per-site noise into canvas, WebGL and
 * Web Audio readback and reports quantized screen metrics.
 * `LinkDecorationFiltering` strips known click-ID query parameters from
 * navigations and from copied or pasted links, using the list the system
 * WebPrivacy service supplies; embedders cannot supply their own list.
 *
 * ## Source
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKWebpagePreferencesPrivate.h
 */
typedef NS_OPTIONS(NSUInteger, _WKWebsiteNetworkConnectionIntegrityPolicy) {
    _WKWebsiteNetworkConnectionIntegrityPolicyNone = 0,
    _WKWebsiteNetworkConnectionIntegrityPolicyEnabled = 1 << 0,
    _WKWebsiteNetworkConnectionIntegrityPolicyHTTPSFirst = 1 << 1,
    _WKWebsiteNetworkConnectionIntegrityPolicyHTTPSOnly = 1 << 2,
    _WKWebsiteNetworkConnectionIntegrityPolicyHTTPSOnlyExplicitlyBypassedForDomain = 1 << 3,
    _WKWebsiteNetworkConnectionIntegrityPolicyFailClosed = 1 << 4,
    _WKWebsiteNetworkConnectionIntegrityPolicyWebSearchContent API_AVAILABLE(macos(14.0), ios(17.0)) = 1 << 5,
    _WKWebsiteNetworkConnectionIntegrityPolicyEnhancedTelemetry API_AVAILABLE(macos(14.0), ios(17.0)) = 1 << 6,
    _WKWebsiteNetworkConnectionIntegrityPolicyRequestValidation API_AVAILABLE(macos(14.0), ios(17.0)) = 1 << 7,
    _WKWebsiteNetworkConnectionIntegrityPolicySanitizeLookalikeCharacters API_AVAILABLE(macos(14.0), ios(17.0)) = 1 << 8,
    _WKWebsiteNetworkConnectionIntegrityPolicyFailClosedForAllHosts API_AVAILABLE(macos(26.0), ios(26.0)) = 1 << 9,
    _WKWebsiteNetworkConnectionIntegrityPolicyStrictFailClosed API_AVAILABLE(macos(26.0), ios(26.0)) = 1 << 10,
} API_AVAILABLE(macos(13.3), ios(16.4));

#pragma mark - WKWebpagePreferences Private Extensions

NS_ASSUME_NONNULL_BEGIN

@interface WKWebpagePreferences (WKPrivate)

/** Per-navigation autoplay policy. Overrides the default from WKWebViewConfiguration. */
@property (nonatomic, setter=_setAutoplayPolicy:) _WKWebsiteAutoplayPolicy _autoplayPolicy API_AVAILABLE(macos(10.13), ios(11.0));

/**
 * Advanced privacy protections for the navigation.
 *
 * Replaces the whole set on write. Check `respondsToSelector:` with
 * `_setNetworkConnectionIntegrityPolicy:` before use.
 */
@property (nonatomic, setter=_setNetworkConnectionIntegrityPolicy:) _WKWebsiteNetworkConnectionIntegrityPolicy _networkConnectionIntegrityPolicy API_AVAILABLE(macos(13.3), ios(16.4));

@end

NS_ASSUME_NONNULL_END
