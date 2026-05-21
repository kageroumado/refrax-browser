/**
 * WKThumbnailViewPrivate.h
 * Refrax Browser
 *
 * Private WebKit API for efficient tab thumbnail generation.
 *
 * `_WKThumbnailView` is WebKit's internal mechanism for rendering scaled-down
 * snapshots of web pages, optimized for tab preview displays.
 *
 * ## Advantages Over takeSnapshot:
 * - Uses shared backing stores when possible (memory efficient)
 * - Renders at reduced resolution based on scale factor
 * - Automatic update handling when content changes
 * - Optimized for repeated use (tab switchers)
 *
 * ## Memory Management
 * The thumbnail view maintains its own backing store. For best performance:
 * - Set `exclusivelyUsesSnapshot = YES` for static previews
 * - Set `shouldKeepSnapshotWhenRemovedFromSuperview = YES` for caching
 * - Use appropriate `scale` values (0.25 is typical for tab thumbnails)
 *
 * ## Thread Safety
 * All APIs must be called on the main thread.
 *
 * ## Source Reference
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKThumbnailView.h
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/_WKThumbnailView.mm
 *
 * Last verified: WebKit trunk (December 2024)
 */

#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

#if TARGET_OS_OSX

#pragma mark - _WKThumbnailView

/**
 * A view that displays an efficient thumbnail of a WKWebView's content.
 *
 * This class renders a scaled-down version of a web view's content,
 * suitable for tab previews, visual bookmarks, or page overviews.
 *
 * ## Creation
 * @code
 * _WKThumbnailView *thumbnail = [[_WKThumbnailView alloc] initWithFrame:frame
 *                                                         fromWKWebView:webView];
 * thumbnail.scale = 0.25;
 * thumbnail.maximumSnapshotSize = CGSizeMake(320, 200);
 * thumbnail.exclusivelyUsesSnapshot = YES;
 * [containerView addSubview:thumbnail];
 * [thumbnail requestSnapshot];
 * @endcode
 *
 * ## Snapshot Lifecycle
 * 1. Create thumbnail view with `initWithFrame:fromWKWebView:`
 * 2. Configure properties (scale, maxSize, etc.)
 * 3. Call `requestSnapshot` to capture content
 * 4. View updates automatically when snapshot is ready
 * 5. Call `requestSnapshot` again when content may have changed
 *
 * ## Automatic Deferral
 * If `requestSnapshot` is called while a snapshot is already being captured,
 * the new request is automatically deferred until the current one completes.
 * This prevents unnecessary duplicate work.
 *
 * ## Availability
 * macOS 10.10+ (macOS only, not available on iOS)
 */
API_AVAILABLE(macos(10.10))
@interface _WKThumbnailView : NSView

#pragma mark - Initialization

/**
 * Creates a thumbnail view for the specified web view.
 *
 * @param frame The frame rectangle for the thumbnail view.
 * @param webView The web view to capture thumbnails from.
 * @return An initialized thumbnail view.
 *
 * ## Note
 * The thumbnail view maintains a reference to the web view but does not
 * retain it. Ensure the web view remains valid while using the thumbnail.
 */
- (instancetype)initWithFrame:(NSRect)frame fromWKWebView:(WKWebView *)webView;

#pragma mark - Configuration

/**
 * The scale factor for the thumbnail rendering.
 *
 * A scale of 1.0 renders at full resolution. A scale of 0.25 renders
 * at 1/4 resolution (1/16 the pixels), significantly reducing memory usage.
 *
 * ## Recommended Values
 * - Tab thumbnails: 0.25 (good balance of quality and memory)
 * - Quick previews: 0.1 - 0.15
 * - High-quality previews: 0.5
 *
 * ## Default Value
 * 1.0 (full resolution)
 */
@property (nonatomic) CGFloat scale;

/**
 * The maximum size for snapshot rendering.
 *
 * Snapshots larger than this size will be scaled down proportionally.
 * This provides an additional memory cap beyond the scale factor.
 *
 * ## Usage
 * @code
 * thumbnail.maximumSnapshotSize = CGSizeMake(320, 200);
 * @endcode
 */
