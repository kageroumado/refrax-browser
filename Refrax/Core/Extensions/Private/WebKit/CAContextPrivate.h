/**
 * CAContextPrivate.h
 * Refrax Browser
 *
 * Private CAContext APIs for accessing rendering context information.
 *
 * CAContext represents a rendering context that the WindowServer uses to
 * composite layers. Each window has an associated CAContext with a unique
 * `contextId` that can be used for cross-window layer operations.
 *
 * ## Usage in Refrax
 *
 * CAContext is used for:
 * - Getting the `contextId` for cross-window CAPortalLayer mirroring
 * - Identifying which rendering context a layer belongs to
 *
 * ## Cross-Window Portal Layers
 *
 * When portaling a layer from a different window, simply setting `sourceLayer`
 * is insufficient. You must also set `sourceContextId` on the CAPortalLayer:
 *
 * @code
 * CAContext *sourceContext = (CAContext *)sourceLayer.context;
 * if (sourceContext) {
 *     portal.sourceContextId = sourceContext.contextId;
 *     portal.sourceLayer = sourceLayer;
 * }
 * @endcode
 *
 * ## References
 *
 * - QuartzCore/CAContext.h (private header)
 * - WebKit: Source/WebCore/platform/graphics/cocoa/WebCoreCALayerExtras.mm
 */

#import <QuartzCore/QuartzCore.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - CAContext

@class CAHostingToken;

/**
 * A rendering context for Core Animation layer compositing.
 *
 * `CAContext` represents a connection to the WindowServer's compositing engine.
 * Each window typically has one CAContext that manages the rendering of its
 * layer tree. The context provides a unique identifier (`contextId`) that can
 * be used for cross-process and cross-window layer operations.
 *
 * ## Context Types
 *
 * - **Local Context**: Created within the current process for in-process rendering
 * - **Remote Context**: Created for cross-process rendering (e.g., GPU process)
 *
 * ## Availability
 *
 * Available since macOS 10.10 (Yosemite), but undocumented.
 */
@interface CAContext : NSObject

#pragma mark - Context Identification

/**
 * The unique identifier for this rendering context.
 *
 * This 32-bit identifier is assigned by the WindowServer and uniquely
 * identifies this context across all processes. It can be used with:
 * - `CALayerHost.contextId` to host remote content
 * - `CAPortalLayer.sourceContextId` for cross-window portaling
 *
 * A value of `0` typically indicates an invalid or uninitialized context.
 */
@property (readonly) uint32_t contextId;

/**
 * A token-based identifier for secure context access.
 *
 * CAHostingToken provides a more secure alternative to raw contextId,
 * as tokens can be scoped and revoked.
 */
@property (readonly, nonatomic, nullable) CAHostingToken *hostingToken;

#pragma mark - Layer Management

/**
 * The root layer of this context's layer tree.
 *
 * All layers added to this context should be descendants of this layer.
 * Setting this property replaces the entire layer tree.
 */
@property (retain, nullable) CALayer *layer;

#pragma mark - Display Configuration

/**
 * The display number for this context.
 *
 * Identifies which physical display this context renders to.
 */
@property uint32_t displayNumber;

/**
 * A bitmask of displays this context can render to.
 */
@property uint32_t displayMask;

/**
 * The display identifier for this context.
 */
@property (readonly) uint32_t displayId;

/**
 * The GPU registry ID for the GPU rendering this context.
 */
@property unsigned long long GPURegistryID;

#pragma mark - Event Handling

/**
 * A bitmask of events this context receives.
 */
@property uint32_t eventMask;

#pragma mark - Security

/**
 * Whether this context is secure (protected content).
 *
 * Secure contexts prevent their content from being captured or recorded.
 */
@property (readonly, getter=isSecure) BOOL secure;

/**
 * Process ID that is allowed to host this context.
 *
 * When set, only the specified process can create a CALayerHost for this context.
 * Set to `-1` to allow any process.
 */
@property int restrictedHostProcessId;

#pragma mark - Rendering Options

/**
 * The color space for rendering.
 */
@property (nullable) CGColorSpaceRef colorSpace;

/**
 * Whether to color match untagged content.
 */
@property BOOL colorMatchUntaggedContent;

/**
 * The pixel format for rendered content.
 */
@property (copy, nullable) NSString *contentsFormat;

