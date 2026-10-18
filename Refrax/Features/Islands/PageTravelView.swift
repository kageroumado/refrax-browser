import AppKit
import SwiftUI

/// The window's page, and the way one page replaces another: a neighbor slides in from the
/// direction of travel while the outgoing page's snapshot slides out; a crossing shrinks the
/// outgoing page away and grows the next one in; a jump fades.
struct PageTravelView: View {
    @Environment(IslandController.self) private var islands
    @Environment(WindowState.self) private var windowState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The move being shown, with its progress from 0 (just begun) to 1 (arrived).
    @State private var shown: PageTravel?
    @State private var progress: CGFloat = 1
    @State private var size: CGSize = .zero

    private enum Layout {
        static let slideDuration: TimeInterval = 0.3
        static let crossDuration: TimeInterval = 0.38
        static let jumpDuration: TimeInterval = 0.18
        static let crossScale: CGFloat = 0.92
        static let cornerRadius: CGFloat = 12
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(nsColor: .windowBackgroundColor)
            if let tab = windowState.activeTab {
                UnifiedContentView(tab: tab)
                    .id(tab.id)
                    .modifier(TravelMotion(travel: shown, progress: progress, size: size, incoming: true))
            }
            if let shown, let image = shown.outgoing {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
                    .clipped()
                    .modifier(TravelMotion(travel: shown, progress: progress, size: size, incoming: false))
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            size = frame.size
            islands.updateViewport(frame)
        }
        .onChange(of: islands.travel?.id) { _, id in
            guard let travel = islands.travel, travel.id == id else { return }
            begin(travel)
        }
    }

    private func begin(_ travel: PageTravel) {
        shown = travel
        progress = 0
        let duration: TimeInterval = switch travel.style {
        case .slide: Layout.slideDuration
        case .cross: Layout.crossDuration
        case .jump: Layout.jumpDuration
        }
        withAnimation(reduceMotion ? .easeOut(duration: Layout.jumpDuration) : .easeInOut(duration: duration)) {
            progress = 1
        } completion: {
            if shown?.id == travel.id {
                shown = nil
            }
            islands.finishTravel(travel.id)
        }
    }
}

/// Places the incoming page and the outgoing snapshot along a move's path.
private struct TravelMotion: ViewModifier {
    let travel: PageTravel?
    let progress: CGFloat
    let size: CGSize
    let incoming: Bool

    private enum Layout {
        static let crossScale: CGFloat = 0.92
    }

    func body(content: Content) -> some View {
        guard let travel else { return AnyView(content) }
        switch travel.style {
        case let .slide(direction):
            let vector = Self.vector(direction, size: size)
            let offset = incoming
                ? CGSize(width: vector.width * (1 - progress), height: vector.height * (1 - progress))
                : CGSize(width: -vector.width * progress, height: -vector.height * progress)
            return AnyView(content.offset(offset))
        case .cross:
            let scale = incoming ? Layout.crossScale + (1 - Layout.crossScale) * progress : 1 - (1 - Layout.crossScale) * progress
            let opacity = incoming ? progress : 1 - progress
            return AnyView(content.scaleEffect(scale).opacity(opacity))
        case .jump:
            return AnyView(content.opacity(incoming ? progress : 1 - progress))
        }
    }

    /// Where an incoming page starts for a move in `direction`: off the edge it comes from.
    private static func vector(_ direction: TableDirection, size: CGSize) -> CGSize {
        switch direction {
        case .left: CGSize(width: -size.width, height: 0)
        case .right: CGSize(width: size.width, height: 0)
        case .up: CGSize(width: 0, height: -size.height)
        case .down: CGSize(width: 0, height: size.height)
        }
    }
}
