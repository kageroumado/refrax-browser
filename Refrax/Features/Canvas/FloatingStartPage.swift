import SwiftUI

/// The empty page, drawn as light. One beam leaves the rail's Command Lens row, enters the
/// lens on the page, and leaves it dispersed into one band per placed page, each ending on
/// a faint outline of that page at its saved place. The space color is the light: the beam
/// is the color itself, the bands its neighboring hues, and a soft field of it sits behind
/// the rail. Moving the rail moves the beam's origin. On first launch the bands end on three
/// dotted outlines and a note sits at each of the three objects; a space with pages shows
/// its recovery row and the outlines of its real pages.
struct FloatingStartPage: View {
    @Environment(WindowState.self) private var windowState
    @Environment(UndoRedoManager.self) private var undoRedo
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(TabManager.self) private var tabs
    @Environment(FloatingTourManager.self) private var tour
    @Environment(CommandLensManager.self) private var lens
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("startPage.hintsDismissed") private var hintsDismissed = false
    @AppStorage("floatingTabs.revealKey") private var revealKey = FloatingRevealKey.control
    /// The page's frame in window coordinates; everything measured in the window is drawn relative to it.
    @State private var pageFrame: CGRect = .zero
    /// The lens's frame in window coordinates.
    @State private var lensFrame: CGRect = .zero
    /// When the light started breathing; the beams' clock counts from here.
    @State private var epoch = Date.now

    private enum Layout {
        static let width: CGFloat = 640
        static let topInset: CGFloat = 150
        static let spacing: CGFloat = 28
        static let lensHeight: CGFloat = 52
        static let lensCornerRadius: CGFloat = 26
        static let rimOutset: CGFloat = 1.5
        static let rimGlowRadius: CGFloat = 6
        static let fieldDiameter: CGFloat = 640
        static let fieldOpacity: Double = 0.22
        static let outlineCornerRadius = CanvasTileLayout.slabCornerRadius
        static let outlineOpacity: Double = 0.35
        static let placeholderOpacity: Double = 0.25
        static let outlineTitleGap: CGFloat = 6
        static let outlineTitleHeight: CGFloat = 18
        static let leaderLength: CGFloat = 14
        static let leaderGap: CGFloat = 4
        static let noteWidth: CGFloat = 260
        static let noteSpacing: CGFloat = 4
        static let bottomInset: CGFloat = 24
        static let placeholderTitles = ["A page you keep", "Another, beside it", "One you kept visible"]
    }

    /// A page's place on the empty page: its outline and the title beneath it.
    private struct Outline: Identifiable {
        let id: AnyHashable
        let title: String
        let frame: CGRect
        let isPlaceholder: Bool
    }

    var body: some View {
        let island = windowState.controlIsland
        let bounds = windowBounds
        let railLensFrame = island.itemFrames[.commandLens] ?? .zero
        let places = outlines(in: bounds, railFrame: island.railFrame)
        let layout = PrismLayout(
            railLensFrame: railLensFrame,
            railFrame: island.railFrame,
            lensFrame: lensCapsule,
            pageFrames: places.map(\.frame),
            bounds: bounds,
        )
        let sourceCenter = island.railFrame.isEmpty ? layout.entry[0] : CGPoint(x: island.railFrame.midX, y: island.railFrame.midY)
        ZStack(alignment: .topLeading) {
            field(around: sourceCenter)
            if !lensFrame.isEmpty {
                light(layout)
                lensRim
            }
            ForEach(places) { place in
                outline(place)
            }
            .opacity(canvas.floatingVisibility.isRevealed ? 0 : 1)
            column
            if !hintsDismissed {
                railNote(beside: railLensFrame.isEmpty ? island.railFrame : railLensFrame, in: bounds)
                if let last = places.last {
                    placesNote(below: last)
                }
                gotIt
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { pageFrame = $0 }
        .onAppear { tour.offer() }
        .onDisappear { tour.startPageLensFrame = .zero }
    }

    // MARK: - Measures

    /// The window's content area in window coordinates, the space the rail and the pages are placed in.
    private var windowBounds: CGRect {
        if let size = windowState.window?.contentView?.bounds.size, size.width > 0, size.height > 0 {
            return CGRect(origin: .zero, size: size)
        }
        return CGRect(origin: .zero, size: pageFrame.size)
    }

    /// The lens's text capsule: the top of the lens's frame, which grows downward with suggestions.
    private var lensCapsule: CGRect {
        CGRect(x: lensFrame.minX, y: lensFrame.minY, width: lensFrame.width, height: min(lensFrame.height, Layout.lensHeight))
    }

    private var spaceColor: Color {
        windowState.activeSpace?.color ?? .appAccentColor
    }

    /// The lens is being typed in.
    private var isTightened: Bool {
        !lens.inputText.isEmpty
    }

    private func local(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x - pageFrame.minX, y: point.y - pageFrame.minY)
    }

    private func local(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -pageFrame.minX, dy: -pageFrame.minY)
    }

