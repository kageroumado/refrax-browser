/**
 * CAIOSurfacePrivate.h
 * Refrax Browser
 *
 * Private QuartzCore API for extracting IOSurfaceRef from CAIOSurface.
 *
 * CAIOSurface is an opaque wrapper around IOSurfaceRef used by Core Animation
 * for layer contents. This header declares the private function to extract
 * the underlying IOSurfaceRef.
 *
 * ## Usage
 * ```swift
 * import IOSurface
 *
 * if let contents = layer.contents {
 *     let cfType = contents as CFTypeRef
 *     if CFGetTypeID(cfType) == CAIOSurfaceGetTypeID() {
 *         let caIOSurface = unsafeBitCast(cfType, to: CAIOSurfaceRef.self)
 *         let ioSurface = CAIOSurfaceGetIOSurface(caIOSurface)
 *         // Now use ioSurface with Metal
 *     }
 * }
 * ```
 *
 * ## Source Reference
 * Symbols discovered via: xcrun dyld_info -exports QuartzCore
 *
 * Last verified: macOS 26.1
 */

#ifndef CAIOSurfacePrivate_h
#define CAIOSurfacePrivate_h

#include <CoreFoundation/CoreFoundation.h>
#include <IOSurface/IOSurface.h>

CF_ASSUME_NONNULL_BEGIN

/// Opaque type representing a CAIOSurface wrapper around IOSurfaceRef.
typedef struct _CAIOSurface *CAIOSurfaceRef;

/// Returns the CFTypeID for CAIOSurface objects.
CF_EXPORT CFTypeID CAIOSurfaceGetTypeID(void);

/// Creates a CAIOSurface wrapper around an IOSurfaceRef.
/// The returned CAIOSurface retains the IOSurface.
CF_EXPORT CAIOSurfaceRef _Nullable CAIOSurfaceCreate(IOSurfaceRef surface);

/// Extracts the underlying IOSurfaceRef from a CAIOSurface.
/// The returned IOSurfaceRef is not retained - do not release it.
CF_EXPORT IOSurfaceRef _Nullable CAIOSurfaceGetIOSurface(CAIOSurfaceRef surface);

/// Reloads color attributes on the CAIOSurface (used for HDR content).
CF_EXPORT void CAIOSurfaceReloadColorAttributes(CAIOSurfaceRef surface);

/// Retains the front texture associated with the CAIOSurface.
CF_EXPORT void CAIOSurfaceRetainFrontTexture(CAIOSurfaceRef surface);

CF_ASSUME_NONNULL_END

#endif /* CAIOSurfacePrivate_h */