@property (nonatomic) CGSize maximumSnapshotSize;

/**
 * Whether the view exclusively uses snapshots (static images) vs live layer reparenting.
 *
 * ## When YES (Recommended for caching):
 * - The view ONLY displays static CGImage snapshots stored in `layer.contents`
 * - When added to a window, automatically calls `requestSnapshot` if needed
 * - No connection to the source WKWebView's rendering layers
 * - Snapshot persists independently of the WKWebView's state
 * - Combined with `shouldKeepSnapshotWhenRemovedFromSuperview = YES`, snapshots remain cached
 *
 * ## When NO (Live mode):
 * - When added to a window, the WKWebView's actual CALayer sublayers are reparented into this view
 * - You see live web content, not a static image
 * - When removed from window or WKWebView disconnects, live layers are removed
 * - Falls back to snapshot ONLY if `layer.contents` has a cached image
 * - This mode is NOT suitable for caching - the "live" content disappears quickly
 *
 * ## IMPORTANT
 * The "gray view" problem occurs when using NO: the live layers disconnect but no
 * snapshot was cached. For tab previews and caching, always use YES.
 *
 * Default: NO
 */
@property (nonatomic) BOOL exclusivelyUsesSnapshot;

/**
 * Whether to retain the snapshot when removed from the view hierarchy.
 *
 * When YES, the snapshot is kept in memory when the thumbnail view is
 * removed from its superview. This allows instant display when re-added,
 * at the cost of memory usage.
 *
 * When NO, the snapshot is released when removed from superview.
 *
 * ## Recommendation
 * Set to YES for tab switchers that frequently show/hide thumbnails.
 */
@property (nonatomic) BOOL shouldKeepSnapshotWhenRemovedFromSuperview;

/**
 * Override background color for the thumbnail.
 *
 * Use this to set a consistent background color while the snapshot is
 * loading or if the web content has a transparent background.
 *
 * @return The override color, or nil to use the default.
 */
@property (strong, nonatomic, nullable) NSColor *overrideBackgroundColor;

#pragma mark - Snapshot State

/**
 * The size of the current snapshot in pixels.
 *
 * This reflects the actual rendered size, which may differ from
 * `maximumSnapshotSize` based on content aspect ratio.
 *
 * @return The current snapshot size, or CGSizeZero if no snapshot exists.
 */
@property (nonatomic, readonly) CGSize snapshotSize;

#pragma mark - Snapshot Capture

/**
 * Requests a new snapshot of the web view's content.
 *
 * The snapshot is rendered asynchronously. The view automatically updates
 * when the snapshot is complete - no completion handler is needed.
 *
 * ## Deferral Behavior
 * If called while a snapshot capture is in progress, the request is
 * automatically queued and processed when the current capture completes.
 * This prevents redundant work from rapid consecutive calls.
 *
 * ## When to Call
 * - After adding the view to the hierarchy
 * - After significant web content changes (navigation, scroll)
 * - When the web view becomes visible after being hidden
 *
 * ## Implementation Note
 * Internally, this calls `WebPageProxy::takeSnapshot()` with the configured
 * scale and size constraints.
 */
- (void)requestSnapshot;

@end

#pragma mark - _WKThumbnailView Internal

/**
 * Internal interface for _WKThumbnailView.
 *
 * These methods are used by WebKit internally. Do not call directly
 * unless you understand the implications.
 */
@interface _WKThumbnailView (WKThumbnailViewInternal)

/**
 * Sets the CALayer used for displaying the thumbnail.
 *
 * @param layer The layer containing the snapshot image.
 *
 * @warning This is called internally by WebKit. Do not call directly.
 */
- (void)_setThumbnailLayer:(nullable CALayer *)layer;

/**
 * Sets whether the view is waiting for a snapshot.
 *
 * @param waiting YES if waiting for snapshot completion.
 *
 * @warning This is called internally by WebKit. Do not call directly.
 */
- (void)_setWaitingForSnapshot:(BOOL)waiting;

@end

#endif /* TARGET_OS_OSX */

NS_ASSUME_NONNULL_END
