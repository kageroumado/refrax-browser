/**
 * QuartzCoreSPI.h
 * Refrax Browser
 *
 * Private QuartzCore/CoreAnimation APIs for advanced layer compositing.
 *
 * These APIs enable layer mirroring and remote layer hosting, which are essential
 * for multi-window tab display and screen sharing features in Refrax.
 *
 * ## Overview
 *
 * - `CAPortalLayer`: Mirrors another layer's content without duplicating backing store
 * - `CALayerHost`: Hosts content from a remote CAContext (cross-process rendering)
 * - `CABackdropLayer`: Provides blur/vibrancy effects for translucent UI
 *
 * ## Usage in Refrax
 *
 * `CAPortalLayer` is used for:
 * - Displaying tab previews in the tab bar without re-rendering
 * - Showing the same tab in multiple windows (only one is interactive)
 * - Creating screen share windows that mirror a single tab
 *
 * ## References
 *
 * - WebKit: Source/WebCore/PAL/pal/spi/cocoa/QuartzCoreSPI.h
 * - WebKit: Source/WebCore/platform/graphics/cocoa/WebCoreCALayerExtras.mm
 */

#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - CAPortalLayer

@protocol CABackdropLayerDelegate;

/**
 * A layer that mirrors the visual content of another layer.
 *
 * `CAPortalLayer` displays a live copy of its `sourceLayer`'s content
 * without duplicating the backing store. This is ideal for thumbnails,
 * previews, and multi-view display of the same content.
 *
 * ## How It Works
 *
 * The portal layer creates a visual reference to the source layer's
 * composited content. When the source updates, the portal automatically
 * reflects those changes. No additional memory is consumed for the
 * mirrored content.
 *
 * ## Limitations
 *
 * - **Read-only**: Input events do not propagate to the source layer
 * - **Same process**: Source must be in the same process as the portal
 * - **Performance**: Many portals of the same source may impact compositing
 * - **Transforms**: Complex source transforms may not render correctly
 *
 * ## Example
 *
 * @code
 * // Create a thumbnail of a WKWebView's content
 * CAPortalLayer *portal = [CAPortalLayer layer];
 * portal.sourceLayer = webView.layer;
 * portal.matchesTransform = YES;
 * portal.frame = thumbnailFrame;
 * [containerLayer addSublayer:portal];
 * @endcode
 *
 * ## Availability
 *
 * Available since macOS 10.12 (Sierra), but undocumented.
 */
@interface CAPortalLayer : CALayer

/**
 * The layer whose content to mirror.
 *
 * Setting this property establishes a visual link between the portal
 * and the source. The portal displays whatever the source layer renders,
 * including all sublayers and effects.
 *
 * Set to `nil` to disconnect the portal and display nothing.
 *
 * - Note: The source layer is held weakly to prevent retain cycles.
 */
@property (weak, nullable) CALayer *sourceLayer;

/**
 * The render ID of the source layer for cross-context portaling.
 *
 * Used when the source layer is in a different CAContext. This allows
 * portaling content across process boundaries when combined with `sourceContextId`.
 */
@property unsigned long long sourceLayerRenderId;

/**
 * The context ID of the source layer's CAContext.
 *
 * When set, allows the portal to reference a layer in a different CAContext,
 * enabling cross-process layer mirroring.
 */
@property uint32_t sourceContextId;

/**
 * Whether to hide the source layer when the portal is visible.
 *
 * When `YES`, the source layer becomes invisible while the portal displays
 * its content. This is useful for "moving" content between locations without
 * duplicating the visual.
 *
 * Default is `NO`.
 *
 * - Note: Only available on macOS 13.0+
 */
@property BOOL hidesSourceLayer API_AVAILABLE(macos(13.0));

/**
 * Scale factor applied to the source layer's opacity.
 *
 * Allows dimming the portaled content without affecting the source.
 * Default is `1.0`.
 */
@property float sourceLayerOpacityScale;

