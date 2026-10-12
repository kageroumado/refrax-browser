import CoreGraphics

/// A path of light the tour asks the light engine to draw from a control to what it opened,
/// so the eye follows: the rail's lens button to the open lens, the page icon to its card.
nonisolated struct TourBeam: Equatable, Sendable {
    /// Which control and which opened thing the beam joins.
    enum Kind: Hashable, Sendable {
        case lensButtonToLens
        case pageIconToCard
    }

    let kind: Kind
    /// Where the light leaves, in window content coordinates.
    let from: CGRect
    /// Where the light lands, in window content coordinates.
    let to: CGRect
    /// Counts the times a beam was asked for anew, so the same pair lights again on a repeat.
    let revision: Int
}
