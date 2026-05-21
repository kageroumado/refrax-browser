import AppKit
import IOSurface
import QuartzCore
import WebKit

/// Debug utility to inspect WKWebView's layer hierarchy.
///
/// This helps identify which layers contain IOSurface-backed content
/// that can be used for GPU-accelerated edge color sampling.
enum LayerHierarchyInspector {
    /// Dumps the complete layer hierarchy of a WKWebView to the console.
    ///
    /// - Parameter webView: The WKWebView to inspect.
    static func dumpLayerHierarchy(of webView: WKWebView) {
        guard let rootLayer = webView.layer else {
            print("⚠️ WKWebView has no layer")
            return
        }

        print("\n" + String(repeating: "=", count: 60))
        print("WKWebView Layer Hierarchy")
        print(String(repeating: "=", count: 60))
        dumpLayer(rootLayer, indent: 0)
        print(String(repeating: "=", count: 60) + "\n")
    }

    /// Recursively dumps a layer and its sublayers.
    private static func dumpLayer(_ layer: CALayer, indent: Int) {
        let prefix = String(repeating: "  ", count: indent)
        let className = String(describing: type(of: layer))

        // Check for IOSurface content
        var contentInfo = "nil"
        if let contents = layer.contents {
            let contentsType = String(describing: type(of: contents))
            let cfType = contents as CFTypeRef
            let typeID = CFGetTypeID(cfType)
            let typeName = CFCopyTypeIDDescription(typeID) as String? ?? "unknown"

            if typeID == IOSurfaceGetTypeID() {
                contentInfo = "✅ IOSurface (direct)"
            } else if typeName.contains("IOSurface") {
                contentInfo = "✅ \(typeName)"
            } else {
                contentInfo = "\(contentsType) [CFTypeID:\(typeID) = \(typeName)]"
            }
        }

        // Check for context ID (CALayerHost)
        var contextInfo = ""
        if className.contains("LayerHost") || className.contains("RemoteLayer") {
            if let contextID = layer.value(forKey: "contextId") as? UInt32, contextID != 0 {
                contextInfo = " [contextId: \(contextID)]"
            }
        }

        // Get frame info
        let frame = layer.frame
        let frameStr = String(format: "(%.0f,%.0f %.0fx%.0f)", frame.origin.x, frame.origin.y, frame.size.width, frame.size.height)

        print("\(prefix)[\(className)] \(frameStr)")
        print("\(prefix)  contents: \(contentInfo)\(contextInfo)")

        // Check for delegate
        if let delegate = layer.delegate {
            let delegateType = String(describing: type(of: delegate))
            print("\(prefix)  delegate: \(delegateType)")
        }

        // Recurse into sublayers
        if let sublayers = layer.sublayers {
            for sublayer in sublayers {
                dumpLayer(sublayer, indent: indent + 1)
            }
        }
    }

    /// Finds layers that likely contain IOSurface content.
    ///
    /// - Parameter webView: The WKWebView to search.
    /// - Returns: Array of layers whose contents might be IOSurface-backed.
    static func findContentLayers(in webView: WKWebView) -> [CALayer] {
        guard let rootLayer = webView.layer else { return [] }
        return findContentLayersRecursive(rootLayer)
    }

    private static func findContentLayersRecursive(_ layer: CALayer) -> [CALayer] {
        var results: [CALayer] = []

        // Check if this layer has IOSurface contents
        if let contents = layer.contents {
            let contentsType = String(describing: type(of: contents))
            if contentsType.contains("IOSurface") || contentsType.contains("CAIOSurface") {
                results.append(layer)
            }
        }

        // Check if this is a CALayerHost (remote content)
        let className = String(describing: type(of: layer))
        if className.contains("LayerHost") {
            results.append(layer)
        }

        // Recurse
        if let sublayers = layer.sublayers {
            for sublayer in sublayers {
                results.append(contentsOf: findContentLayersRecursive(sublayer))
            }
        }

        return results
    }

    /// Inspects IOSurface details if the layer's contents is an IOSurface.
    ///
    /// - Parameter layer: The layer to inspect.
    /// - Returns: Dictionary of IOSurface properties, or nil if not IOSurface-backed.
    static func inspectIOSurface(of layer: CALayer) -> [String: Any]? {
        guard let contents = layer.contents else { return nil }

        // Try to get IOSurfaceRef via private API
        // CAIOSurface has a private `surface` method that returns IOSurfaceRef
        let contentsObject = contents as AnyObject

        // Check class name
        let className = String(describing: type(of: contents))
        guard className.contains("IOSurface") else { return nil }

        var info: [String: Any] = ["class": className]

        // Try to get the underlying IOSurfaceRef
        if contentsObject.responds(to: Selector(("surface"))) {
            if let surfacePtr = contentsObject.perform(Selector(("surface")))?.toOpaque() {
                let surface = Unmanaged<IOSurfaceRef>.fromOpaque(surfacePtr).takeUnretainedValue()
                info["width"] = IOSurfaceGetWidth(surface)
                info["height"] = IOSurfaceGetHeight(surface)
                info["seed"] = IOSurfaceGetSeed(surface)
                info["pixelFormat"] = IOSurfaceGetPixelFormat(surface)
                info["bytesPerRow"] = IOSurfaceGetBytesPerRow(surface)
                info["ioSurfaceRef"] = surfacePtr
            }
        }

        return info
    }