/**
 * Whether to match the source layer's opacity.
 *
 * When `YES`, the portal's opacity is synchronized with the source layer's
 * opacity, preserving transparency effects.
 *
 * Default is `NO`.
 */
@property BOOL matchesOpacity;

/**
 * Whether to match the source layer's position.
 *
 * When `YES`, the portal's position is synchronized with the source layer's
 * position in its parent coordinate space. This is useful when the portal
 * should track the source layer's movement.
 *
 * Default is `NO`.
 */
@property BOOL matchesPosition;

/**
 * Whether to match the source layer's transform.
 *
 * When `YES`, the portal applies the same transform as the source layer,
 * preserving rotation, scale, and other transformations.
 *
 * Default is `NO`. Set to `YES` for accurate visual mirroring.
 */
@property BOOL matchesTransform;

/**
 * Whether backdrop groups from the source layer affect this portal.
 *
 * When `YES`, backdrop effects (blur, vibrancy) from the source are
 * properly composited in the portal.
 *
 * Default is `NO`.
 */
@property BOOL allowsBackdropGroups;

/**
 * Whether the portal can display content from a different display.
 *
 * When `YES`, allows portaling content that resides on another display/screen.
 *
 * Default is `NO`.
 */
@property BOOL crossDisplay;

/**
 * Whether to exclude separated (offscreen) content from the portal.
 *
 * Default is `NO`.
 */
@property BOOL excludeSeparated;

/**
 * Whether the portal is allowed in context transform calculations.
 *
 * Affects how the portal participates in the layer hierarchy's
 * coordinate space transformations.
 */
@property BOOL allowedInContextTransform;

/**
 * Dictionary of property overrides to apply to the portaled content.
 *
 * Allows selectively overriding properties of the source layer
 * when displayed through this portal.
 */
@property (copy, nullable) NSDictionary *overrides;

/**
 * Whether to hide the source layer in other portals.
 *
 * When `YES`, the source layer is hidden only in other CAPortalLayer
 * instances, not in the original layer tree.
 */
@property BOOL hidesSourceLayerInOtherPortals;

@end

#pragma mark - CALayerHost

@class CAHostingToken;

/**
 * A layer that hosts content from a remote CAContext.
 *
 * `CALayerHost` displays content rendered in another process by referencing
 * a `CAContext`'s identifier. This is how WebKit displays GPU-process-rendered
 * web content in the UI process.
 *
 * ## How It Works
 *
 * 1. A remote process creates a `CAContext` and renders content into it
 * 2. The remote process shares the context's `contextId` with the host process
 * 3. The host process creates a `CALayerHost` with that `contextId`
 * 4. The WindowServer composites the remote content into the host's layer tree
 *
 * ## Security
 *
 * The remote process must explicitly allow hosting via `CAContext` configuration.
 * The `inheritsSecurity` property controls whether the host inherits the remote
 * context's security attributes.
 *
 * ## Example
 *
 * @code
 * // Host content from a remote GPU process
 * CALayerHost *host = [CALayerHost layer];
 * host.contextId = remoteContextId;
 * host.preservesFlip = YES;
 * host.frame = contentFrame;
 * [containerLayer addSublayer:host];
 * @endcode
 *
 * ## Availability
 *
 * Available since macOS 10.10 (Yosemite), but undocumented.
 */
@interface CALayerHost : CALayer

/**
 * The context ID of the remote CAContext to host.
 *
 * This 32-bit identifier uniquely identifies a `CAContext` created in
 * another process. The context must be configured to allow remote hosting.
 *
 * Set to `0` to disconnect from the remote context.
 */
@property uint32_t contextId;

/**
 * A token-based alternative to contextId for secure hosting.
 *
 * `CAHostingToken` provides a more secure way to establish layer hosting
 * connections, as tokens can be scoped and revoked.
 */
@property (retain, nonatomic, nullable) CAHostingToken *hostingToken;

/**
 * Whether to inherit security attributes from the hosted context.
 *
 * When `YES`, the host layer inherits the security configuration of the
 * remote context, including whether it can be captured or recorded.
 *
 * Default is `NO`.
 */
