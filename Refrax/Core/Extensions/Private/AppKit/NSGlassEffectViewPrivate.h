/**
 * NSGlassEffectViewPrivate.h
 * Refrax Browser
 *
 * Private NSGlassEffectView APIs for Liquid Glass effects.
 *
 * NSGlassEffectView is the new view class introduced in macOS Tahoe (26)
 * that implements the Liquid Glass design language. It provides advanced
 * glass-like materials with depth, refraction, and adaptive appearance.
 *
 * ## Key Features
 *
 * - **Variants**: Different glass styles (regular, subdued, etc.)
 * - **Interaction States**: Visual feedback for hover, press, selection
 * - **Content Lensing**: Refraction/magnification of underlying content
 * - **Adaptive Appearance**: Automatic adjustment to surrounding content
 * - **Custom Shapes**: Support for custom CGPath shapes
 *
 * ## Usage
 *
 * NSGlassEffectView should be used as a container for content that needs
 * the Liquid Glass appearance. The `contentView` property holds your actual
 * content, which is rendered with the glass effect applied.
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

#ifndef NSGlassEffectViewPrivate_h
#define NSGlassEffectViewPrivate_h

#import <AppKit/AppKit.h>

// Forward declaration for private AppKit class
@class NSViewCornerConfiguration;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Glass Variant

/**
 * Glass effect variants that define the base appearance.
 *
 * Each variant has different levels of blur, tint, and reflectivity
 * to suit different UI contexts.
 */
typedef NS_ENUM(NSInteger, NSGlassEffectVariant) {
    /** Standard glass appearance - balanced blur and reflectivity */
    NSGlassEffectVariantRegular = 0,
    /** Reduced visual prominence - less blur and reflection */
    NSGlassEffectVariantSubdued = 1,
    /** Enhanced visual prominence - more pronounced glass effect */
    NSGlassEffectVariantProminent = 2,
    /** Ultra-thin glass - minimal visual weight */
    NSGlassEffectVariantUltraThin = 3
};

#pragma mark - Interaction State

/**
 * Interaction states that affect the glass appearance.
 *
 * The glass effect changes subtly based on user interaction
 * to provide visual feedback.
 */
typedef NS_ENUM(NSInteger, NSGlassEffectInteractionState) {
    /** Default state - no interaction */
    NSGlassEffectInteractionStateNone = 0,
    /** Mouse hovering over the view */
    NSGlassEffectInteractionStateHovered = 1,
    /** Mouse pressed on the view */
    NSGlassEffectInteractionStatePressed = 2,
    /** View is selected/active */
    NSGlassEffectInteractionStateSelected = 3
};

#pragma mark - Subdued State

/**
 * Subdued states that reduce the glass effect prominence.
 *
 * Used when the glass effect should be less visually prominent,
 * such as when in a background or inactive state.
 */
typedef NS_ENUM(NSInteger, NSGlassEffectSubduedState) {
    /** Normal appearance */
    NSGlassEffectSubduedStateNone = 0,
    /** Slightly reduced prominence */
    NSGlassEffectSubduedStateLow = 1,
    /** Moderately reduced prominence */
    NSGlassEffectSubduedStateMedium = 2,
    /** Significantly reduced prominence */
    NSGlassEffectSubduedStateHigh = 3
};

#pragma mark - Scrim State

/**
 * Scrim states that add an overlay to the glass effect.
 *
 * Scrims are semi-transparent overlays that can be used to
 * improve legibility or indicate state.
 */
typedef NS_ENUM(NSInteger, NSGlassEffectScrimState) {
    /** No scrim overlay */
    NSGlassEffectScrimStateNone = 0,
    /** Light scrim for subtle dimming */
    NSGlassEffectScrimStateLight = 1,
    /** Dark scrim for stronger dimming */
    NSGlassEffectScrimStateDark = 2
};

#pragma mark - Content Lensing

/**
 * Content lensing modes that affect how underlying content appears.
 *
 * Lensing creates a subtle magnification/refraction effect
 * on content behind the glass.
 */
typedef NS_ENUM(NSInteger, NSGlassEffectContentLensing) {
    /** No lensing effect */
    NSGlassEffectContentLensingNone = 0,
    /** Subtle lensing */
    NSGlassEffectContentLensingSubtle = 1,
    /** Standard lensing */
    NSGlassEffectContentLensingRegular = 2,
    /** Pronounced lensing */
    NSGlassEffectContentLensingProminent = 3
};

#pragma mark - Adaptive Appearance

/**
 * Adaptive appearance modes that adjust to surrounding content.
 *
 * The glass effect can automatically adjust its appearance
 * based on the luminance or color of underlying content.
 */