/**
 * The priority for committing layer changes.
 */
@property uint32_t commitPriority;

/**
 * The stacking level for this context.
 */
@property float level;

/**
 * Desired dynamic range for HDR content.
 */
@property float desiredDynamicRange;

#pragma mark - State

/**
 * Whether this context is still valid.
 *
 * A context becomes invalid after `invalidate` is called or when
 * the WindowServer connection is lost.
 */
@property (readonly, getter=isValid) BOOL valid;

/**
 * The current commit identifier.
 *
 * Incremented each time layer changes are committed to the WindowServer.
 */
@property (readonly, nonatomic) uint32_t commitId;

#pragma mark - Annotations

/**
 * A debug annotation for this context.
 *
 * Used for debugging and profiling in Instruments.
 */
@property (copy, nullable) NSString *annotation;

/**
 * Additional metadata for this context.
 */
@property (copy, nullable) NSDictionary *payload;

/**
 * Options used to create this context.
 */
@property (readonly, nullable) NSDictionary *options;

#pragma mark - Lifecycle

/**
 * Whether to zombify this context on invalidation.
 *
 * When `YES`, the context remains visible (frozen) after invalidation
 * rather than disappearing immediately.
 */
@property BOOL zombifyOnInvalidate;

/**
 * The region of interest that should remain unobscured.
 */
@property CGRect unobscuredRegionOfInterest;

/**
 * Whether occlusion clears the event shape.
 */
@property BOOL occlusionClearsEventShape;

#pragma mark - Class Methods

/**
 * Returns all active contexts in this process.
 */
+ (NSArray<CAContext *> *)allContexts;

/**
 * Creates a remote context for cross-process rendering.
 */
+ (nullable CAContext *)remoteContext;

/**
 * Creates a remote context with options.
 */
+ (nullable CAContext *)remoteContextWithOptions:(nullable NSDictionary *)options;

/**
 * Creates a local context for in-process rendering.
 */
+ (nullable CAContext *)localContext;

/**
 * Creates a local context with options.
 */
+ (nullable CAContext *)localContextWithOptions:(nullable NSDictionary *)options;

/**
 * Retrieves an existing context by its identifier.
 *
 * @param contextId The context identifier to look up.
 * @return The matching context, or nil if not found.
 */
+ (nullable CAContext *)contextWithId:(uint32_t)contextId;

/**
 * Returns the current context for the calling thread.
 */
+ (nullable CAContext *)currentContext;

#pragma mark - Instance Methods

/**
 * Invalidates this context, releasing WindowServer resources.
 *
 * After invalidation, the context cannot be used for rendering.
 */
- (void)invalidate;

/**
 * Invalidates all pending fences.
 */
- (void)invalidateFences;

/**
 * Waits for rendering to complete.
 *
 * @param timeout Maximum time to wait in seconds.
 * @return YES if rendering completed, NO if timeout expired.
 */
- (BOOL)waitForRenderingWithTimeout:(double)timeout;

/**
 * Waits for a specific commit to complete.
 *
 * @param commitId The commit identifier to wait for.
 * @param timeout Maximum time to wait in seconds.
 * @return YES if commit completed, NO if timeout expired.
 */
- (BOOL)waitForCommitId:(uint32_t)commitId timeout:(double)timeout;

/**
 * Orders this context above another context.
 *
 * @param contextId The context to order above.
 */
- (void)orderAbove:(uint32_t)contextId;

/**
 * Orders this context below another context.
 *
 * @param contextId The context to order below.
 */
- (void)orderBelow:(uint32_t)contextId;

@end

#pragma mark - CALayer Context Extension

/**
 * CALayer extension for accessing the rendering context.
 */
@interface CALayer (CAContextAccess)

/**
 * The CAContext this layer's tree is rendered in.
 *
 * Returns the rendering context for the window containing this layer,
 * or nil if the layer is not attached to a window.
 *
 * This is useful for getting the `contextId` needed for cross-window
 * CAPortalLayer operations:
 *
 * @code
 * CAContext *ctx = (CAContext *)layer.context;
 * if (ctx) {
 *     portalLayer.sourceContextId = ctx.contextId;
 * }
 * @endcode
 */
- (nullable CAContext *)context;

@end

NS_ASSUME_NONNULL_END