@property BOOL inheritsSecurity;

/**
 * Whether to render the hosted content asynchronously.
 *
 * When `YES`, the hosted content is rendered on a separate timeline,
 * which can improve performance but may introduce latency.
 *
 * Default is `NO`.
 */
@property BOOL rendersAsynchronously;

/**
 * Whether the asynchronously rendered content is opaque.
 *
 * Only relevant when `rendersAsynchronously` is `YES`. Allows
 * optimizations when the content has no transparency.
 */
@property BOOL asynchronousOpaque;

/**
 * Specific times at which to render asynchronous content.
 *
 * An array of render timestamps for precise control over when
 * asynchronous content is composited.
 */
@property (copy, nullable) NSArray *asynchronousRenderTimes;

/**
 * The period between asynchronous render updates.
 *
 * Controls the refresh rate of asynchronously rendered content.
 */
@property double asynchronousRenderPeriod;

/**
 * Maximum Average Picture Level for HDR content.
 *
 * Used for tone mapping HDR content when hosting HDR-capable contexts.
 */
@property float asynchronousRenderMaxAPL;

/**
 * Strength of the APL limiting for HDR content.
 */
@property float asynchronousRenderMaxAPLStrength;

/**
 * Whether the host resizes the hosted context to match its bounds.
 *
 * When `YES`, the hosted context is resized to fit the host layer's frame.
 *
 * Default is `NO`.
 */
@property BOOL resizesHostedContext;

/**
 * Whether to preserve the flip state of the hosted content.
 *
 * Core Animation layers can be "flipped" (y-axis inverted) for compatibility
 * with different coordinate systems. When `YES`, the host preserves whatever
 * flip state the remote content has.
 *
 * Default is `NO`. Set to `YES` when hosting WebKit content to ensure
 * correct orientation.
 */
@property BOOL preservesFlip;

/**
 * Whether hit testing stops accumulating transforms at this layer.
 *
 * When `YES`, hit test coordinate transforms do not propagate
 * through this layer, useful for complex hosting scenarios.
 */
@property BOOL stopsHitTestTransformAccumulation;

/**
 * Whether to stop validating secure superlayers at this layer.
 *
 * Affects the security validation chain for protected content.
 */
@property BOOL stopsSecureSuperlayersValidation;

/**
 * Whether to transform the hosted content to screen space.
 *
 * When `YES`, the hosted content is transformed to align with
 * screen coordinates rather than layer coordinates.
 */
@property BOOL transformsToScreenSpace;

/**
 * Whether this layer host is sequestered from normal compositing.
 *
 * Sequestered layers are composited separately and can be used
 * for security isolation.
 */
@property BOOL sequestered;

/**
 * The zombification mode for the hosted content.
 *
 * Controls what happens to the hosted content when the remote
 * context becomes unavailable (e.g., process crash).
 */
@property (copy, nullable) NSString *zombificationMode;

/**
 * Requests an authoritative hosting token from the WindowServer.
 *
 * Called to establish a verified connection to the hosted context.
 */
- (void)setNeedsAuthoritativeHostingToken;

@end

#pragma mark - CABackdropLayer

/**
 * A layer that provides blur and vibrancy effects for content behind it.
 *
 * `CABackdropLayer` samples the content beneath it in the layer hierarchy
 * and applies visual effects like Gaussian blur. This is used for translucent
 * UI elements like sidebars, sheets, and popovers.
 *
 * ## How It Works
 *
 * The backdrop layer captures a snapshot of underlying content and applies
 * configurable filters. The result is composited beneath the layer's own
 * content, creating the "frosted glass" effect.
 *
 * ## Backdrop Groups
 *
 * Backdrop layers can be organized into groups using `groupName`. Layers in
 * the same group share a single backdrop capture, improving performance when
 * multiple translucent elements need the same background content.
 *
 * ## Performance
 *
 * Backdrop layers are GPU-accelerated but can be expensive when:
 * - The underlying content changes frequently
 * - Multiple backdrop layers overlap
 * - Large blur radii are used
 *
 * ## Example
 *
 * @code
 * CABackdropLayer *backdrop = [CABackdropLayer layer];
 * backdrop.windowServerAware = YES;
 * backdrop.frame = panelFrame;
 * // Add blur filter
 * backdrop.filters = @[[CIFilter filterWithName:@"CIGaussianBlur"]];
 * [containerLayer addSublayer:backdrop];
 * @endcode
 *
 * ## Availability
 *
 * Available since macOS 10.10 (Yosemite), but undocumented.
 */
