/**
 * NSThemeFramePrivate.h
 * Refrax Browser
 *
 * Private NSThemeFrame APIs for advanced window chrome customization.
 *
 * NSThemeFrame is the private view class that draws the window frame,
 * including the titlebar, traffic light buttons, and toolbar. These APIs
 * enable precise control over window chrome appearance and behavior.
 *
 * ## Key Features
 *
 * - **Traffic Lights**: Position and reveal amount for window buttons
 * - **Titlebar**: Custom height, transparency, and visibility
 * - **Sidebar Integration**: Divider positions for sidebar layouts
 * - **Button Access**: Direct access to window control buttons
 *
 * ## Accessing NSThemeFrame
 *
 * NSThemeFrame is the window's contentView's superview:
 * ```objc
 * NSView *themeFrame = window.contentView.superview;
 * ```
 *
 * ## App Store Notice
 * These APIs are NOT allowed in App Store submissions.
 *
 * ## Source Reference
 * Derived from AppKit framework headers (macOS 26.1 SDK)
 */

#ifndef NSThemeFramePrivate_h
#define NSThemeFramePrivate_h

#import <AppKit/AppKit.h>
#import "NSSidebarTrackingAdapter-Protocol.h"

NS_ASSUME_NONNULL_BEGIN

@class NSTitlebarContainerView, NSTitlebarView, NSVisualEffectView;

#pragma mark - NSThemeFrame

/**
 * The private frame view class that manages window chrome.
 *
 * NSThemeFrame handles drawing and layout of the window's non-client area,
 * including the titlebar, traffic lights, and toolbar area.
 */
@interface NSThemeFrame : NSView

#pragma mark - Titlebar Height

/**
 * The custom height for the titlebar.
 *
 * Set to 0 to use the system default height. Larger values create
 * more vertical space for custom titlebar content.
 *
 * - Note: This affects the contentLayoutRect and toolbar positioning.
 */
@property (nonatomic) CGFloat customTitlebarHeight;

/**
 * The custom titlebar height saved before entering full screen.
 *
 * Used to restore the titlebar height when exiting full screen mode.
 */
@property (nonatomic) CGFloat customTitlebarHeightPriorToFSMode;

#pragma mark - Traffic Light Buttons

/**
 * The offset applied to the traffic light button group.
 *
 * Positive X moves buttons right, positive Y moves buttons down.
 * This is relative to their default position.
 *
 * ## Example
 * ```objc
 * // Move traffic lights 10pt right and 5pt down
 * themeFrame.stoplightOffset = CGSizeMake(10, 5);
 * ```
 */
@property (nonatomic) CGSize stoplightOffset;

/**
 * The reveal amount for window buttons (0.0 to 1.0).
 *
 * Controls the visibility of traffic light buttons during hover animations.
 * - 0.0: Buttons fully hidden
 * - 1.0: Buttons fully visible
 *
 * - Note: Used for auto-hiding titlebar effects.
 */
@property (nonatomic) CGFloat buttonRevealAmount;

/**
 * Returns the origin point for the close button.
 */
- (CGPoint)_closeButtonOrigin;

/**
 * Returns the origin point for the minimize (collapse) button.
 */
- (CGPoint)_collapseButtonOrigin;

/**
 * Returns the origin point for the zoom button.
 */
- (CGPoint)_zoomButtonOrigin;

/**
 * Returns the origin point for the full screen button.
 */
- (CGPoint)_fullScreenButtonOrigin;

/**
 * Whether the traffic lights should be centered vertically in the titlebar.
 *
 * When YES, buttons are vertically centered regardless of titlebar height.
 */
- (BOOL)_shouldCenterTrafficLights;

#pragma mark - Button Access

/**
 * The window's full screen button.
 *
 * - Note: May be nil if full screen is not supported.
 */
@property (readonly, nullable) NSButton *fullScreenButton;

