/**
 * CoreGraphicsSPI.h
 * Refrax Browser
 *
 * Private CoreGraphics API for GPU-accelerated window capture.
 *
 * `CGSHWCaptureWindowList` performs hardware-accelerated window capture
 * by reading directly from WindowServer's GPU textures. This is the same
 * API Safari/WebKit uses for tab snapshots.
 *
 * ## Usage
 * ```swift
 * var windowID = CGSWindowID(window.windowNumber)
 * let options: CGSWindowCaptureOptions = kCGSCaptureIgnoreGlobalClipShape
 * if let snapshots = CGSHWCaptureWindowList(CGSMainConnectionID(), &windowID, 1, options) as? [CGImage],
 *    let image = snapshots.first {
 *     // GPU-backed CGImage ready for CALayer.contents
 * }
 * ```
 *
 * ## Source Reference
 * Based on WebKit's PAL/pal/spi/cg/CoreGraphicsSPI.h
 *
 * Last verified: macOS 26.1
 */

#ifndef CoreGraphicsSPI_h
#define CoreGraphicsSPI_h

#include <CoreGraphics/CoreGraphics.h>

typedef uint32_t CGSConnectionID;
typedef uint32_t CGSWindowID;
typedef CGSWindowID *CGSWindowIDList;
typedef uint32_t CGSWindowCaptureOptions;

enum {
    kCGSWindowCaptureNominalResolution = 0x0200,
    kCGSCaptureIgnoreGlobalClipShape = 0x0800,
};

/// Returns the connection ID for the main display connection.
CF_EXPORT CGSConnectionID CGSMainConnectionID(void);

/// Performs GPU hardware capture of the specified windows.
///
/// Returns a CFArray of CGImageRef, one per captured window.
/// The images are GPU-backed and suitable for direct use as CALayer contents.
CF_EXPORT CFArrayRef _Nullable CGSHWCaptureWindowList(
    CGSConnectionID cid,
    CGSWindowIDList _Nullable windowList,
    uint32_t windowCount,
    CGSWindowCaptureOptions options
) CF_RETURNS_RETAINED;

#endif /* CoreGraphicsSPI_h */