@interface CABackdropLayer : CALayer

/**
 * Whether the backdrop layer is enabled.
 *
 * When `NO`, the layer does not capture or display backdrop content.
 * Default is `YES`.
 */
@property BOOL enabled;

/**
 * The name of the backdrop group this layer belongs to.
 *
 * Layers with the same group name share backdrop capture data,
 * reducing memory and GPU usage for multiple translucent elements.
 */
@property (copy, nullable) NSString *groupName;

/**
 * Whether the group name is in the global namespace.
 *
 * When `YES`, the group name is resolved globally across all contexts.
 * When `NO`, the group is scoped to `groupNamespace`.
 *
 * Default is `NO`.
 */
@property BOOL usesGlobalGroupNamespace;

/**
 * The namespace for the backdrop group.
 *
 * Used to scope group names when `usesGlobalGroupNamespace` is `NO`.
 */
@property (copy, nullable) NSString *groupNamespace;

/**
 * Scale factor applied to the backdrop capture.
 *
 * Values less than 1.0 reduce the resolution of the captured content,
 * which can improve performance at the cost of quality.
 *
 * Default is `1.0`.
 */
@property double scale;

/**
 * The rectangle in the layer's coordinate space to capture as backdrop.
 *
 * When set, only this region of the underlying content is captured.
 * By default, the entire layer bounds are used.
 */
@property CGRect backdropRect;

/**
 * Additional margin around the backdrop capture area.
 *
 * Extends the capture area beyond the layer bounds, useful for
 * blur effects that need content from outside the visible area.
 */
@property double marginWidth;

/**
 * Whether to disable backdrop blurs that are fully occluded.
 *
 * When `YES`, backdrop layers that are completely covered by opaque
 * content are disabled for performance.
 *
 * Default is `NO`.
 */
@property BOOL disablesOccludedBackdropBlurs;

/**
 * Whether this layer only captures but does not display the backdrop.
 *
 * When `YES`, the layer captures backdrop content for use by other
 * layers (via groups) but does not render it itself.
 *
 * Default is `NO`.
 */
@property BOOL captureOnly;

/**
 * Whether to allow applying filters in-place.
 *
 * When `YES`, filters may be applied directly to the captured content
 * without an intermediate buffer. Can improve performance.
 *
 * Default is `NO`.
 */
@property BOOL allowsInPlaceFiltering;

/**
 * Whether to reduce the bit depth of the captured backdrop.
 *
 * When `YES`, the capture uses a lower bit depth format, reducing
 * memory usage at the cost of color precision.
 *
 * Default is `NO`.
 */
@property BOOL reducesCaptureBitDepth;

/**
 * Whether to ignore screen clipping when capturing.
 *
 * When `YES`, content outside the visible screen area can be captured.
 *
 * Default is `NO`.
 */
@property BOOL ignoresScreenClip;

/**
 * Whether to preallocate the screen area for capture.
 *
 * When `YES`, memory for the capture is allocated in advance,
 * reducing latency when the backdrop becomes visible.
 *
 * Default is `NO`.
 */
@property BOOL preallocatesScreenArea;

/**
 * Whether the layer uses inverse mesh rendering.
 *
 * Affects how the backdrop content is composited, particularly
 * for complex layer hierarchies.
 */
@property BOOL inverseMeshed;

/**
 * The amount of edge bleeding for the backdrop effect.
 *
 * Controls how far blur effects extend beyond the layer's bounds.
 */
@property double bleedAmount;

