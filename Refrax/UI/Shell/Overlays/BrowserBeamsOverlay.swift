import CoreGraphics
import Foundation
import SwiftUI

/// Decides when the window's beams play, from what the lens and the page card report.
///
/// Two cues, each a ``Request`` the light engine draws once: a ``LightStyle/guide`` from
/// the rail's lens button to the centered lens, once per opening the button asked for, as
/// soon as the lens has a frame; and a ``LightStyle/trail`` from the page icon to its card,
/// once per unfold that the icon's hover or click asked for. While the tour runs, its
/// overlay draws these pairs above its scrim, so the cues stay quiet.
nonisolated struct BrowserBeamCues: Equatable, Sendable {
    /// One beam for the light engine, from `from` to `to` in window coordinates.
    struct Request: Equatable, Sendable {
        let style: LightStyle
        let from: CGRect
        let to: CGRect
        /// Counts requests, so a repeat of the same pair plays again.
        let revision: Int

        /// The beam's route: a guide refracts into the lens like a displaced ray; a trail is a
        /// straight run from the icon's center to the card's near edge.
        func points(in area: CGRect) -> [CGPoint] {
            switch style {
            case .guide, .displaced:
                let ray = FloatingRayPath(from: from, to: to, in: area)
                return [ray.start, ray.bend, ray.end]
            case .trail:
                let start = CGPoint(x: from.midX, y: from.midY)
                let edge = abs(to.minX - start.x) <= abs(to.maxX - start.x) ? to.minX : to.maxX
                return [start, CGPoint(x: edge, y: min(max(start.y, to.minY), to.maxY))]
            }
        }
    }

    /// What the lens reports.
    struct LensReading: Equatable, Sendable {
        /// The lens is up, centered in the window.
        var isOpen: Bool
        /// The control that opened it, when a control did.
        var source: CGRect?
        /// The lens capsule, once its geometry has arrived.
        var frame: CGRect
    }

    /// What the page card reports.
    struct CardReading: Equatable, Sendable {
        /// The card's frame while it is unfolded; empty while it is away.
        var frame: CGRect
        /// The page icon's hover or click asked for the card.
        var isDeliberate: Bool
        /// The page icon's row on the rail.
        var row: CGRect
    }

    private(set) var lensRay: Request?
    private(set) var trail: Request?
    private var revision = 0
    /// The current opening of the lens has had its ray, or needs none.
    private var lensIsLit = false
    /// The current unfold of the card has had its trail, or needs none.
    private var cardIsLit = false

    /// Reads the lens and asks for its ray once per opening a control started.
    mutating func reviewLens(_ lens: LensReading, tourIsActive: Bool) {
        guard lens.isOpen else {
            lensIsLit = false
            lensRay = nil
            return
        }
        guard !lensIsLit, !lens.frame.isEmpty else { return }
        lensIsLit = true
        guard !tourIsActive, let source = lens.source, !source.isEmpty else { return }
        lensRay = next(.guide, from: source, to: lens.frame)
    }

    /// Reads the page card and asks for its trail once per unfold the icon asked for.
    mutating func reviewCard(_ card: CardReading, tourIsActive: Bool) {
        guard !card.frame.isEmpty else {
            cardIsLit = false
            trail = nil
            return
        }
        guard !cardIsLit else { return }
        cardIsLit = true
        guard !tourIsActive, card.isDeliberate, !card.row.isEmpty else { return }
        trail = next(.trail, from: card.row, to: card.frame)
    }

    /// Clears a request the engine has finished drawing.
    mutating func finish(_ request: Request) {
        if lensRay == request {
            lensRay = nil
        }
        if trail == request {
            trail = nil
        }
    }

    private mutating func next(_ style: LightStyle, from: CGRect, to: CGRect) -> Request {
        revision += 1
        return Request(style: style, from: from, to: to, revision: revision)
    }
}

/// The window's beams, drawn over the page and under the lens: the rail's lens button to
/// the lens it opened, and the page icon to its card. The layer takes no clicks.
struct BrowserBeamsOverlay: View {
    @Environment(WindowState.self) private var windowState
    @Environment(FloatingTourManager.self) private var tour
    @State private var cues = BrowserBeamCues()

    var body: some View {
        let island = windowState.controlIsland
        let lens = BrowserBeamCues.LensReading(
            isOpen: windowState.showsCommandLens && !windowState.showsAnchoredLens,
            source: windowState.commandLensEntrance?.source,
            frame: windowState.commandLensFrame,
        )
        let card = BrowserBeamCues.CardReading(
            frame: island.pageCardFrame,
            isDeliberate: island.showsAddress || island.tabInfo.isLatched,
            row: island.itemFrames[.page] ?? .zero,
        )
        let space = windowState.activeSpace?.color
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size)
            ZStack(alignment: .topLeading) {
                ForEach([cues.lensRay, cues.trail].compactMap(\.self), id: \.revision) { request in
                    LightTravel(
                        paths: [request.style.path(request.points(in: bounds), color: request.style.color(space: space))],
                        timing: request.style.timing,
                    ) {
                        cues.finish(request)
                    }
                }
            }
            .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: lens, initial: true) { _, lens in cues.reviewLens(lens, tourIsActive: tour.isActive) }
        .onChange(of: card, initial: true) { _, card in cues.reviewCard(card, tourIsActive: tour.isActive) }
    }
}
