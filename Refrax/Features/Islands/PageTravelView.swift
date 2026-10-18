import AppKit
import SwiftUI

/// The window's page, and the way one page replaces another.
///
/// At rest the page fills the window, live. The moment the reveal key goes down the window's
/// controls step away, the window server shows a frame of the page alone, and that frame
/// becomes the page's image, which takes its place: a slab at 84%, with a shadow and a glass
/// rim over the window's tinted background, the margins naming the tab in each direction.
/// Every move while the key is held slides slabs of images, the outgoing page's snapshot and
/// the incoming tab's stored one, with the background in the gap between them; nothing is
/// live and nothing takes input. Only when the key is released does the slab grow back to
/// the window, shedding its rim and shadow as it lands, and the live page mount beneath it,
/// staying under its snapshot until it has painted. A crossing to another island shrinks the
/// outgoing slab away and grows the next one in.
struct PageTravelView: View {
    @Environment(IslandController.self) private var islands
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(WindowState.self) private var windowState
    @Environment(WebPagePool.self) private var pagePool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The move being shown and its progress from 0 (just begun) to 1 (arrived).
    @State private var shown: PageTravel?
    @State private var progress: CGFloat = 1
    /// The page's image stands in for it: while the key is held, and until the live page has
    /// painted after it is let go.
    @State private var showsSlab = false
    @State private var slabScale: CGFloat = 1
    /// The tab whose live page is painting under its snapshot.
    @State private var arrivingTabID: UUID?
    /// The view's size: it runs past the window's top and bottom, under the title bar and the
    /// window's corners, the way the live page does.
    @State private var size: CGSize = .zero
    /// The part of the view the window shows, in its coordinates: the page as a picture of
    /// it is drawn here, at the picture's own size, so the live page lands on it exactly.
    @State private var visible: CGRect = .zero
    /// The wait for the frame without the window's controls, then the capture.
    @State private var captureTask: Task<Void, Never>?
    /// The slab's lean against an edge that did not give.
    @State private var bumpOffset: CGSize = .zero

    private enum Layout {
        /// The page's share of the window while the reveal key is held.
        static let inspectionScale: CGFloat = 0.84
        static let inspectDuration: TimeInterval = 0.28
        static let slideDuration: TimeInterval = 0.34
        static let labelFade: TimeInterval = 0.12
        static let crossDuration: TimeInterval = 0.4
        static let jumpDuration: TimeInterval = 0.2
        /// The background showing between two sliding slabs.
        static let gap: CGFloat = 28
        /// How far the slab leans against an edge.
        static let bumpDistance: CGFloat = 22
        static let firstPaintFade: TimeInterval = 0.18
    }

    private var isInspecting: Bool {
        canvas.isMomentaryNavigation
    }

    private var isTraveling: Bool {
        shown != nil
    }

    /// The live page is drawn: no slab stands in for it and no move is under way.
    private var showsLive: Bool {
        !showsSlab && !isTraveling
    }

    private var slabSize: CGSize {
        CGSize(width: visible.width * Layout.inspectionScale, height: visible.height * Layout.inspectionScale)
    }