    private func localized(_ path: LightPath) -> LightPath {
        var localPath = path
        localPath.points = path.points.map(local)
        return localPath
    }

    /// The pages of this space at their places, or three placeholders when there are none.
    private func outlines(in bounds: CGRect, railFrame: CGRect) -> [Outline] {
        let pages = canvas.floatingTabs
        guard pages.isEmpty else {
            return pages.map { Outline(id: $0.id, title: $0.displayTitle, frame: canvas.floatingFrame(for: $0, in: bounds), isPlaceholder: false) }
        }
        return zip(PrismLayout.placeholderFrames(in: bounds, railFrame: railFrame), Layout.placeholderTitles).enumerated().map { index, place in
            Outline(id: "placeholder-\(index)", title: place.1, frame: place.0, isPlaceholder: true)
        }
    }

    // MARK: - Light

    /// A soft field of the space color behind the rail.
    private func field(around center: CGPoint) -> some View {
        Circle()
            .fill(RadialGradient(
                colors: [spaceColor.opacity(Layout.fieldOpacity), .clear],
                center: .center,
                startRadius: 0,
                endRadius: Layout.fieldDiameter / 2,
            ))
            .frame(width: Layout.fieldDiameter, height: Layout.fieldDiameter)
            .position(local(center))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// The beams on their clock: the entry beam pulses every few seconds and each band breathes on its own period.
    private func light(_ layout: PrismLayout) -> some View {
        let color = Color.Components(color: spaceColor)
        let tightened = isTightened
        return TimelineView(.animation(paused: reduceMotion)) { context in
            LightLayer(paths: layout.paths(color: color, time: context.date.timeIntervalSince(epoch), tightened: tightened, reduceMotion: reduceMotion)
                .map(localized))
        }
        .accessibilityHidden(true)
    }

    /// The lens's rim in the space color while it is being typed in.
    private var lensRim: some View {
        let capsule = local(lensCapsule).insetBy(dx: -Layout.rimOutset, dy: -Layout.rimOutset)
        return RoundedRectangle(cornerRadius: Layout.lensCornerRadius + Layout.rimOutset)
            .stroke(spaceColor, lineWidth: 1)
            .shadow(color: spaceColor.opacity(0.6), radius: Layout.rimGlowRadius)
            .frame(width: capsule.width, height: capsule.height)
            .offset(x: capsule.minX, y: capsule.minY)
            .opacity(isTightened ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: isTightened)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    // MARK: - Outlines

    private func outline(_ outline: Outline) -> some View {
        let frame = local(outline.frame)
        return VStack(alignment: .leading, spacing: Layout.outlineTitleGap) {
            RoundedRectangle(cornerRadius: Layout.outlineCornerRadius)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: outline.isPlaceholder ? [4, 4] : []))
                .foregroundStyle(.secondary.opacity(outline.isPlaceholder ? Layout.placeholderOpacity : Layout.outlineOpacity))
                .frame(width: frame.width, height: frame.height)
            Text(outline.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: frame.width, height: Layout.outlineTitleHeight, alignment: .leading)
        }
        .offset(x: frame.minX, y: frame.minY)
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(outline.isPlaceholder ? "A place for a page" : "\(outline.title), at its place")
    }

    // MARK: - The column

