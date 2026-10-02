import AppKit

extension NSImage {
    /// A bitmap copy `width` pixels wide with the aspect ratio kept, or `self` when it is
    /// already that narrow. Rasterized up front so the larger source can be released.
    /// Nil when the image has no drawable size.
    func scaled(toWidth width: CGFloat) -> NSImage? {
        guard size.width > 0, size.height > 0 else { return nil }
        guard size.width > width else { return self }
        let pixelsWide = Int(width)
        let pixelsHigh = Int((width * size.height / size.width).rounded())
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }

        let target = NSSize(width: pixelsWide, height: pixelsHigh)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        draw(in: NSRect(origin: .zero, size: target), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: target)
        image.addRepresentation(rep)
        return image
    }
}
