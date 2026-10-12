import CoreGraphics

/// Converts between a tab's saved preview rectangle and its visible slab, keeping its center fixed.
nonisolated enum CanvasTileLayout {
    /// The glass header and rim surround this content rectangle in both presentations.
    static let compactContentSize = CGSize(width: 208, height: 1)
    static let slabCornerRadius: CGFloat = 12
    static let glassInset: CGFloat = 6
    static let headerHeight: CGFloat = 20

    static func displayedFrame(for preview: CGRect, isCompact: Bool) -> CGRect {
        isCompact ? centeredFrame(size: compactContentSize, on: preview) : preview
    }

    static func previewFrame(for displayed: CGRect, previewSize: CGSize) -> CGRect {
        centeredFrame(size: previewSize, on: displayed)
    }

    static func centeredFrame(size: CGSize, on frame: CGRect) -> CGRect {
        CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)
    }
}
