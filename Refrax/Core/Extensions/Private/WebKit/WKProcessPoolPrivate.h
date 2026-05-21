/**
 * WKProcessPoolPrivate.h
 * Refrax Browser
 *
 * Private WebKit APIs for process pool management and per-process metrics.
 *
 * Provides access to:
 * - Per-process memory (physicalFootprint), CPU time, and state
 * - Process-to-WKWebView mapping (which tabs live in which process)
 * - Process termination and suspension queries
 * - GPU process information
 *
 * ## Key Types
 *
 * `_WKProcessInfo` — base class with pid, state, memory, CPU time.
 * `_WKWebContentProcessInfo` — extends with webViews array, content state,
 *   service/shared worker flags, and per-state time breakdowns.
 *
 * ## Memory Measurement
 *
 * `physicalFootprint` reports Mach `phys_footprint` — the same metric
 * Activity Monitor shows under "Memory" column. This is physical RAM
 * attributed to the process (dirty + compressed + purgeable-in-use),
 * excluding shared clean pages (dylibs, frameworks). Much more accurate
 * than `pti_resident_size` from proc_pidinfo which double-counts shared pages.
 *
 * ## Process Sharing
 *
 * WebKit uses process-per-origin by default, but multiple same-origin
 * tabs may share a process. The `webViews` array on each process info
 * reveals which WKWebViews share that process, enabling:
 * - Accurate process memory display (total for shared tabs)
 * - Estimated per-tab memory (processMemory / tabsInProcess)
 * - Visual grouping of tabs sharing a process
 *
 * ## Thread Safety
 * All APIs must be called on the main thread.
 *
 * ## Source Reference
 * WebKit/Source/WebKit/UIProcess/API/Cocoa/WKProcessPoolPrivate.h
 *
 * Last verified: WebKit trunk (March 2025)
 */

#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Process State

/**
 * Overall scheduling state of a WebKit child process.
 *
 * Reflects the process's priority as managed by the system:
 * - Foreground: Full CPU and memory priority
 * - Background: Reduced priority, timers may be throttled
 * - Suspended: Frozen, no code execution, memory preserved
 */
typedef NS_ENUM(NSInteger, _WKProcessState) {
    _WKProcessStateForeground,
    _WKProcessStateBackground,
    _WKProcessStateSuspended,
} API_AVAILABLE(macos(14.5), ios(17.5), visionos(1.2));

/**
 * Content-level state of a web content process.
 *
 * Distinct from scheduling state — describes the process's role:
 * - Prewarmed: Launched speculatively for fast tab opening, no content yet
 * - Cached: Previously active, content cached for back/forward navigation
 * - Active: Currently hosting one or more WKWebViews with live content
 */
typedef NS_ENUM(NSInteger, _WKWebContentProcessState) {
    _WKWebContentProcessStatePrewarmed,
    _WKWebContentProcessStateCached,
    _WKWebContentProcessStateActive,
} API_AVAILABLE(macos(14.5), ios(17.5), visionos(1.2));

#pragma mark - Process Info

/**
 * Base class for WebKit child process information.
 *
 * Provides system-level metrics for any WebKit child process
 * (web content, GPU, networking).
 */
API_AVAILABLE(macos(14.5), ios(17.5), visionos(1.2))
@interface _WKProcessInfo : NSObject

/// Process identifier.
@property (nonatomic, readonly) pid_t pid;

/// Current scheduling state.
@property (nonatomic, readonly) _WKProcessState state;

/// Cumulative user-mode CPU time in seconds.
@property (nonatomic, readonly) NSTimeInterval totalUserCPUTime;

/// Cumulative system-mode CPU time in seconds.
@property (nonatomic, readonly) NSTimeInterval totalSystemCPUTime;

/// Physical memory footprint in bytes (Mach phys_footprint).
///
/// This is the same metric shown in Activity Monitor's "Memory" column.
/// Includes dirty pages + compressed pages + purgeable-in-use.
/// Does NOT include shared clean pages (dylibs, frameworks).
@property (nonatomic, readonly) size_t physicalFootprint;

@end

#pragma mark - Web Content Process Info

/**
 * Extended information for a web content process.
 *
 * Adds content-specific metadata to the base process info:
 * - Which WKWebViews are hosted in this process
 * - Content state (prewarmed, cached, active)
 * - Whether service/shared workers are running
 * - Time breakdown by scheduling state
 */
API_AVAILABLE(macos(14.5), ios(17.5), visionos(1.2))
@interface _WKWebContentProcessInfo : _WKProcessInfo

/// Content-level state of this process.
@property (nonatomic, readonly) _WKWebContentProcessState webContentState;

/// WKWebView instances hosted in this process.
///
/// Multiple same-origin tabs may share a process. This array reveals
/// the mapping, enabling per-tab memory estimation.
@property (nonatomic, readonly) NSArray<WKWebView *> *webViews;

/// Whether this process is running service workers.
@property (nonatomic, readonly) BOOL runningServiceWorkers;

/// Whether this process is running shared workers.
@property (nonatomic, readonly) BOOL runningSharedWorkers;

/// Cumulative time spent in foreground state (seconds).
@property (nonatomic, readonly) NSTimeInterval totalForegroundTime;

/// Cumulative time spent in background state (seconds).
@property (nonatomic, readonly) NSTimeInterval totalBackgroundTime;

/// Cumulative time spent in suspended state (seconds).
@property (nonatomic, readonly) NSTimeInterval totalSuspendedTime;

@end

#pragma mark - WKProcessPool Private Extensions

@interface WKProcessPool (WKPrivateProcessManagement)

/// Returns information for the GPU process, or nil if not running.
+ (nullable _WKProcessInfo *)_gpuProcessInfo
    API_AVAILABLE(macos(14.5));

/// Returns information for all web content processes.
///
/// Includes active, prewarmed, and cached processes. Each entry's
/// `webViews` array maps the process to its hosted WKWebView instances.
///
/// Note: The WebKit header declares the return type as `NSArray<_WKProcessInfo *>`
/// but the actual objects are `_WKWebContentProcessInfo` instances. Cast accordingly.
+ (NSArray<_WKProcessInfo *> *)_webContentProcessInfo
    API_AVAILABLE(macos(14.5));

/// Requests termination of the web content process with the given PID.
///
/// Returns YES if the termination was requested, NO if the process
/// was not found or could not be terminated. The process may not
/// terminate immediately.
///
/// Tabs in the terminated process enter the `.notRunning` state and
/// can be restored by reloading.
- (BOOL)_requestWebProcessTermination:(pid_t)pid
    API_AVAILABLE(macos(12.0), ios(15.0));

/// Returns whether the web content process with the given PID is suspended.
- (BOOL)_isWebProcessSuspended:(pid_t)pid;

/// Number of active web content processes (excluding prewarmed/cached).
- (size_t)_webProcessCountIgnoringPrewarmedAndCached
    API_AVAILABLE(macos(10.14.4), ios(12.2));

/// Terminates all web content processes.
- (void)_terminateAllWebContentProcesses;

@end

NS_ASSUME_NONNULL_END