    var body: some View {
        ZStack {
            background
            if let tab = windowState.activeTab {
                livePage(tab)
                if showsSlab, !isTraveling {
                    slab(image: islands.snapshot(for: tab.id), tab: tab, scale: slabScale)
                        .offset(bumpOffset)
                        .allowsHitTesting(false)
                }
            }
            if let shown {
                travelingSlabs(shown)
            }
            if isInspecting, showsSlab {
                directionLabels
                    .opacity(isTraveling ? 0 : 1)
                    .animation(.easeOut(duration: Layout.labelFade), value: isTraveling)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .background {
            WindowVisibleRectReader { rect in
                visible = rect
                islands.updateViewport(rect)
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .onChange(of: showsLive && arrivingTabID == nil, initial: true) { _, visible in
            islands.liveIsVisible = visible
        }
        .onChange(of: showsLive, initial: true) { _, live in
            if live {
                canvas.showsPageSlab = false
            }
        }
        .onChange(of: isInspecting) { _, inspecting in
            if inspecting {
                beginInspecting()
            } else if !isTraveling {
                endInspecting()
            }
        }
        .onChange(of: islands.travel?.id) { _, id in
            guard let travel = islands.travel, travel.id == id else { return }
            begin(travel)
        }
        .onChange(of: islands.bump?.id) { _, id in
            guard let bump = islands.bump, bump.id == id, showsSlab, !isTraveling else { return }
            lean(toward: bump.direction)
        }
    }

    // MARK: - Layers

    private var background: some View {
        Color(nsColor: .windowBackgroundColor)
            .overlay(windowState.controlIslandTint)
            .ignoresSafeArea()
    }

    /// The live page, full size; invisible and deaf while a slab stands in for it, and under
    /// its snapshot until it has painted after arriving.
    private func livePage(_ tab: Tab) -> some View {
        let arriving = arrivingTabID == tab.id
        return UnifiedContentView(tab: tab)
            .id(tab.id)
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .topLeading) {
                if arriving {
                    snapshotFace(for: tab)
                        .offset(x: visible.minX, y: visible.minY)
                        .transition(.opacity)
                }
            }
            .opacity(showsLive ? 1 : 0)
            .allowsHitTesting(showsLive && !arriving)
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
            // A page that has finished loading while on screen is captured, so its slab is
            // a picture of it from then on, in this session and the next.
            .task(id: LoadKey(tabID: tab.id, isLoading: pagePool.existingPage(for: tab.activePage)?.isLoading ?? true, visible: showsLive && !arriving)) {
                guard showsLive, !arriving, pagePool.existingPage(for: tab.activePage)?.isLoading == false else { return }
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                await islands.refreshSnapshot(of: tab)
            }
    }

    /// The two slabs of a move: images only.
    @ViewBuilder
    private func travelingSlabs(_ travel: PageTravel) -> some View {
        let incoming = windowState.activeTab
        ZStack {
            slab(image: travel.outgoing, tab: nil, scale: Layout.inspectionScale)
                .modifier(TravelMotion(style: travel.style, progress: progress, step: slabSize, gap: Layout.gap, incoming: false))
            slab(image: incoming.flatMap { islands.snapshot(for: $0.id) }, tab: incoming, scale: Layout.inspectionScale)
                .modifier(TravelMotion(style: travel.style, progress: progress, step: slabSize, gap: Layout.gap, incoming: true))
        }
        .allowsHitTesting(false)
    }

    /// A slab of a page's image at the size the window shows the page, scaled about its
    /// center, or its placeholder.
    private func slab(image: NSImage?, tab: Tab?, scale: CGFloat) -> some View {
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
        .frame(width: visible.width, height: visible.height, alignment: .topLeading)
        .clipped()
        .modifier(SlabChrome(scale: scale, slabScale: Layout.inspectionScale))
        .position(x: visible.midX, y: visible.midY)
    }

    @ViewBuilder
    private func snapshotFace(for tab: Tab) -> some View {
        if let image = islands.snapshot(for: tab.id) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: visible.width, height: visible.height, alignment: .topLeading)
                .clipped()
        } else {
            PagePlaceholder(tab: tab)
                .frame(width: visible.width, height: visible.height)
        }
    }

    /// The names of the tabs in each direction, each sitting on the slab's rim on that side.
    private var directionLabels: some View {
        let slab = CGRect(
            x: visible.minX + (visible.width - slabSize.width) / 2, y: visible.minY + (visible.height - slabSize.height) / 2,
            width: slabSize.width, height: slabSize.height,
        )
        return ZStack {
            ForEach(TableDirection.allCases, id: \.self) { direction in
                if let label = label(toward: direction) {
                    DirectionLabel(
                        direction: direction, text: label.text, crosses: label.crosses,
                        isArmed: label.crosses && islands.armedCrossing?.direction == direction,
                    )
                    .position(Self.labelPosition(for: direction, on: slab))
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    private static func labelPosition(for direction: TableDirection, on slab: CGRect) -> CGPoint {
        switch direction {
        case .left: CGPoint(x: slab.minX, y: slab.midY)
        case .right: CGPoint(x: slab.maxX, y: slab.midY)
        case .up: CGPoint(x: slab.midX, y: slab.minY)
        case .down: CGPoint(x: slab.midX, y: slab.maxY)
        }
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

    // MARK: - Inspecting

    /// The key went down: the window's controls step away, the window server shows the page
    /// alone, the page is captured, and its image steps back to a slab. A slab still on its
    /// way back just turns around.
    private func beginInspecting() {
        guard let tab = windowState.activeTab else { return }
        guard !showsSlab else {
            stepBack()
            return
        }
        captureTask?.cancel()
        canvas.isCapturingPage = true
        captureTask = Task(name: "Capture the page for inspecting") {
            try? await Task.sleep(for: PageCapture.compositingDelay)
            canvas.isCapturingPage = false
            guard !Task.isCancelled, isInspecting, !isTraveling, !showsSlab else { return }
            islands.captureSnapshot(of: tab)
            canvas.showsPageSlab = true
            showsSlab = true
            stepBack()
        }
    }

    private func stepBack() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: Layout.inspectDuration)) {
            slabScale = Layout.inspectionScale
        }
    }

    /// The slab leans the way it was pushed and springs back: the edge did not give.
    private func lean(toward direction: TableDirection) {
        let unit = TravelMotion.vector(direction, step: CGSize(width: 1, height: 1))
        let lean = CGSize(width: -unit.width * Layout.bumpDistance, height: -unit.height * Layout.bumpDistance)
        if reduceMotion {
            return
        }
        withAnimation(.snappy(duration: 0.14)) {
            bumpOffset = lean
        } completion: {
            withAnimation(.bouncy(duration: 0.42, extraBounce: 0.1)) {
                bumpOffset = .zero
            }
        }
    }

    /// The key was let go: the slab grows back to the window and the live page mounts under
    /// it, its snapshot over it until it has painted, with nothing moving at the swap.
    private func endInspecting() {
        captureTask?.cancel()
        captureTask = nil
        canvas.isCapturingPage = false
        islands.leaveEdges()
        guard showsSlab else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: Layout.inspectDuration)) {
            slabScale = 1
        } completion: {
            guard !isInspecting, !isTraveling else { return }
            var swap = Transaction()
            swap.disablesAnimations = true
            withTransaction(swap) {
                arrivingTabID = windowState.activeTabID
                showsSlab = false
            }
        }
    }

    // MARK: - Moves

    private func begin(_ travel: PageTravel) {
        if let tab = windowState.activeTab {
            islands.requestStoredSnapshot(for: tab)
        }
        canvas.showsPageSlab = true
        shown = travel
        progress = 0
        arrivingTabID = nil
        let duration: TimeInterval = switch travel.style {
        case .slide: Layout.slideDuration
        case .cross: Layout.crossDuration
        case .jump: Layout.jumpDuration
        }
        let motion: Animation = switch travel.style {
        case .slide: .smooth(duration: duration)
        case .cross, .jump: .easeInOut(duration: duration)
        }
        withAnimation(reduceMotion ? .easeOut(duration: Layout.jumpDuration) : motion) {
            progress = 1
        } completion: {
            guard shown?.id == travel.id else { return }
            shown = nil
            islands.finishTravel(travel.id)
            if isInspecting {
                // The key is still down: the arrived slab stays an image until it is let go.
                showsSlab = true
                slabScale = Layout.inspectionScale
            } else {
                showsSlab = true
                slabScale = Layout.inspectionScale
                endInspecting()
            }
        }
    }
}

/// A page's image drawn as a slab: scaled about the center, rounded, with a shadow and a
/// glass rim. The chrome follows the scale: at the window's size there is none, so the
/// image is the page's pixels and nothing else, and the live page can take over under it
/// without a seam.
private struct SlabChrome: ViewModifier, Animatable {
    var scale: CGFloat
    /// The scale at which the slab wears its whole rim and shadow.
    let slabScale: CGFloat

