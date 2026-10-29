import CoreGraphics

/// Places a compact tab rail within the control island's edge insets and clear of other chrome.
nonisolated enum IconRailLayout {
    static let clearance = ControlIslandPlacement.adjacentGap

    static func frame(placement: ControlIslandPlacement, height: CGFloat, in bounds: CGRect, obstacles: [CGRect]) -> CGRect {
        let preferred = placement.railFrame(in: bounds, height: height)
        let area = bounds.insetBy(dx: ControlIslandPlacement.margin, dy: ControlIslandPlacement.margin)
        let occupied = obstacles.filter { !$0.isEmpty }.map { $0.insetBy(dx: -clearance, dy: -clearance) }
        guard occupied.contains(where: { $0.intersects(preferred) }) else { return preferred }
        let xs = [preferred.minX, area.minX, area.maxX - preferred.width]
            + occupied.flatMap { [$0.minX - preferred.width, $0.maxX] }
        let ys = [preferred.minY, area.minY, area.maxY - preferred.height]
            + occupied.flatMap { [$0.minY - preferred.height, $0.maxY] }
        var candidates: [CGRect] = []
        for x in xs {
            for y in ys {
                let origin = CGPoint(
                    x: min(max(area.minX, x), max(area.minX, area.maxX - preferred.width)),
                    y: min(max(area.minY, y), max(area.minY, area.maxY - preferred.height)),
                )
                let candidate = CGRect(origin: origin, size: preferred.size)
                if !occupied.contains(where: { $0.intersects(candidate) }) {
                    candidates.append(candidate)
                }
            }
        }
        return candidates.min {
            hypot($0.minX - preferred.minX, $0.minY - preferred.minY)
                < hypot($1.minX - preferred.minX, $1.minY - preferred.minY)
        } ?? preferred
    }
}