/**
 * The window's lock button (for document locking).
 *
 * - Note: May be nil if not applicable.
 */
@property (readonly, nullable) NSButton *lockButton;

/**
 * The window's toolbar toggle button.
 *
 * - Note: May be nil if no toolbar is configured.
 */
- (nullable NSButton *)toolbarButton;

/**
 * Creates a new close button for this window style.
 */
- (NSButton *)newCloseButton;

/**
 * Creates a new minimize button for this window style.
 */
- (NSButton *)newMiniaturizeButton;

/**
 * Creates a new zoom button for this window style.
 */
- (NSButton *)newZoomButton;

/**
 * Creates a new full screen button for this window style.
 */
- (NSButton *)newFullScreenButton;

#pragma mark - Button Frame Manipulation

/**
 * Sets the frame origin for a specific window button.
 *
 * Use this to directly position traffic light buttons.
 *
 * @param button The button to position (close, minimize, zoom).
 * @param origin The new origin point for the button.
 */
- (void)_setButton:(NSButton *)button frameOrigin:(CGPoint)origin;

/**
 * Gets the frame rect containing all left-side window buttons.
 *
 * Returns the bounding rect for the traffic light button group
 * in the titlebar view's coordinate space.
 */
- (CGRect)leftButtonGroupFrameInTitlebarView;

#pragma mark - Titlebar Transparency

/**
 * The alpha value of the titlebar.
 *
 * Controls the opacity of the entire titlebar area.
 * Values range from 0.0 (fully transparent) to 1.0 (fully opaque).
 */
@property (nonatomic) CGFloat titlebarAlphaValue;

/**
 * Whether the titlebar is hidden.
 *
 * When YES, the titlebar is not rendered but still occupies space.
 * Different from titlebarAppearsTransparent which only affects rendering.
 */
@property (nonatomic, getter=isTitlebarHidden) BOOL titlebarHidden;

/**
 * Whether safe area insets should be applied for transparent titlebars.
 *
 * When YES, content respects safe area even with transparent titlebar.
 */
@property (nonatomic) BOOL applySafeAreaInsetsForTransparentTitlebar;

#pragma mark - Titlebar Views

/**
 * The container view that holds the titlebar.
 *
 * This view manages the titlebar's position and size.
 */
@property (readonly, nullable) NSTitlebarContainerView *titlebarContainerView;

/**
 * The view that renders the titlebar content.
 *
 * This view contains the title, subtitle, and titlebar accessories.
 */
@property (readonly, nullable) NSTitlebarView *titlebarView;

/**
 * The backdrop view for titlebar blur effects.
 */
@property (readonly, nullable) NSVisualEffectView *_backdropView;

/**
 * The blending mode used for the titlebar.
 *
 * Controls how the titlebar blends with content behind it.
 */
@property (readonly) NSInteger titlebarBlendingMode;

#pragma mark - Sidebar Integration

/**
 * The sidebar tracking adapter used to align the titlebar with a sidebar.
 *
 * Setting this adapter causes the theme frame to read `sidebarDividerPosition`
 * from the adapter during layout. The position is not set directly on NSThemeFrame.
 */
@property (retain, nullable) NSObject<NSSidebarTrackingAdapter> *sidebarTrackingAdapter;

/**
 * Whether the sidebar sits below the toolbar.
 *
 * When YES, the sidebar extends from below the toolbar to the bottom.
 * When NO, the sidebar extends into the titlebar area.
 */
@property (readonly) BOOL _sidebarSitsBelowToolbar;

#pragma mark - Full Screen

/**
 * The amount of titlebar height to hide in full screen mode.
 *
 * Used for animating the titlebar show/hide in full screen.
 */
@property (readonly) CGFloat titleHeightToHideInFullScreen;

/**
 * Whether a floating titlebar is desired.
 *
 * Floating titlebars hover over content rather than pushing it down.
 */
- (BOOL)_wantsFloatingTitlebar;

