/**
 * NSContainerConcentricGlassEffectView.h
 * Refrax Browser
 *
 * Private NSContainerConcentricGlassEffectView APIs for Liquid Glass effects.
 *
 * NSContainerConcentricGlassEffectView is a subclass of NSGlassEffectView
 * used for concentric glass effects, such as the sidebar in macOS Tahoe.
 * It provides additional corner radius customization for nested glass effects.
 *
 * ## Key Features
 *
 * - **Concentric Corner Radius**: Minimum radius for nested concentric shapes
 * - **Non-uniform Corners**: Support for different radii on each corner
 *
 * ## Usage
 *
 * Used by AppKit for sidebar and other container-based glass effects.
 * The concentric styling creates proper visual layering when glass effects
 * are nested or adjacent to each other.
 *
 * ## App Store Notice
 * These APIs are NOT allowed in App Store submissions.
 *
 * ## Availability
 * New in macOS 26.0 (Tahoe)
 *
 * ## Source Reference
 * Derived from AppKit framework headers (macOS 26.1 SDK)
 */

#ifndef NSContainerConcentricGlassEffectView_h
#define NSContainerConcentricGlassEffectView_h

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - NSContainerConcentricGlassEffectView

/**
 * A glass effect view with concentric corner radius support.
 *
 * This view is used by AppKit for sidebar glass effects. It extends
 * NSGlassEffectView with additional properties for controlling how
 * corner radii behave in concentric (nested) configurations.
 */
@interface NSContainerConcentricGlassEffectView : NSGlassEffectView

/**
 * The minimum corner radius for concentric glass effects.
 *
 * When glass effects are nested, this ensures the inner radius
 * doesn't become too small. The actual corner radius used will be
 * at least this value.
 */
@property (nonatomic) double concentricMinimumCornerRadius;

/**
 * Whether to allow non-uniform corner radii.
 *
 * When YES, each corner can have a different radius.
 * When NO, all corners share the same radius.
 */
@property (nonatomic) BOOL allowsNonuniformCornerRadii;

/**
 * The corner configuration for this view.
 *
 * Returns the current corner configuration, which may include
 * per-corner radius settings when `allowsNonuniformCornerRadii` is YES.
 *
 * @return The corner configuration object.
 */
- (nullable id)_cornerConfiguration;

@end

NS_ASSUME_NONNULL_END

#endif /* NSContainerConcentricGlassEffectView_h */