/**
 * Whether the backdrop samples content from the window server.
 *
 * When `YES`, the backdrop can sample content from other windows and
 * the desktop, not just layers in the same window. This enables effects
 * like desktop blur behind translucent windows.
 *
 * When `NO`, the backdrop only samples content from layers below it in
 * the same layer tree.
 *
 * Default is `NO`.
 *
 * - Important: Setting this to `YES` may have privacy implications as it
 *   allows the layer to access content from other applications.
 */
@property BOOL windowServerAware;

/**
 * Whether a substitute color can be used when backdrop is unavailable.
 *
 * When `YES` and the backdrop cannot be captured, `substituteColor`
 * is displayed instead.
 *
 * Default is `NO`.
 */
@property BOOL allowsSubstituteColor;

/**
 * The color to display when backdrop capture is unavailable.
 *
 * Only used when `allowsSubstituteColor` is `YES` and the backdrop
 * content cannot be captured.
 */
@property (nullable) CGColorRef substituteColor;

/**
 * Whether to ignore backdrop groups that are offscreen.
 *
 * When `YES`, backdrop groups outside the visible area are not included
 * in the capture.
 *
 * Default is `NO`.
 */
@property BOOL ignoresOffscreenGroups;

/**
 * Zoom factor applied to the backdrop content.
 *
 * Values greater than 1.0 magnify the backdrop, values less than 1.0
 * create a zoomed-out effect.
 *
 * Default is `1.0`.
 */
@property double zoom;

/**
 * Whether to disable the filter cache for this layer.
 *
 * When `YES`, filtered results are not cached, which uses less memory
 * but may reduce performance for complex filters.
 *
 * Default is `NO`.
 */
@property BOOL disableFilterCache;

/**
 * The rate at which the backdrop capture is updated.
 *
 * Higher values result in more frequent updates, consuming more GPU
 * resources but providing smoother animations.
 */
@property double updateRate;

/**
 * Whether to track the luminance of the backdrop content.
 *
 * When `YES`, the layer monitors the brightness of the captured content,
 * which can be used to adapt UI elements for contrast.
 *
 * Default is `NO`.
 */
@property BOOL tracksLuma;

/**
 * Whether to continue tracking luminance when the layer is hidden.
 *
 * Only relevant when `tracksLuma` is `YES`.
 *
 * Default is `NO`.
 */
@property BOOL tracksLumaWhileHidden;

/**
 * The rate at which luminance tracking is updated.
 */
@property double lumaUpdateRate;

/**
 * Whether to apply filters when computing luminance.
 *
 * When `YES`, the layer's filters are applied before computing
 * luminance values.
 *
 * Default is `NO`.
 */
@property BOOL allowsFilteredLuma;

/**
 * The subrect used for luminance calculations.
 *
 * When tracking luminance, only this region is sampled.
 */
@property CGRect lumaSubrect;

/**
 * The delegate for backdrop layer events.
 *
 * Conforms to both `CABackdropLayerDelegate` for backdrop-specific
 * callbacks and `CALayerDelegate` for standard layer delegation.
 */
@property (weak, nullable) id<CABackdropLayerDelegate, CALayerDelegate> delegate;

@end

#pragma mark - CAChameleonLayer

/**
 * A layer that adaptively tints itself based on content behind the window.
 *
 * Used by `NSVisualEffectView` at low opacity (~5%) to add a subtle adaptive
 * color that makes glass effects feel alive and responsive to the environment.
 *
 * No public configuration API beyond what `CALayer` provides.
 */
@interface CAChameleonLayer : CALayer
@end

#pragma mark - CAFilter

