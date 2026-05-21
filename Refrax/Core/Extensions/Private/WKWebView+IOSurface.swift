import AppKit
import IOSurface
import QuartzCore
import WebKit

/// Extension for extracting IOSurface from WKWebView's layer hierarchy.
///
/// ## Overview
///
/// WKWebView renders web content to IOSurface-backed CALayers. This extension
/// provides methods to extract the underlying IOSurfaceRef for zero-copy GPU
/// texture binding in Metal.
///
/// ## Layer Hierarchy
///
/// WKWebView uses a tiled layer architecture:
/// ```
/// WKWebView
/// └── WKCompositingView (layer-backed)
///     └── Multiple WKCompositingLayer tiles
///         └── contents: CAIOSurface → IOSurfaceRef
/// ```
///
/// Each tile is typically 512×512 pixels at device scale.
///
/// ## Thread Safety
///
/// All methods must be called on the main thread.
extension WKWebView {
    /// Result of IOSurface extraction containing the surface and its source layer.
    struct IOSurfaceExtractionResult {
        /// The extracted IOSurface reference.
        let surface: IOSurfaceRef

        /// The layer that contains this IOSurface.
        let sourceLayer: CALayer

        /// Width of the IOSurface in pixels.
        var width: Int { IOSurfaceGetWidth(surface) }

        /// Height of the IOSurface in pixels.
        var height: Int { IOSurfaceGetHeight(surface) }

        /// Seed value that changes when content is updated.
        var seed: UInt32 { IOSurfaceGetSeed(surface) }
    }

    /// Extracts the primary IOSurface from this WKWebView.
    ///
    /// Traverses the layer hierarchy to find the largest IOSurface-backed layer,
    /// which typically contains the main web content.
    ///
    /// - Returns: Extraction result containing the IOSurface, or `nil` if not found.
    func extractIOSurface() -> IOSurfaceExtractionResult? {
        guard let rootLayer = layer else { return nil }

        // Find all IOSurface-backed layers
        var surfaces: [IOSurfaceExtractionResult] = []
        collectIOSurfaces(from: rootLayer, into: &surfaces)

        // Return the largest surface (most likely the main content)
        return surfaces.max { $0.width * $0.height < $1.width * $1.height }
    }

    /// Extracts all IOSurfaces from this WKWebView.
    ///
    /// WebKit uses tiled rendering, so there may be multiple IOSurface-backed
    /// layers representing different regions of the content.
    ///
    /// - Returns: Array of all found IOSurface extraction results.
    func extractAllIOSurfaces() -> [IOSurfaceExtractionResult] {
        guard let rootLayer = layer else { return [] }

        var surfaces: [IOSurfaceExtractionResult] = []
        collectIOSurfaces(from: rootLayer, into: &surfaces)
        return surfaces
    }

    /// Extracts the IOSurface that covers the left edge of the viewport.
    ///
    /// For edge color sampling, we need the surface that contains the leftmost
    /// pixels. WebKit content tiles have negative x origin (scroll offset),
    /// while background/overlay layers sit at x=0.
    ///
    /// - Returns: The IOSurface covering the left edge, or `nil` if not found.
    func extractLeftEdgeIOSurface() -> IOSurfaceExtractionResult? {
        guard let rootLayer = layer else { return nil }

        var surfaces: [IOSurfaceExtractionResult] = []
        collectIOSurfaces(from: rootLayer, into: &surfaces)

        // Prefer content tiles (negative x) over background/overlay layers (x=0)
        // Content tiles are positioned with negative x due to scroll offset
        let contentTiles = surfaces.filter { result in
            result.sourceLayer.frame.origin.x < 0
        }

        if let best = contentTiles.max(by: { $0.height < $1.height }) {
            return best
        }

        // Fall back to any surface near the left edge
        let leftEdgeSurfaces = surfaces.filter { result in
            result.sourceLayer.frame.origin.x < 10
        }
        return leftEdgeSurfaces.max { $0.height < $1.height }
    }

    // MARK: - Private Helpers

    private func collectIOSurfaces(from layer: CALayer, into results: inout [IOSurfaceExtractionResult]) {
        // Check this layer's contents
        if let surface = extractIOSurfaceFromContents(layer.contents) {
            results.append(IOSurfaceExtractionResult(surface: surface, sourceLayer: layer))
        }

        // Recurse into sublayers
        if let sublayers = layer.sublayers {
            for sublayer in sublayers {
                collectIOSurfaces(from: sublayer, into: &results)
            }
        }
    }

    private func extractIOSurfaceFromContents(_ contents: Any?) -> IOSurfaceRef? {
        guard let contents else { return nil }

        let cfType = contents as CFTypeRef
        let typeID = CFGetTypeID(cfType)

        // Check if it's a direct IOSurface (toll-free bridged)
        if typeID == IOSurfaceGetTypeID() {
            return unsafeDowncast(cfType, to: IOSurfaceRef.self)
        }

        // Check if it's CAIOSurface (wrapper class used by WebKit)
        if typeID == CAIOSurfaceGetTypeID() {
            let caIOSurface = unsafeBitCast(cfType, to: CAIOSurfaceRef.self)
            return CAIOSurfaceGetIOSurface(caIOSurface)?.takeUnretainedValue()
        }

        return nil
    }
}

// MARK: - IOSurface Utilities

extension IOSurfaceRef {
    /// Pixel format as a human-readable string.
    var pixelFormatString: String {
        let format = IOSurfaceGetPixelFormat(self)
        switch format {
        case 0x4247_5241: return "BGRA"
        case 0x4247_5258: return "BGRX"
        case 0x5247_4241: return "RGBA"
        default: return String(format: "0x%08X", format)
        }
    }

    /// Debug description of this IOSurface.
    var debugDescription: String {
        let width = IOSurfaceGetWidth(self)
        let height = IOSurfaceGetHeight(self)
        let seed = IOSurfaceGetSeed(self)
        let bytesPerRow = IOSurfaceGetBytesPerRow(self)
        return "IOSurface(\(width)×\(height), \(pixelFormatString), seed:\(seed), bpr:\(bytesPerRow))"
    }
}