    /// The title, the lens, its note on first launch, and the way back.
    private var column: some View {
        VStack(spacing: 0) {
            Text("Refrax")
                .font(.title3.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, Layout.spacing)
            CommandLensView()
                .id(windowState.startPageLensRequest)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    lensFrame = $0
                    tour.startPageLensFrame = $0
                }
            if !hintsDismissed {
                lensNote
            }
            recovery
                .padding(.top, Layout.spacing)
        }
        .frame(maxWidth: Layout.width)
        .padding(.horizontal, 24)
        .padding(.top, Layout.topInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// A way back: the last closed page in this space, or the last page used here.
    @ViewBuilder
    private var recovery: some View {
        let recentlyClosed = undoRedo.recentlyClosedTabs.first(where: { $0.spaceID == windowState.activeSpaceID })
        let lastUsed = windowState.activeSpace?.mainTabs.max(by: { ($0.lastAccessed ?? $0.createdAt) < ($1.lastAccessed ?? $1.createdAt) })
        if recentlyClosed != nil || lastUsed != nil {
            HStack(spacing: 20) {
                if let recent = recentlyClosed {
                    Button {
                        if let index = undoRedo.recentlyClosedTabs.firstIndex(where: { $0.id == recent.id }) {
                            undoRedo.reopenClosedTab(at: index)
                        }
                    } label: {
                        Label("Reopen \(recent.customName ?? recent.title)", systemImage: "arrow.uturn.backward").lineLimit(1)
                    }
                    .help("Reopen the last closed page in this space")
                }
                if let lastUsed, let space = windowState.activeSpace {
                    Button {
                        tabs.setActiveTab(lastUsed, in: windowState)
                    } label: {
                        Label("Continue \(space.name)", systemImage: "arrow.right").lineLimit(1)
                    }
                    .help("Resume \(lastUsed.displayTitle)")
                }
            }
            .buttonStyle(.plain)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Notes

    private var leader: some View {
        Rectangle()
            .fill(spaceColor)
            .accessibilityHidden(true)
    }

    private func noteText(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Under the lens: what it takes.
    private var lensNote: some View {
        VStack(spacing: Layout.leaderGap) {
            leader.frame(width: 1, height: Layout.leaderLength)
            noteText("An address, a search, an open page, or a command.")
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }

    /// Beside the rail's lens row: the controls rest and move. The note sits on the side facing the window's middle.
    @ViewBuilder
    private func railNote(beside anchor: CGRect, in bounds: CGRect) -> some View {
        if !anchor.isEmpty {
            let onLeft = anchor.midX <= bounds.midX
            let row = local(anchor)
            let text = VStack(alignment: onLeft ? .leading : .trailing, spacing: Layout.noteSpacing) {
                noteText("Rests while you work. ⌥-drag moves it.")
                    .multilineTextAlignment(onLeft ? .leading : .trailing)
                Button("Customize…") { windowState.controlIsland.showsCustomization = true }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            let line = leader
                .frame(width: Layout.leaderLength, height: 1)
                .padding(.top, 8)
            HStack(alignment: .top, spacing: Layout.leaderGap) {
                if onLeft {
                    line
                    text
                } else {
                    text
                    line
                }
            }
            .frame(width: Layout.noteWidth, alignment: onLeft ? .leading : .trailing)
            .offset(x: onLeft ? row.maxX + Layout.leaderGap : row.minX - Layout.leaderGap - Layout.noteWidth, y: row.midY - 8)
            .accessibilityElement(children: .contain)
        }
    }

    /// Below the last outline: pages keep their places.
    private func placesNote(below outline: Outline) -> some View {
        let frame = local(outline.frame)
        return VStack(alignment: .leading, spacing: Layout.noteSpacing) {
            leader.frame(width: 1, height: Layout.leaderLength)
            noteText("Pages keep their places. Hold \(revealKey.glyph) to see each where you put it.")
            Button("Take the tour") { tour.start() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(width: min(Layout.noteWidth, frame.width), alignment: .leading)
        .offset(x: frame.minX, y: frame.maxY + Layout.outlineTitleGap + Layout.outlineTitleHeight + Layout.leaderGap)
        .accessibilityElement(children: .contain)
    }

    private var gotIt: some View {
        Button("Got it") { hintsDismissed = true }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, Layout.bottomInset)
    }
}
