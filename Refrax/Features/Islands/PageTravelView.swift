import AppKit
import SwiftUI

/// The window's page as a slab, and the way one page replaces another.
///
/// At rest the page fills the window. While the reveal key is held the page sits zoomed out a
/// little, a slab with a shadow and a glass rim over the window's tinted background, and the
/// margins name the tab in each direction. A move never moves a page: the outgoing page's
/// snapshot and the incoming tab's stored snapshot slide as slabs, with the background
/// showing in the gap between them, and the live page mounts only once its slab is in place,
/// under its snapshot until it has painted. A crossing to another island shrinks the outgoing
/// slab away and grows the next one in.
struct PageTravelView: View {
    @Environment(IslandController.self) private var islands
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(WindowState.self) private var windowState
    @Environment(WebPagePool.self) private var pagePool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The move being shown and its progress from 0 (just begun) to 1 (arrived).
    @State private var shown: PageTravel?
    @State private var progress: CGFloat = 1
    /// The tab that arrived, whose live page is still painting under its snapshot.
    @State private var arrivingTabID: UUID?
    @State private var size: CGSize = .zero

    private enum Layout {
        /// The page's share of the window while the reveal key is held.
        static let inspectionScale: CGFloat = 0.84
        static let slideDuration: TimeInterval = 0.32
        static let crossDuration: TimeInterval = 0.4
        static let jumpDuration: TimeInterval = 0.2
        static let crossScale: CGFloat = 0.9
        /// The background showing between two sliding slabs.
        static let gap: CGFloat = 28
        static let cornerRadius: CGFloat = 16
        static let shadowRadius: CGFloat = 22
        static let shadowOpacity: Double = 0.22
        static let rimOpacity: Double = 0.45
        static let labelInset: CGFloat = 14
        static let firstPaintFade: TimeInterval = 0.18
    }

    private var isInspecting: Bool {
        canvas.isMomentaryNavigation
    }

    private var isTraveling: Bool {
        shown != nil
    }

    /// The page's scale: zoomed out while inspecting or traveling, full at rest.
    private var scale: CGFloat {
        isInspecting || isTraveling ? Layout.inspectionScale : 1
    }

    private var slabSize: CGSize {
        CGSize(width: size.width * scale, height: size.height * scale)
    }

    var body: some View {
        ZStack {
            background
            if let tab = windowState.activeTab {
                livePage(tab)
            }
            if let shown {
                travelingSlabs(shown)
            }
            if isInspecting, !isTraveling {
                directionLabels
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: isInspecting)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            size = frame.size
            islands.updateViewport(frame)
        }
        .onChange(of: islands.travel?.id) { _, id in
            guard let travel = islands.travel, travel.id == id else { return }
            begin(travel)
        }
    }

    // MARK: - Layers

    private var background: some View {
        Color(nsColor: .windowBackgroundColor)
            .overlay(windowState.controlIslandTint)
            .ignoresSafeArea()
    }

