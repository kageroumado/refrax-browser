/**
 * NSWindowPrivate.h
 * Refrax Browser
 *
 * Private NSWindow APIs for advanced window customization and control.
 *
 * These APIs enable features like custom corner radii, screenshot capture,
 * titlebar backdrop control, and window layer hosting that are essential
 * for creating a modern browser chrome.
 *
 * ## Key Features
 *
 * - **Corner Radius**: Customize window corner rounding
 * - **Screenshots**: Capture window content programmatically
 * - **Titlebar Control**: Backdrop groups, blur filters, transparency
 * - **Layer Hosting**: WindowServer layer hosting for performance
 * - **Tab Support**: Native window tabbing state and control
 *
 * ## App Store Notice
 * These APIs are NOT allowed in App Store submissions.
 *
 * ## Source Reference
 * Derived from AppKit framework headers (macOS 26.1 SDK)
 */

#ifndef NSWindowPrivate_h
#define NSWindowPrivate_h

#import <AppKit/AppKit.h>

// Forward declaration for private QuartzCore class
@class CAContext;

NS_ASSUME_NONNULL_BEGIN

#pragma mark - NSWindow Private Extensions

@interface NSWindow (RefraxPrivate)

#pragma mark - Corner Radius

/**
 * The current corner radius of the window.
 *
 * This is the actual corner radius being used, which may differ from
 * what was set if the system applies constraints.
 */
@property (readonly) CGFloat _cornerRadius;

/**
 * Sets a custom corner radius for the window.
 *
 * @param radius The desired corner radius in points.
 *
 * - Note: The system may constrain this value based on window style.
 * - Note: Setting to 0 uses the system default for the window style.
 */
- (void)_setCornerRadius:(CGFloat)radius;

/**
 * The effective corner radius after system adjustments.
 *
 * This accounts for any system-imposed constraints or modifications
 * to the requested corner radius.
 */
@property (readonly) CGFloat _effectiveCornerRadius;

/**
 * Sets a custom corner path for non-rectangular window shapes.
 *
 * @param path A CGPath defining the window's corner shape. Pass NULL to reset.
 *
 * - Note: The path should be in window coordinates.
 * - Note: This affects both rendering and hit testing.
 */
- (void)_setCornerPath:(nullable CGPathRef)path;

#pragma mark - Screenshot Capture

/**
 * Captures the window content as a CGImage.
 *
 * @param rect The rectangle to capture in window coordinates.
 * @param options Capture options (see CGWindowListCreateImage options).
 * @return A CGImage of the captured content, or NULL on failure.
 *
 * - Note: Caller is responsible for releasing the returned CGImage.
 */
- (nullable CGImageRef)_cgImageInRect:(CGRect)rect options:(uint32_t)options CF_RETURNS_RETAINED;

/**
 * Captures a screenshot of the entire window.
 *
 * @return A CGImage of the window content, or NULL on failure.
 *
 * - Note: Does not include the window shadow.
 * - Note: Caller is responsible for releasing the returned CGImage.
 */
- (nullable CGImageRef)_cgImageScreenShot CF_RETURNS_RETAINED;

/**
 * Captures a screenshot with advanced options.
 *
 * @param includingShadow Whether to include the window shadow in the capture.
 * @param clipRect The rectangle to clip to, or CGRectNull for full window.
 * @param visualEffectOnly If YES, only capture visual effect views with desktop bleed.
 * @param spaceID The space ID to capture from, or 0 for current space.
 * @return A CGImage of the captured content, or NULL on failure.
 *
 * - Note: Useful for capturing tab thumbnails or sharing previews.
 * - Note: Caller is responsible for releasing the returned CGImage.
 */
- (nullable CGImageRef)_cgImageScreenShotIncludingShadow:(BOOL)includingShadow
                                                clipRect:(CGRect)clipRect
                              visualEffectViewWithDesktopBleedOnly:(BOOL)visualEffectOnly
                                                 spaceID:(uint64_t)spaceID CF_RETURNS_RETAINED;

#pragma mark - Titlebar & Backdrop Control

/**
 * The backdrop group name for the titlebar.
 *
 * Backdrop groups allow multiple views to share a single backdrop capture,
 * improving performance for translucent UI elements.
 */
@property (copy, nullable) NSString *_titlebarBackdropGroupName;

/**
 * Whether titlebar blur filters are disabled.
 *
 * When YES, the titlebar does not apply blur effects, which can improve
 * performance or achieve a specific visual style.
 */
@property (nonatomic) BOOL titlebarBlurFiltersDisabled;

/**
 * The effective alpha value for the titlebar.
 *
 * This is the computed alpha considering window state, animations,
 * and any programmatic adjustments.
 */
