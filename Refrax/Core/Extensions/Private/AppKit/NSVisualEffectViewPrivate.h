/**
 * NSVisualEffectViewPrivate.h
 * Refrax Browser
 *
 * Private NSVisualEffectView APIs for advanced blur and vibrancy effects.
 *
 * NSVisualEffectView provides the classic macOS blur and vibrancy effects.
 * These private APIs enable fine-grained control over backdrop groups,
 * material appearance, and performance optimizations.
 *
 * ## Key Features
 *
 * - **Backdrop Groups**: Coordinate blur captures across multiple views
 * - **Material Control**: Corner radius, continuous corners
 * - **Clear State**: Temporarily disable the effect
 * - **Chameleon**: Artificial chameleon appearance for dark content
 *
 * ## Backdrop Groups
 *
 * Backdrop groups allow multiple views to share a single blur capture,
 * improving performance. Views with the same `_groupName` coordinate
 * their backdrop rendering.
 *
 * ## App Store Notice
 * These APIs are NOT allowed in App Store submissions.
 *
 * ## Source Reference
 * Derived from AppKit framework headers (macOS 26.1 SDK)
 */

#ifndef NSVisualEffectViewPrivate_h
#define NSVisualEffectViewPrivate_h

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface NSVisualEffectView (RefraxPrivate)

#pragma mark - Backdrop Groups

/**
 * The group name for coordinating backdrop captures.
 *
 * Views with the same group name share a single backdrop capture,
 * reducing GPU overhead when multiple views need the same blur.
 *
 * ## Example
 * ```objc
 * // Coordinate sidebar and toolbar blur
 * sidebarEffect._groupName = @"MainWindowChrome";
 * toolbarEffect._groupName = @"MainWindowChrome";
 * ```
 *
 * - Note: Set to nil to use independent backdrop capture.
 */
@property (copy, nullable) NSString *_groupName;

/**
 * The effective group name for within-window backdrop coordination.
 *
 * Returns the resolved group name considering window-level defaults.
 */
@property (readonly, nullable) NSString *_effectiveWithinWindowBackdropGroupName;

/**
 * The default backdrop group name for behind-window content.
 *
 * Used for coordinating blur of desktop content behind windows.
 */
+ (nullable NSString *)_behindWindowBackdropGroupName;

/**
 * The scale factor for behind-window backdrop capture.
 *
 * Lower values reduce memory usage but also blur quality.
 */
+ (CGFloat)_behindWindowBackdropScale;

#pragma mark - Material Appearance

/**
 * The corner radius applied to the material effect.
 *
 * Controls how rounded the corners of the blur effect appear.
 * Set to 0 for square corners.
 */
@property (nonatomic) CGFloat _materialCornerRadius;

/**
 * Whether to use continuous (squircle) corners.
 *
 * When YES, uses Apple's continuous corner curves (like iOS app icons).
 * When NO, uses standard circular arc corners.
 */
@property (nonatomic) BOOL _useContinuousCorners;

/**
 * The effective corner radius after applying material constraints.
 */
- (CGFloat)_effectiveMaskCornerRadius;

#pragma mark - Clear State

/**
 * Whether the visual effect is currently cleared (disabled).
 *
 * When YES, the view renders as transparent without any blur effect.
 * Useful for temporarily disabling the effect without removing the view.
 */
@property (nonatomic, getter=_isClear) BOOL _clear;

/**
 * Updates the clear state after changes.
 *
 * Call this after modifying properties that affect the clear state.
 */
- (void)_updateClearState;

#pragma mark - Chameleon Appearance

/**
 * Whether to force the artificial chameleon layer.
 *
 * The chameleon effect adjusts the blur tint based on underlying content.
 * When forced, this effect is always active regardless of system settings.
 *
 * Useful for maintaining consistent appearance over varied content.
 */
@property (nonatomic) BOOL _forcesArtificialChameleon;

/**
 * Whether the view wants an artificial chameleon layer.
 *
 * Returns YES if the current configuration would benefit from
 * a chameleon layer for adaptive appearance.
 */
- (BOOL)_wantsArtificialChameleonLayer;

#pragma mark - Material Preferred Appearance

/**
 * Whether the view uses the material's preferred appearance.
 *
 * When YES, the view adopts the appearance that the material
 * specifies (e.g., dark appearance for certain materials).
 */
@property (nonatomic) BOOL _usesMaterialPreferredAppearance;

#pragma mark - Vibrancy

/**
 * The vibrant blending style for descendant views.
 *
 * Controls how subviews blend with the visual effect for vibrancy.
 */
- (NSUInteger)_vibrantBlendingStyleForSubtree;

/**
 * Updates vibrancy for all subviews.
 *
 * Call this after changing vibrancy-related properties.
 */
- (void)_updateVibrancy;

#pragma mark - Layer Management

/**
 * Updates the material layer to reflect current settings.
 *
 * Called automatically, but can be invoked manually after
 * bulk property changes for efficiency.
 */
- (void)_updateMaterialLayer;

/**
 * Removes the material layer if it's no longer needed.
 *
 * Used during state transitions to clean up resources.
 */
- (void)_removeMaterialLayerIfNeeded;

/**
 * Updates the color fill layer.
 *
 * The color fill layer provides the solid color component
 * of certain material types.
 */
- (void)_updateColorFillLayer;

/**
 * Removes the color fill layer if it's no longer needed.
 */
- (void)_removeColorFillLayerIfNeeded;

#pragma mark - Window Integration

/**
 * Called when the window changes key state.
 *
 * Updates the visual effect appearance based on whether
 * the window is key (active) or not.
 */
- (void)_windowChangedKeyState;

/**
 * Called when the window enters or exits full screen.
 *
 * Adjusts the visual effect for full screen context.
 */
- (void)_windowFullScreenDidChange;

#pragma mark - Freezing

/**
 * Begins freezing visual effect updates in a window.
 *
 * While frozen, the blur capture is not updated even if
 * underlying content changes. Useful during animations.
 *
 * @param window The window to freeze effects in.
 */
+ (void)beginFreezingInWindow:(NSWindow *)window;

/**
 * Ends freezing visual effect updates in a window.
 *
 * @param window The window to unfreeze.
 */
+ (void)endFreezingInWindow:(NSWindow *)window;

#pragma mark - Appearance

/**
 * Returns a representative color for a material.
 *
 * Useful for determining a solid fallback color when
 * the visual effect cannot be rendered.
 *
 * @param material The material to get a color for.
 * @param isActive Whether the window is active.
 * @return A representative NSColor for the material.
 */
+ (nullable NSColor *)_representativeColorForMaterial:(NSVisualEffectMaterial)material
                                             isActive:(BOOL)isActive;

/**
 * Returns the preferred appearance for the view.
 *
 * May differ from the view's actual appearance based on
 * material settings and window state.
 */
- (nullable NSAppearance *)_preferredAppearance;

/**
 * Whether the view should use the active (key window) appearance.
 *
 * Returns YES if the view should render as if its window is active,
 * regardless of actual window state.
 */
- (BOOL)_shouldUseActiveAppearance;

#pragma mark - Accessibility

/**
 * Whether to use accessibility-friendly colors.
 *
 * When YES, uses higher contrast colors for better accessibility.
 */
- (BOOL)_useAccessibilityColors;

@end

NS_ASSUME_NONNULL_END

#endif /* NSVisualEffectViewPrivate_h */