    /// The live page, slab-shaped while it does not fill the window, hidden while a move's
    /// slabs are on screen, and under its snapshot until it has painted after arriving.
    @ViewBuilder
    private func livePage(_ tab: Tab) -> some View {
        let arriving = arrivingTabID == tab.id
        UnifiedContentView(tab: tab)
            .id(tab.id)
            .frame(width: size.width, height: size.height)
            .overlay {
                if arriving {
                    snapshotFace(for: tab)
                        .transition(.opacity)
                }
            }
            .modifier(SlabChrome(isSlab: scale < 1, scale: scale))
            .opacity(isTraveling ? 0 : 1)
            .allowsHitTesting(!isTraveling && !arriving)
            .task(id: arriving ? tab.id : nil) {
                guard arriving else { return }
                await Task.yield()
                if let page = pagePool.existingPage(for: tab.activePage) {
                    await page.waitForPresentationUpdate()
                }
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: Layout.firstPaintFade)) {
                    arrivingTabID = nil
                }
            }
    }

    /// The two slabs of a move: images only, nothing live.
    @ViewBuilder
    private func travelingSlabs(_ travel: PageTravel) -> some View {
        let incoming = windowState.activeTab
        ZStack {
            slab(image: travel.outgoing, tab: nil)
                .modifier(TravelMotion(style: travel.style, progress: progress, step: slabSize, gap: Layout.gap, incoming: false))
            slab(image: incoming.flatMap { islands.snapshot(for: $0.id) }, tab: incoming)
                .modifier(TravelMotion(style: travel.style, progress: progress, step: slabSize, gap: Layout.gap, incoming: true))
        }
        .allowsHitTesting(false)
    }

    /// A slab of a page's image at the slab's size, or its placeholder.
    private func slab(image: NSImage?, tab: Tab?) -> some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let tab {
                PagePlaceholder(tab: tab)
            } else {
                Color(nsColor: .windowBackgroundColor)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipped()
        .modifier(SlabChrome(isSlab: true, scale: Layout.inspectionScale))
    }

    @ViewBuilder
    private func snapshotFace(for tab: Tab) -> some View {
        if let image = islands.snapshot(for: tab.id) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .clipped()
        } else {
            PagePlaceholder(tab: tab)
        }
    }

    /// The names of the tabs in each direction, in the margins around the zoomed-out page.
    private var directionLabels: some View {
        ZStack {
            ForEach(TableDirection.allCases, id: \.self) { direction in
                if let label = label(toward: direction) {
                    DirectionLabel(direction: direction, text: label.text, crosses: label.crosses)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment(for: direction))
                        .padding(Layout.labelInset)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private func label(toward direction: TableDirection) -> (text: String, crosses: Bool)? {
        if let tab = islands.destination(toward: direction) {
            return (tab.displayTitle, false)
        }
        if let island = islands.island(toward: direction) {
            return (island.title, true)
        }
        return nil
    }

    private func alignment(for direction: TableDirection) -> Alignment {
        switch direction {
        case .left: .leading
        case .right: .trailing
        case .up: .top
        case .down: .bottom
        }
    }

    // MARK: - Moves

    private func begin(_ travel: PageTravel) {
        if let tab = windowState.activeTab {
            islands.requestStoredSnapshot(for: tab)
        }
        shown = travel
        progress = 0
        arrivingTabID = nil
        let duration: TimeInterval = switch travel.style {
        case .slide: Layout.slideDuration
        case .cross: Layout.crossDuration
        case .jump: Layout.jumpDuration
        }
        withAnimation(reduceMotion ? .easeOut(duration: Layout.jumpDuration) : .easeInOut(duration: duration)) {
            progress = 1
        } completion: {
            guard shown?.id == travel.id else { return }
            arrivingTabID = windowState.activeTabID
            shown = nil
            islands.finishTravel(travel.id)
        }
    }
}

/// A page drawn as a slab: scaled about the center, rounded, with a shadow and a glass rim.
private struct SlabChrome: ViewModifier {
    let isSlab: Bool
    let scale: CGFloat

    private enum Layout {
        static let cornerRadius: CGFloat = 16
        static let shadowRadius: CGFloat = 22
        static let shadowOpacity: Double = 0.22
        static let rimOpacity: Double = 0.45
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: isSlab ? Layout.cornerRadius : 0, style: .continuous)
        content
            .clipShape(shape)
            .overlay {
                if isSlab {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(Layout.rimOpacity), .white.opacity(Layout.rimOpacity * 0.3), .white.opacity(Layout.rimOpacity * 0.6)],
                            startPoint: .topLeading, endPoint: .bottomTrailing,
                        ),
                        lineWidth: 1,
                    )
                    .allowsHitTesting(false)
                }
            }
            .shadow(color: .black.opacity(isSlab ? Layout.shadowOpacity : 0), radius: Layout.shadowRadius, y: 8)
            .scaleEffect(scale)
    }
}

/// Places a move's two slabs along its path.
private struct TravelMotion: ViewModifier {
    let style: TravelStyle
    let progress: CGFloat
    /// The slab's size on screen: one step of a slide is a slab and the gap.
    let step: CGSize
    let gap: CGFloat
    let incoming: Bool

    private enum Layout {
        static let crossScale: CGFloat = 0.9
    }

    func body(content: Content) -> some View {
        switch style {
        case let .slide(direction):
            let vector = Self.vector(direction, step: CGSize(width: step.width + gap, height: step.height + gap))
            let offset = incoming
                ? CGSize(width: vector.width * (1 - progress), height: vector.height * (1 - progress))
                : CGSize(width: -vector.width * progress, height: -vector.height * progress)
            content.offset(offset)
        case .cross:
            let scale = incoming ? Layout.crossScale + (1 - Layout.crossScale) * progress : 1 - (1 - Layout.crossScale) * progress
            content.scaleEffect(scale).opacity(incoming ? progress : 1 - progress)
        case .jump:
            content.opacity(incoming ? progress : 1 - progress)
        }
    }

    /// Where an incoming slab starts for a move in `direction`: one step off, the way it comes from.
    private static func vector(_ direction: TableDirection, step: CGSize) -> CGSize {
        switch direction {
        case .left: CGSize(width: -step.width, height: 0)
        case .right: CGSize(width: step.width, height: 0)
        case .up: CGSize(width: 0, height: -step.height)
        case .down: CGSize(width: 0, height: step.height)
        }
    }
}

/// The name of the tab a direction leads to, with its chevron; an island's name when the
/// direction crosses to it.
private struct DirectionLabel: View {
    let direction: TableDirection
    let text: String
    let crosses: Bool

    private var symbol: String {
        switch direction {
        case .left: crosses ? "chevron.left.2" : "chevron.left"
        case .right: crosses ? "chevron.right.2" : "chevron.right"
        case .up: crosses ? "chevron.up.2" : "chevron.up"
        case .down: crosses ? "chevron.down.2" : "chevron.down"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if direction == .left || direction == .up {
                Image(systemName: symbol)
            }
            Text(text)
                .lineLimit(1)
                .truncationMode(.tail)
            if direction == .right || direction == .down {
                Image(systemName: symbol)
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(crosses ? .secondary : .primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: Capsule())
        .frame(maxWidth: direction == .left || direction == .right ? 220 : 420)
        .accessibilityLabel("\(direction.rawValue): \(text)")
    }
}