/**
 * A private Core Animation filter for applying visual effects.
 *
 * `CAFilter` is used to create and configure filters that can be applied
 * to `CALayer.filters` or `CALayer.backgroundFilters`. Common filters include
 * Gaussian blur, color inversion, and saturation adjustments.
 *
 * ## Available Filter Types
 *
 * - `gaussianBlur`: Blurs the layer content
 * - `colorInvert`: Inverts colors
 * - `colorSaturate`: Adjusts saturation
 * - `luminanceToAlpha`: Converts luminance to alpha
 *
 * ## Filter Parameters (via KVC)
 *
 * Filter parameters are set using `setValue(_:forKey:)`:
 *
 * - `inputRadius` (Double): Blur radius for gaussianBlur
 * - `inputNormalizeEdges` (Bool): Prevents edge darkening during blur
 * - `inputAmount` (Double): Saturation level for colorSaturate
 * - `inputColor` (CGColor): Color for color-based filters
 *
 * ## Usage
 *
 * @code
 * CAFilter *blur = [CAFilter filterWithName:@"gaussianBlur"];
 * [blur setValue:@20.0 forKey:@"inputRadius"];
 * [blur setValue:@YES forKey:@"inputNormalizeEdges"];
 * layer.filters = @[blur];
 * @endcode
 *
 * ## Availability
 *
 * Available since macOS 10.4, but undocumented.
 */
@interface CAFilter : NSObject <NSCopying, NSMutableCopying, NSSecureCoding>

/**
 * Creates a filter with the specified name.
 *
 * @param name The filter type name (e.g., "gaussianBlur").
 * @return A new filter instance, or nil if the filter type is unknown.
 */
+ (nullable instancetype)filterWithName:(NSString *)name;

/**
 * Creates a filter with the specified type (alternative to name).
 *
 * @param type The filter type identifier.
 * @return A new filter instance.
 */
+ (nullable instancetype)filterWithType:(NSString *)type;

/**
 * The filter's name/type.
 */
@property (copy, readonly) NSString *name;
@property (copy, readonly) NSString *type;

/**
 * Whether the filter is enabled.
 *
 * Default is `YES`.
 */
@property (getter=isEnabled) BOOL enabled;

/**
 * Whether to cache the filter output.
 *
 * Caching improves performance for static content.
 */
@property BOOL cachesInputImage;

@end

#pragma mark - CALayer Private Extensions

/**
 * Private CALayer extensions for advanced compositing and rendering control.
 *
 * These properties are present on CALayer but not exposed in the public API.
 * They are derived from runtime analysis of QuartzCore framework.
 */
@interface CALayer (RefraxPrivate)

/**
 * Creates a layer that hosts remote content from a context ID.
 *
 * This is a convenience method that creates and configures a `CALayerHost`
 * for hosting WebKit content from the GPU process.
 *
 * @param contextID The remote CAContext's identifier.
 * @param preservesFlip Whether to preserve the remote content's flip state.
 * @return A configured CALayerHost, or nil if hosting is not available.
 */
+ (nullable CALayer *)_web_renderLayerWithContextID:(uint32_t)contextID
                                shouldPreserveFlip:(BOOL)preservesFlip;

/**
 * Whether this layer is excluded from screen capture.
 *
 * When `YES`, the layer and its sublayers are not captured by screenshot
 * or screen recording APIs. The area appears black or transparent in captures.
 *
 * - Note: This is enforced by the WindowServer and cannot be bypassed.
 */
@property (nonatomic, getter=_isCaptureExcluded, setter=_setCaptureExcluded:) BOOL _captureExcluded
    API_AVAILABLE(macos(14.0));

// MARK: - Compositing Group Properties

/**
 * Whether this layer allows group blending with its sublayers.
 *
 * When `YES`, the layer and its sublayers are composited as a group
 * before being blended with layers below.
 */
@property (nonatomic) BOOL allowsGroupBlending;

/**
 * Whether edge antialiasing is allowed for this layer.
 *
 * When `YES`, edges of the layer can be antialiased for smoother appearance.
 * This is separate from the `edgeAntialiasingMask` property.
 */
@property (nonatomic) BOOL allowsEdgeAntialiasing;

/**
 * Whether in-place filtering is allowed for this layer.
 *
 * When `YES`, filters can be applied in-place without creating
 * intermediate buffers. May affect quality or behavior of some filters.
 */
@property (nonatomic) BOOL allowsInPlaceFiltering;

@end

NS_ASSUME_NONNULL_END
