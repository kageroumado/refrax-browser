import CoreGraphics

/// Measurements for the floating tour's scrim, spotlights, and instruction card.
nonisolated enum FloatingTourLayout {
    static let margin: CGFloat = 20
    /// Room kept below the progress bar so the card never covers it.
    static let topInset: CGFloat = 64
    static let gap: CGFloat = 16
    static let cardWidth: CGFloat = 360
    static let cardPadding: CGFloat = 18
    static let cardCornerRadius: CGFloat = 20
    static let cardSpacing: CGFloat = 10
    static let spotlightPadding: CGFloat = 8
    static let spotlightCornerRadius: CGFloat = 16
    static let ringWidth: CGFloat = 2
    static let scrimOpacity: Double = 0.45
    static let progressWidth: CGFloat = 320
    static let progressHeight: CGFloat = 6
    static let progressTop: CGFloat = 16
    static let progressPaddingH: CGFloat = 14
    static let progressPaddingV: CGFloat = 8
    static let pulseScale: CGFloat = 1.05

    /// The lit area around a target, with breathing room on every side.
    static func spotlight(around target: CGRect) -> CGRect {
        target.insetBy(dx: -spotlightPadding, dy: -spotlightPadding)
    }

    /// Where the instruction card goes: beside a tall target, below or above a wide one,
    /// and centered when the step points at nothing. The card always stays inside the window.
    static func cardOrigin(for target: CGRect?, cardSize: CGSize, in bounds: CGRect) -> CGPoint {
        let area = CGRect(
            x: bounds.minX + margin, y: bounds.minY + topInset,
            width: max(0, bounds.width - margin * 2), height: max(0, bounds.height - topInset - margin),
        )
        guard let target, !target.isEmpty else {
            return clamp(CGPoint(x: bounds.midX - cardSize.width / 2, y: bounds.midY - cardSize.height / 2), cardSize, area)
        }
        let spot = spotlight(around: target)
        let fitsBelow = spot.maxY + gap + cardSize.height <= area.maxY
        let fitsAbove = spot.minY - gap - cardSize.height >= area.minY
        let fitsRight = spot.maxX + gap + cardSize.width <= area.maxX
        let fitsLeft = spot.minX - gap - cardSize.width >= area.minX
        let isTall = spot.height > spot.width
        let beside = CGPoint(
            x: spot.midX < bounds.midX ? spot.maxX + gap : spot.minX - gap - cardSize.width,
            y: spot.midY - cardSize.height / 2,
        )
        let origin: CGPoint = if isTall, fitsRight || fitsLeft {
            beside
        } else if fitsBelow {
            CGPoint(x: spot.midX - cardSize.width / 2, y: spot.maxY + gap)
        } else if fitsAbove {
            CGPoint(x: spot.midX - cardSize.width / 2, y: spot.minY - gap - cardSize.height)
        } else {
            beside
        }
        return clamp(origin, cardSize, area)
    }

    private static func clamp(_ origin: CGPoint, _ size: CGSize, _ area: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, area.minX), max(area.minX, area.maxX - size.width)),
            y: min(max(origin.y, area.minY), max(area.minY, area.maxY - size.height)),
        )
    }
}
