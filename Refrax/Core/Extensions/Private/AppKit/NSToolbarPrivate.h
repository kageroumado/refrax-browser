/**
 * NSToolbarPrivate.h
 * Refrax Browser
 *
 * Private NSToolbar APIs for advanced toolbar customization.
 *
 * These APIs enable fine-grained control over toolbar appearance and behavior,
 * including autohide behavior, glass effects, and item positioning.
 *
 * ## Key Features
 *
 * - **Autohide**: Control toolbar autohide in full screen mode
 * - **Glass Effects**: Force AVPlayer glass variant style
 * - **Item Management**: Control immovable items and positioning
 * - **Context Menu**: Control toolbar context menu availability
 * - **Full Screen**: Manage full screen auxiliary views
 * - **Layout**: Access toolbar view for sidebar divider alignment
 *
 * ## App Store Notice
 * These APIs are NOT allowed in App Store submissions.
 *
 * ## Source Reference
 * Derived from AppKit framework headers (macOS 26.1 SDK)
 */

#ifndef NSToolbarPrivate_h
#define NSToolbarPrivate_h

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class NSToolbarView;

@interface NSToolbar (RefraxPrivate)

#pragma mark - Appearance

/**
 * Whether the toolbar uses a bezeled appearance.
 *
 * Bezeled toolbars have a subtle 3D effect that separates them
 * from the window content. Used in some system apps.
 */
@property (nonatomic, getter=isBezeled) BOOL bezeled;

/**
 * Forces the AVPlayer glass variant style for the toolbar.
 *
 * When YES, the toolbar uses the glass material variant typically
 * used in media player interfaces. Part of macOS Tahoe's Liquid Glass.
 */
@property (nonatomic) BOOL _forceAVPlayerGlassVariant;

/**
 * Sets a custom background color for the toolbar.
 *
 * @param color The background color to use, or nil for default.
 *
 * - Note: May not work with all toolbar styles.
 */
- (void)_setBackgroundColor:(nullable NSColor *)color;

/**
 * Controls whether the baseline separator is shown.
 *
 * @param separator NO to hide the baseline separator.
 *
 * The baseline separator is the line between toolbar and content.
 */
- (void)_setDoNotShowBaselineSeparator:(BOOL)separator;

#pragma mark - Autohide & Full Screen

/**
 * The height at which the toolbar triggers autohide behavior.
 *
 * In full screen mode, moving the cursor to this height
 * from the top of the screen reveals the toolbar.
 */
@property (nonatomic) CGFloat _autohideHeight;

/**
 * Disables toolbar autohiding in full screen mode.
 *
 * Call this to keep the toolbar always visible in full screen.
 */
- (void)_disableFullScreenAutohiding;

/**
 * Enables toolbar autohiding in full screen mode.
 *
 * Call this to restore default autohide behavior.
 */
- (void)_enableFullScreenAutohiding;

/**
 * Forces the toolbar to be visible in full screen mode.
 *
 * The toolbar will remain visible until `_disableFullScreenForceVisible` is called.
 */
- (void)_enableFullScreenForceVisible;

/**
 * Stops forcing the toolbar to be visible in full screen mode.
 *
 * Returns to normal autohide behavior.
 */
- (void)_disableFullScreenForceVisible;

#pragma mark - Full Screen Auxiliary View

/**
 * An auxiliary view displayed in full screen mode.
 *
 * This view appears below the toolbar in full screen mode,
 * useful for additional controls or status indicators.
 */
@property (retain, nullable) NSView *_fullScreenAuxiliaryView;

#pragma mark - Layout

/**
 * The toolbar view that hosts item viewers.
 *
 * Use this to set sidebarDividerPosition for native sidebar alignment.
 */
@property (retain) NSToolbarView *_toolbarView;

/**
 * The minimum size for the auxiliary view.
 */
@property (nonatomic) CGSize _auxiliaryViewMinSize;

/**
 * The maximum size for the auxiliary view.
 */
@property (nonatomic) CGSize _auxiliaryViewMaxSize;