typedef NS_ENUM(NSInteger, NSGlassEffectAdaptiveAppearance) {
    /** No adaptation - fixed appearance */
    NSGlassEffectAdaptiveAppearanceNone = 0,
    /** Adapts to underlying content luminance */
    NSGlassEffectAdaptiveAppearanceLuminance = 1,
    /** Adapts to underlying content color */
    NSGlassEffectAdaptiveAppearanceColor = 2,
    /** Full adaptation to content */
    NSGlassEffectAdaptiveAppearanceFull = 3
};

#pragma mark - NSGlassEffectView

/**
 * Private NSGlassEffectView APIs.
 *
 * NSGlassEffectView is public in macOS 26.0+. This category exposes
 * additional private APIs for advanced customization.
 *
 * Public properties (contentView, cornerRadius, tintColor, style) are
 * already declared in <AppKit/NSGlassEffectView.h>.
 */
@interface NSGlassEffectView (RefraxPrivate)

#pragma mark - Variant & Style

/**
 * The glass effect variant.
 *
 * Controls the base appearance of the glass effect.
 * See `NSGlassEffectVariant` for available options.
 */
@property (nonatomic) NSGlassEffectVariant _variant;

/**
 * The sub-variant identifier for more specific styling.
 *
 * Some variants have sub-variants for specialized contexts.
 */
@property (nonatomic, copy, nullable) NSString *_subvariant;

#pragma mark - Interaction & State

/**
 * The current interaction state.
 *
 * Set this to provide visual feedback during user interaction.
 * The glass effect subtly changes appearance based on this state.
 */
@property (nonatomic) NSGlassEffectInteractionState _interactionState;

/**
 * The subdued state for reduced prominence.
 *
 * Use this when the glass should be less visually prominent,
 * such as when the window is inactive.
 */
@property (nonatomic) NSGlassEffectSubduedState _subduedState;

/**
 * The scrim state for overlays.
 *
 * Adds a semi-transparent overlay to the glass effect.
 */
@property (nonatomic) NSGlassEffectScrimState _scrimState;

#pragma mark - Visual Effects

/**
 * The content lensing mode.
 *
 * Controls the refraction/magnification effect on underlying content.
 */
@property (nonatomic) NSGlassEffectContentLensing _contentLensing;

/**
 * The adaptive appearance mode.
 *
 * Controls how the glass adapts to surrounding content.
 */
@property (nonatomic) NSGlassEffectAdaptiveAppearance _adaptiveAppearance;

/**
 * Whether to use a reduced shadow radius.
 *
 * When YES, the shadow around the glass is more subtle.
 */
@property (nonatomic) BOOL _useReducedShadowRadius;

#pragma mark - Grouping

/**
 * The group identifier for coordinating multiple glass views.
 *
 * Glass views with the same group identifier share backdrop
 * captures and coordinate their appearance.
 */
@property (nonatomic, copy, nullable) NSString *_groupIdentifier;

#pragma mark - Shape

/**
 * A custom path for non-rectangular glass shapes.
 *
 * Set this to create glass effects with custom shapes.
 * Pass nil to use the standard rectangular shape with cornerRadius.
 *
 * Note: CGPathRef is a CF type, use assign semantics.
 */
@property (nonatomic, assign, nullable) CGPathRef _path;

#pragma mark - Corner Configuration

/**
 * The corner configuration for advanced corner customization.
 *
 * Provides per-corner control over the glass shape.
 */
@property (nonatomic, readonly, nullable) NSViewCornerConfiguration *_cornerConfiguration;

#pragma mark - Vibrancy

/**
 * The vibrant blending style for subviews.
 *
 * Controls how subviews blend with the glass effect
 * for vibrancy support.
 */
@property (nonatomic) NSUInteger _vibrantBlendingStyleForSubtree;

#pragma mark - Embedding

/**
 * Increments the disable embedding counter.
 *
 * When the counter is greater than 0, the view cannot be
 * automatically embedded in a glass effect container.
 */
- (void)_incrementDisableEmbedding;

/**
 * Decrements the disable embedding counter.
 */
- (void)_decrementDisableEmbedding;

/**
 * The current disable embedding count.
 */
@property (nonatomic, readonly) NSInteger _disableEmbeddingCount;

#pragma mark - Debugging

/**
 * A debug description of the adaptive appearance state.
 */
@property (nonatomic, readonly, nullable) NSString *_adaptationDebugDescription;

@end

#pragma mark - NSGlassContainerView

/**
 * A container view that can host multiple glass effect views.
 *
 * NSGlassContainerView provides additional control over how
 * glass effects are composited when multiple glass views overlap.
 */
@interface NSGlassContainerView : NSGlassEffectView

/**
 * The smoothness of the glass effect container.
 *
 * Higher values create smoother transitions between
 * overlapping glass effects.
 */
@property (nonatomic) CGFloat smoothness;

@end

NS_ASSUME_NONNULL_END

#endif /* NSGlassEffectViewPrivate_h */
