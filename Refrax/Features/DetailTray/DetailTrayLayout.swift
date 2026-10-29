import CoreGraphics

/// Keeps the library drawer beside the control island while preserving its edge inset.
nonisolated enum DetailTrayLayout {
    static func leading(in bounds: CGRect, controlRail: CGRect, width: CGFloat) -> CGFloat {
        let margin = ControlIslandPlacement.margin
        let left = bounds.minX + margin
        let preferred = CGRect(x: left, y: bounds.minY + margin, width: width, height: max(0, bounds.height - margin * 2))
        guard preferred.intersects(controlRail) else { return left }
        let right = controlRail.maxX + ControlIslandPlacement.adjacentGap
        if right + width <= bounds.maxX - margin { return right }
        let before = controlRail.minX - ControlIslandPlacement.adjacentGap - width
        return before >= left ? before : left
    }
}