    var animatableData: CGFloat {
        get { scale }
        set { scale = newValue }
    }

    private enum Layout {
        static let cornerRadius: CGFloat = 16
        static let shadowRadius: CGFloat = 22
        static let shadowOffset: CGFloat = 8
        static let shadowOpacity: Double = 0.22
    }

    /// How much of a slab the page is: 0 at the window's size, 1 stepped back.
    private var amount: CGFloat {
        min(1, max(0, (1 - scale) / (1 - slabScale)))
    }

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Layout.cornerRadius * amount, style: .continuous)
        content
            .clipShape(shape)
            // The shadow is cast by a shape under the image, never computed from the image:
            // a filter over a view clipped by an animating shape leaves its corners unrendered.
            .background {
                shape.fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(
                        color: .black.opacity(Layout.shadowOpacity * amount),
                        radius: Layout.shadowRadius * amount, y: Layout.shadowOffset * amount,
                    )
            }
            .overlay {
                ZStack {
                    shape.strokeBorder(
                        LinearGradient(
                            stops: [
                                .init(color: .white.opacity(0.7), location: 0),
                                .init(color: .white.opacity(0.18), location: 0.45),
                                .init(color: .white.opacity(0.35), location: 1),
                            ],
                            startPoint: .top, endPoint: .bottom,
                        ),
                        lineWidth: 1,
                    )
                    shape.inset(by: -0.5).strokeBorder(.black.opacity(0.14), lineWidth: 0.5)
                }
                .opacity(amount)
            }
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
    static func vector(_ direction: TableDirection, step: CGSize) -> CGSize {
        switch direction {
        case .left: CGSize(width: -step.width, height: 0)
        case .right: CGSize(width: step.width, height: 0)
        case .up: CGSize(width: 0, height: -step.height)
        case .down: CGSize(width: 0, height: step.height)
        }
    }
}

