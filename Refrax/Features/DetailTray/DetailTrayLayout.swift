import CoreGraphics

/// Keeps the library drawer beside the control island while preserving its edge inset.
nonisolated enum DetailTrayLayout {
    /// The drawer's leading x: against the window edge on the control island's side, or beside
    /// the rail when the rail sits on that edge. `onRight` is the rail's side, known from its
    /// placement even while the rail hides past the edge and has no frame.
    static func leading(in bounds: CGRect, controlRail: CGRect, onRight: Bool = false, width: CGFloat) -> CGFloat {
        let margin = ControlIslandPlacement.margin
        let gap = ControlIslandPlacement.adjacentGap
        let left = bounds.minX + margin
        let right = bounds.maxX - margin - width
        let edge = onRight ? right : left
        let preferred = CGRect(x: edge, y: bounds.minY + margin, width: width, height: max(0, bounds.height - margin * 2))
        guard preferred.intersects(controlRail) else { return edge }
        let after = controlRail.maxX + gap
        let before = controlRail.minX - gap - width
        if onRight {
            if before >= left { return before }
            return after <= right ? after : edge
        }
        if after <= right { return after }
        return before >= left ? before : edge
    }
}
