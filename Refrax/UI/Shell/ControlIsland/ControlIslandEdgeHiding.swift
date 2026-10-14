import CoreGraphics

/// The rail hides past a window edge it is snapped to, and returns when the pointer reaches it.
nonisolated extension ControlIslandPlacement {
    /// The window side a snapped rail hides past.
    enum Edge: Equatable {
        case left
        case right

        var name: String {
            switch self {
            case .left: "left"
            case .right: "right"
            }
        }
    }

    static let edgeHidingTitle = "Hide at the Edge"
    static let edgeHidingHelp = "Against the window's left or right edge, the controls slide away; move the pointer to the edge to bring them back"
    /// The strip along the window edge that brings a hidden rail back.
    static let revealStripWidth: CGFloat = 6
    /// How far past the rail's ends the strip reaches.
    static let revealStripOverhang: CGFloat = 40
    /// How far past the window edge a hidden rail sits, so its glass shadow leaves with it.
    static let hiddenShadowClearance: CGFloat = 32

    /// The edge this placement is snapped to, if it is the left or right one.
    var horizontalEdge: Edge? {
        switch x {
        case 0: .left
        case 1: .right
        default: nil
        }
    }

    /// The strip along `edge` that brings a rail at `rail` back: `revealStripWidth` wide, the
    /// rail's height plus `revealStripOverhang` at each end, inside `bounds`.
    static func revealStrip(for rail: CGRect, at edge: Edge, in bounds: CGRect) -> CGRect {
        let strip = CGRect(
            x: edge == .left ? bounds.minX : bounds.maxX - revealStripWidth,
            y: rail.minY - revealStripOverhang,
            width: revealStripWidth,
            height: rail.height + revealStripOverhang * 2,
        )
        let visible = strip.intersection(bounds)
        return visible.isNull ? .zero : visible
    }

    /// Where a rail at `rail` waits while hidden: wholly past `edge`, shadow included.
    static func hiddenFrame(for rail: CGRect, at edge: Edge, in bounds: CGRect) -> CGRect {
        var frame = rail
        frame.origin.x = edge == .left
            ? bounds.minX - rail.width - hiddenShadowClearance
            : bounds.maxX + hiddenShadowClearance
        return frame
    }
}
