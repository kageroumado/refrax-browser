import CoreGraphics

/// A floating card's frame by state. A card kept visible reads as a small window: a larger
/// radius and the window shadow. A transient card is a thumbnail: the slab radius and a lighter
/// card shadow. The radius and the shadow are the whole "kept" signal.
///
/// The header works like a title bar, and every gap in it is measured by closest approach: the
/// favicon sits as far from the leading edge as from the top and bottom, and the last control's
/// glyph sits as far from the trailing edge.
nonisolated enum FloatingCardChrome {
    static let transientCornerRadius: CGFloat = CanvasTileLayout.slabCornerRadius
    static let keptCornerRadius: CGFloat = 16

    /// The card's outer radius.
    static func cornerRadius(isKept: Bool) -> CGFloat {
        isKept ? keptCornerRadius : transientCornerRadius
    }

    /// The live preview's radius, concentric with the card around the preview inset.
    static func previewCornerRadius(isKept: Bool) -> CGFloat {
        cornerRadius(isKept: isKept) - FloatingTabPlacement.previewInset
    }

    /// A drop shadow, black at `opacity`, blurred by `radius`, and dropped by `y`.
    struct Shadow: Equatable, Sendable {
        let opacity: Double
        let radius: CGFloat
        let y: CGFloat
    }

    /// A window's shadow: soft, wide, and a little lower.
    static let windowShadow = Shadow(opacity: 0.3, radius: 24, y: 10)
    /// A thumbnail's shadow, lighter and closer to the page.
    static let cardShadow = Shadow(opacity: 0.18, radius: 14, y: 6)

    static func shadow(isKept: Bool) -> Shadow {
        isKept ? windowShadow : cardShadow
    }

    /// The header's metrics, from which every padding follows.
    enum Header {
        static let height: CGFloat = FloatingTabPlacement.headerHeight
        /// The favicon and every control glyph sit in a square box this size.
        static let glyphBox: CGFloat = 16
        /// Point size of the control symbols, drawn inside the glyph box.
        static let symbolPointSize: CGFloat = 13
        /// The clickable margin around a control's glyph box.
        static let controlPadding: CGFloat = 4

        /// The gap from a glyph box to the header's top and bottom edges, and to its sides.
        static var edgeGap: CGFloat {
            (height - glyphBox) / 2
        }

        /// A control's square target.
        static var controlSize: CGFloat {
            glyphBox + controlPadding * 2
        }

        /// Padding before the favicon.
        static var leadingPadding: CGFloat {
            edgeGap
        }

        /// Padding after the last control's target, so its glyph sits `edgeGap` from the edge.
        static var trailingPadding: CGFloat {
            edgeGap - controlPadding
        }

        /// The gap between neighboring glyph boxes: two control paddings, so identity items and
        /// controls are spaced alike.
        static var itemSpacing: CGFloat {
            controlPadding * 2
        }
    }
}