#pragma mark - Layout Metrics

/**
 * Returns the height of the titlebar.
 */
- (CGFloat)_titlebarHeight;

/**
 * Returns the corner radius of the window.
 */
- (CGFloat)_cornerRadius;

/**
 * The rectangle of the titlebar in the frame view's coordinates.
 */
- (CGRect)titlebarRect;

/**
 * The rectangle of the titlebar including the toolbar area.
 */
- (CGRect)titlebarRectIncludingToolbar;

/**
 * The content rectangle excluding the titlebar and toolbar.
 */
- (CGRect)contentRect;

/**
 * The content layout guide for positioning content.
 */
@property (readonly, nullable) id contentLayoutGuide;

#pragma mark - Toolbar

/**
 * Returns whether the toolbar is currently shown.
 */
- (BOOL)_toolbarIsShown;

/**
 * Returns whether the toolbar is hidden.
 */
- (BOOL)_toolbarIsHidden;

/**
 * Returns the effective toolbar style considering window state.
 */
- (NSInteger)_effectiveToolbarStyle;

/**
 * Whether full-width titlebar is preferred when accessories are visible.
 */
@property (nonatomic) BOOL prefersFullWidthTitlebarWhenAccessoriesVisible;

#pragma mark - Sharing Indicator

/**
 * The sharing indicator view (shown during screen sharing/recording).
 */
@property (retain, nullable) NSView *sharingIndicator;

/**
 * Positions the sharing indicator appropriately in the titlebar.
 */
- (void)_positionSharingIndicator;

@end

#pragma mark - NSTitlebarContainerView

/**
 * Container view that manages titlebar layout and transparency.
 */
@interface NSTitlebarContainerView : NSView

/**
 * Whether the titlebar container is transparent.
 */
@property (nonatomic, getter=isTransparent) BOOL transparent;

/**
 * Whether transparency is allowed in full screen mode.
 */
@property (nonatomic) BOOL transparencyAllowedInFullScreen;

/**
 * Whether the container responds to hit tests when transparent.
 */
@property (nonatomic) BOOL hitTestsWhenTransparent;

/**
 * Whether to draw the bottom divider when transparent.
 */
@property (nonatomic) BOOL drawsBottomDividerWhenTransparent;

/**
 * Whether to draw the bottom separator line.
 */
@property (nonatomic) BOOL drawsBottomSeparator;

/**
 * The reveal amount for window buttons (0.0 to 1.0).
 */
@property (nonatomic) CGFloat buttonRevealAmount;

/**
 * The position of the sidebar divider.
 */
@property (nonatomic) CGFloat sidebarDividerPosition;

/**
 * The position of the trailing sidebar divider.
 */
@property (nonatomic) CGFloat trailingSidebarDividerPosition;

@end

#pragma mark - NSTitlebarView

/**
 * View that renders titlebar content and handles backdrop effects.
 */
@interface NSTitlebarView : NSView

/**
 * Whether the titlebar view is transparent.
 */
@property (nonatomic, getter=isTransparent) BOOL transparent;

/**
 * Whether the window has a leading sidebar.
 */
@property (nonatomic) BOOL hasSidebar;

/**
 * Whether the window has a trailing sidebar.
 */
@property (nonatomic) BOOL hasTrailingSidebar;

/**
 * The blending mode for the titlebar.
 */
@property (nonatomic) NSInteger blendingMode;

/**
 * The group name for titlebar backdrop effects.
 *
 * Used to coordinate backdrop blur with other views.
 */
@property (copy, nonatomic, nullable) NSString *titleGroupName;

/**
 * Sets the material for the titlebar.
 *
 * @param material The NSVisualEffectMaterial to use.
 */
- (void)setMaterial:(NSInteger)material;

/**
 * Updates the titlebar transparency state.
 */
- (void)updateTransparency;

@end

NS_ASSUME_NONNULL_END

#endif /* NSThemeFramePrivate_h */