    /// Attempts to extract IOSurfaceRef from a WKWebView for Metal texture binding.
    ///
    /// This traverses the layer hierarchy to find IOSurface-backed content layers
    /// and extracts the underlying IOSurfaceRef.
    ///
    /// - Parameter webView: The WKWebView to extract IOSurface from.
    /// - Returns: Tuple of (IOSurfaceRef, CALayer) if found, nil otherwise.
    static func extractIOSurface(from webView: WKWebView) -> (IOSurfaceRef, CALayer)? {
        guard let rootLayer = webView.layer else { return nil }

        // Traverse layer tree looking for IOSurface contents
        return findIOSurfaceRecursive(rootLayer)
    }

    private static func findIOSurfaceRecursive(_ layer: CALayer) -> (IOSurfaceRef, CALayer)? {
        // Check this layer's contents
        if let surface = extractIOSurfaceFromContents(layer.contents) {
            return (surface, layer)
        }

        // Recurse into sublayers
        if let sublayers = layer.sublayers {
            for sublayer in sublayers {
                if let result = findIOSurfaceRecursive(sublayer) {
                    return result
                }
            }
        }

        return nil
    }

    /// Extracts IOSurfaceRef from layer contents (handles CAIOSurface wrapper)
    private static func extractIOSurfaceFromContents(_ contents: Any?) -> IOSurfaceRef? {
        guard let contents else { return nil }

        let cfType = contents as CFTypeRef
        let typeID = CFGetTypeID(cfType)

        // Check if it's a direct IOSurface (toll-free bridged)
        if typeID == IOSurfaceGetTypeID() {
            return unsafeDowncast(cfType, to: IOSurfaceRef.self)
        }

        // Check if it's CAIOSurface (wrapper class)
        // Use CAIOSurfaceGetTypeID() to verify, then extract via CAIOSurfaceGetIOSurface()
        if typeID == CAIOSurfaceGetTypeID() {
            let caIOSurface = unsafeBitCast(cfType, to: CAIOSurfaceRef.self)
            // CAIOSurfaceGetIOSurface returns unretained IOSurfaceRef
            if let surface = CAIOSurfaceGetIOSurface(caIOSurface) {
                return surface.takeUnretainedValue()
            }
        }

        return nil
    }

    /// Finds ALL IOSurface-backed layers in the hierarchy.
    static func findAllIOSurfaceLayers(in webView: WKWebView) -> [(IOSurfaceRef, CALayer)] {
        guard let rootLayer = webView.layer else { return [] }
        var results: [(IOSurfaceRef, CALayer)] = []
        collectIOSurfacesRecursive(rootLayer, into: &results)
        return results
    }

    private static func collectIOSurfacesRecursive(_ layer: CALayer, into results: inout [(IOSurfaceRef, CALayer)]) {
        if let surface = extractIOSurfaceFromContents(layer.contents) {
            results.append((surface, layer))
        }

        if let sublayers = layer.sublayers {
            for sublayer in sublayers {
                collectIOSurfacesRecursive(sublayer, into: &results)
            }
        }
    }

    /// Debug function to be called from lldb or during development.
    ///
    /// Usage from lldb:
    /// ```
    /// expr LayerHierarchyInspector.debugInspectActiveWebView()
    /// ```
    
    static func debugInspectActiveWebView() {
        // Get the key window
        guard let window = NSApp.keyWindow,
              let windowController = window.windowController as? RefraxWindowController,
              let webPage = windowController.windowState.activeWebPage else {
            print("⚠️ No active WebPage found")
            return
        }

        let webView = webPage.backingWebView
        print("\n🔍 Inspecting WKWebView layer hierarchy...")
        dumpLayerHierarchy(of: webView)

        print("\n🔍 Looking for IOSurface layers...")
        let contentLayers = findContentLayers(in: webView)
        print("Found \(contentLayers.count) potential content layers")

        for (index, layer) in contentLayers.enumerated() {
            print("\n--- Layer \(index + 1) ---")
            print("Class: \(type(of: layer))")
            print("Frame: \(layer.frame)")
            if let info = inspectIOSurface(of: layer) {
                print("IOSurface info: \(info)")
            }
        }

        // Find ALL IOSurfaces
        print("\n🔍 Finding all IOSurface-backed layers...")
        let allSurfaces = findAllIOSurfaceLayers(in: webView)
        print("Found \(allSurfaces.count) IOSurface-backed layers\n")

        for (index, (surface, layer)) in allSurfaces.enumerated() {
            let width = IOSurfaceGetWidth(surface)
            let height = IOSurfaceGetHeight(surface)
            let seed = IOSurfaceGetSeed(surface)
            let pixelFormat = IOSurfaceGetPixelFormat(surface)
            let bytesPerRow = IOSurfaceGetBytesPerRow(surface)

            // Decode pixel format
            let formatStr = switch pixelFormat {
            case 0x4247_5241: "BGRA"
            case 0x4247_5258: "BGRX"
            default: String(format: "0x%08X", pixelFormat)
            }

            print("IOSurface #\(index + 1):")
            print("  Layer: \(type(of: layer)) at \(layer.frame)")
            print("  Size: \(width)x\(height)")
            print("  Format: \(formatStr), bytesPerRow: \(bytesPerRow)")
            print("  Seed: \(seed)")
            print("")
        }

        // Summary for implementation
        if !allSurfaces.isEmpty {
            print("✅ IOSurface extraction confirmed working!")
            print("   These surfaces can be bound to Metal textures via:")
            print("   device.makeTexture(descriptor:iosurface:plane:)")
        }
    }
}
