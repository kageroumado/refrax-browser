import CoreGraphics

/// Shared slab styling and centered page geometry.
nonisolated enum CanvasTileLayout {
    static let slabCornerRadius: CGFloat = 12
    static let glassInset: CGFloat = 6
    static let headerHeight: CGFloat = 20

    static func centeredFrame(size: CGSize, on frame: CGRect) -> CGRect {
        CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)
    }
}