/**
 * Forces the auxiliary view to be visible in full screen mode.
 */
- (void)_enableFullScreenAuxiliaryViewForceVisible;

/**
 * Stops forcing the auxiliary view to be visible in full screen mode.
 */
- (void)_disableFullScreenAuxiliaryViewForceVisible;

#pragma mark - Item Management

/**
 * The index of the first item that can be moved by the user.
 *
 * Items before this index are "immovable" and cannot be repositioned
 * during customization. Useful for pinned items like back/forward buttons.
 */
@property (nonatomic) NSInteger _firstMoveableItemIndex;

/**
 * Whether items always enter customization mode on click and drag.
 *
 * When YES, dragging any item immediately starts customization
 * rather than requiring Command-drag or customization mode.
 */
@property (nonatomic) BOOL _customizesAlwaysOnClickAndDrag;

/**
 * Whether the toolbar wants to provide a context menu.
 *
 * - Note: This property does NOT control the toolbar's right-click context menu
 *   shown when clicking the toolbar background. To disable that menu, swizzle
 *   `NSToolbarView.rightMouseDown:` instead (see `ToolbarContextMenuSwizzle`).
 */
@property (nonatomic, getter=_wantsToolbarContextMenu, setter=_setWantsToolbarContextMenu:) BOOL wantsToolbarContextMenu;

/**
 * Whether the toolbar prefers to be shown.
 *
 * This is the toolbar's preference, which may be overridden
 * by user settings or window state.
 */
- (BOOL)_prefersToBeShown;

/**
 * Sets whether the toolbar prefers to be shown.
 *
 * @param shown YES if the toolbar should prefer to be visible.
 */
- (void)_setPrefersToBeShown:(BOOL)shown;

#pragma mark - Size Constraints

/**
 * Returns the maximum size for a search field toolbar item.
 */
- (CGSize)_maximumSizeForSearchFieldToolbarItem;

/**
 * Returns the minimum size for a search field toolbar item.
 */
- (CGSize)_minimumSizeForSearchFieldToolbarItem;

/**
 * Returns the maximum size for a text field toolbar item.
 */
- (CGSize)_maximumSizeForTextFieldToolbarItem;

/**
 * Returns the minimum size for a text field toolbar item.
 */
- (CGSize)_minimumSizeForTextFieldToolbarItem;

/**
 * Returns the minimum window size needed to ensure an item is visible.
 *
 * @param item The toolbar item to check visibility for.
 * @return The minimum window size required.
 */
- (CGSize)_minimumWindowSizeEnsuringVisibilityOfItem:(NSToolbarItem *)item;

#pragma mark - Sidebar Integration

/**
 * Returns the sidebar tracking adapter for split view integration.
 *
 * Used when the toolbar needs to coordinate with sidebar show/hide behavior.
 */
- (nullable id)_sidebarTrackingAdapter;

#pragma mark - Configuration

/**
 * Whether externally persisted defaults are allowed.
 *
 * When YES, toolbar configuration can be saved/loaded from
 * external sources rather than just user defaults.
 */
@property (nonatomic) BOOL _allowsExternallyPersistedDefaults;

/**
 * Saves the current toolbar configuration.
 *
 * Called automatically when autosavesConfiguration is YES
 * and the toolbar configuration changes.
 */
- (void)_autoSaveConfiguration;

/**
 * Updates the configuration if autosave is enabled.
 */
- (void)updateConfigurationIfEnabled;

/**
 * Returns the autosave name used for configuration persistence.
 */
- (nullable NSString *)_configurationAutosaveName;

#pragma mark - Window Access

/**
 * Returns the window containing this toolbar.
 *
 * May differ from the toolbar's assigned window in some cases.
 */
- (nullable NSWindow *)_containingWindow;

/**
 * Returns the logical window for this toolbar.
 *
 * The logical window is the window the toolbar is conceptually
 * attached to, which may differ during window tabbing.
 */
- (nullable NSWindow *)_logicalWindow;

@end

NS_ASSUME_NONNULL_END

#endif /* NSToolbarPrivate_h */