@property (readonly) CGFloat _effectiveTitlebarAlphaValue;

/**
 * Sets whether the window title is hidden.
 *
 * @param hidden YES to hide the title, NO to show it.
 *
 * - Note: Different from titleVisibility which affects layout.
 */
- (void)setTitleHidden:(BOOL)hidden;

#pragma mark - Layer Hosting

/**
 * The CAContext for hosting layers in the WindowServer.
 *
 * Used for cross-process layer compositing, such as displaying
 * WebKit GPU-process rendered content.
 */
@property (readonly, weak, nullable) CAContext *_contextForLayerHosting;

/**
 * The CAContext when this window is itself layer-hosted.
 */
@property (readonly, weak, nullable) CAContext *_layerHostedContext;

/**
 * The CAContext for the window's layer tree.
 */
@property (readonly, weak, nullable) CAContext *_windowLayerContext;

/**
 * The transform from layer coordinates to host coordinates.
 */
@property (readonly) CGAffineTransform _layerTransformToHost;

/**
 * Whether the window can host layers in the WindowServer.
 *
 * When YES, the window's layers can be composited by the WindowServer
 * for improved performance with GPU-rendered content.
 *
 * @param server YES to enable WindowServer layer hosting.
 */
- (void)setCanHostLayersInWindowServer:(BOOL)server;

#pragma mark - Blur & Visual Effects

/**
 * The blur radius applied to window content.
 *
 * Used for behind-window blur effects. Set to 0 to disable.
 */
@property (readonly) CGFloat _contentBlurRadius;

/**
 * The bleed amount for backdrop effects.
 *
 * Controls how far backdrop blur extends beyond the window bounds.
 */
@property (readonly) float _backdropBleedAmount;

#pragma mark - Tab Support

/**
 * Whether the tab overview (Exposé-style tab picker) is visible.
 */
@property (readonly) BOOL tabOverviewVisible;

/**
 * Whether the window has a pending miniaturize operation.
 */
@property (readonly) BOOL _hasPendingMiniaturize;

#pragma mark - Cursor & Input

/**
 * Whether cursor rects are active when the window is inactive.
 *
 * When YES, cursor changes occur even when the window is not key.
 * Useful for hover effects in background windows.
 */
@property (nonatomic) BOOL allowsCursorRectsWhenInactive;

#pragma mark - Window Sharing

/**
 * Whether the window has an active sharing session (screen share, AirPlay).
 */
@property (readonly) BOOL hasActiveWindowSharingSession;

#pragma mark - Shadow

/**
 * The shadow offset for the window.
 */
@property (readonly) CGSize _shadowOffset;

/**
 * The shadow blur radius for the window.
 */
@property (readonly) CGSize _shadowRadius;

/**
 * Sets the shadow style for the window.
 *
 * @param style The shadow style to use.
 */
- (void)setShadowStyle:(NSUInteger)style;

#pragma mark - Sidebar Overlay

/**
 * The currently overlaid sidebar view.
 *
 * When a sidebar is in overlay mode, it appears over content instead
 * of pushing it aside. This property tracks that overlay.
 */
@property (retain, nullable) NSView *overlaidSidebar;

/**
 * The currently overlaid inspector view.
 *
 * Similar to overlaidSidebar but for trailing inspector panels.
 */
@property (retain, nullable) NSView *overlaidInspector;

#pragma mark - Traffic Light Button Control

/**
 * Sets the offset for the standard window button group (traffic lights).
 *
 * Use this to move the traffic lights along with a sliding sidebar.
 *
 * @param offset The offset to apply. Positive x moves right, positive y moves down.
 */
- (void)setStandardWindowButtonGroupOffset:(CGSize)offset;

/**
 * Gets the current offset of the standard window button group.
 *
 * @return The current offset of the traffic lights.
 */
- (CGSize)standardWindowButtonGroupOffset;

/**
 * Sets the alpha value for standard window title buttons (traffic lights).
 *
 * Use this to fade traffic lights in/out with sidebar animation.
 *
 * @param value Alpha value from 0.0 (transparent) to 1.0 (opaque).
 */
- (void)setStandardWindowTitleButtonsAlphaValue:(double)value;

/**
 * Gets the current alpha value of standard window title buttons.
 *
 * @return The current alpha value.
 */
- (double)standardWindowTitleButtonsAlphaValue;

/**
 * Toggles the sidebar visibility.
 *
 * Standard AppKit method for sidebar toggling, respects split view configuration.
 *
 * @param sender The sender of the action.
 */
- (void)toggleSidebar:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END

#endif /* NSWindowPrivate_h */