/// The name of the tab a direction leads to, with its chevron; an island's name when the
/// direction crosses to it, lit once its edge has been pushed and the next push will cross.
private struct DirectionLabel: View {
    let direction: TableDirection
    let text: String
    let crosses: Bool
    let isArmed: Bool

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
        .foregroundStyle(isArmed ? AnyShapeStyle(Color.appAccentColor) : crosses ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: Capsule())
        .animation(.easeOut(duration: 0.15), value: isArmed)
        .frame(maxWidth: direction == .left || direction == .right ? 220 : 420)
        .accessibilityLabel("\(direction.rawValue): \(text)")
    }
}

/// Reports the part of its frame the window shows, in its own top-left coordinates: the page
/// view runs past the window's edges, and only what the window shows is captured and drawn.
private struct WindowVisibleRectReader: NSViewRepresentable {
    let onChange: (CGRect) -> Void

    func makeNSView(context _: Context) -> WindowVisibleRectView {
        let view = WindowVisibleRectView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ view: WindowVisibleRectView, context _: Context) {
        view.onChange = onChange
    }
}

private final class WindowVisibleRectView: NSView {
    var onChange: ((CGRect) -> Void)?
    private var reported: CGRect = .null

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        report()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        report()
    }

    private func report() {
        guard let content = window?.contentView else { return }
        let visible = convert(convert(bounds, to: content).intersection(content.bounds), from: content)
        guard visible != reported else { return }
        reported = visible
        // Layout runs inside SwiftUI's update; the state it feeds changes on the next turn.
        DispatchQueue.main.async { [self] in onChange?(visible) }
    }
}

/// What decides when a page is captured after loading.
private struct LoadKey: Equatable {
    var tabID: UUID
    var isLoading: Bool
    var visible: Bool
}
