import SwiftUI

/// The floating tour on screen: a scrim over the page with the step's target lit, an
/// instruction card beside it, and a progress bar that fills as steps complete.
///
/// The target stays usable: the hosting view passes clicks through the lit areas, the scrim's
/// own hit area leaves them out, and the control rail is drawn above this overlay. Every frame
/// comes from the tour itself. The tour's beam requests are drawn by the light engine.
struct FloatingTourOverlay: View {
    @Environment(FloatingTourManager.self) private var tour
    @Environment(WindowState.self) private var windowState
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("floatingTabs.revealKey") private var revealKey = FloatingRevealKey.control
    @State private var cardSize = CGSize.zero
    /// A click on the dimmed page draws the eye back to the target.
    @State private var pulse = 0
    /// The beam revision whose travel has ended, so the engine draws nothing until the next.
    @State private var finishedBeamRevision: Int?
    private typealias Layout = FloatingTourLayout

    var body: some View {
        if let step = tour.currentStep {
            GeometryReader { geometry in
                let bounds = CGRect(origin: .zero, size: geometry.size)
                let spotlights = tour.spotlights(in: bounds)
                let anchor = tour.instructionAnchor(in: bounds)
                let origin = Layout.cardOrigin(
                    for: anchor,
                    cardSize: cardSize,
                    in: bounds,
                    avoiding: windowState.controlIsland.railFrame.isEmpty ? .null : windowState.controlIsland.railFrame,
                )
                ZStack(alignment: .topLeading) {
                    if tour.dimsPage {
                        scrim(spotlights: spotlights)
                        rings(spotlights)
                    }
                    beams(in: bounds)
                    progressBar(step: step)
                        .frame(width: bounds.width, alignment: .top)
                        .padding(.top, Layout.progressTop)
                    card(step)
                        .offset(x: origin.x, y: origin.y)
                }
                .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: spotlights)
                .animation(reduceMotion ? nil : .snappy(duration: 0.3), value: origin)
            }
            .ignoresSafeArea()
            .transition(.opacity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Refrax tour")
        }
    }

    // MARK: - Scrim

    /// A tap on the scrim closes a lens the way its own cover would, and points at the target again.
    private func scrim(spotlights: [TourSpotlight]) -> some View {
        Rectangle()
            .fill(.black.opacity(Layout.scrimOpacity))
            .mask {
                ZStack(alignment: .topLeading) {
                    Rectangle()
                    ForEach(Array(spotlights.enumerated()), id: \.offset) { _, spot in
                        RoundedRectangle(cornerRadius: spot.cornerRadius)
                            .frame(width: spot.rect.width, height: spot.rect.height)
                            .offset(x: spot.rect.minX, y: spot.rect.minY)
                            .blendMode(.destinationOut)
                    }
                }
                .compositingGroup()
            }
            .contentShape(SpotlightCutout(spotlights: spotlights), eoFill: true)
            .onTapGesture {
                pulse += 1
                if windowState.showsCommandLens {
                    windowState.closeCommandLens()
                }
            }
            .accessibilityHidden(true)
    }

    private func rings(_ spotlights: [TourSpotlight]) -> some View {
        ForEach(Array(spotlights.enumerated()), id: \.offset) { _, spot in
            RoundedRectangle(cornerRadius: spot.cornerRadius)
                .strokeBorder(Color.appAccentColor, lineWidth: Layout.ringWidth)
                .frame(width: spot.rect.width, height: spot.rect.height)
                .keyframeAnimator(initialValue: CGFloat(1), trigger: reduceMotion ? 0 : pulse) { ring, scale in
                    ring.scaleEffect(scale)
                } keyframes: { _ in
                    SpringKeyframe(Layout.pulseScale, duration: 0.15)
                    SpringKeyframe(1, duration: 0.3)
                }
                .offset(x: spot.rect.minX, y: spot.rect.minY)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Beams

    /// The tour's beams, from a control to what it opened, played once per revision above the
    /// scrim and under the card. The window's own beams rest while the tour runs, so each pair
    /// lights once.
    @ViewBuilder
    private func beams(in bounds: CGRect) -> some View {
        let requests = tour.beamRequests
        let revision = tour.beamRevision
        if !requests.isEmpty, finishedBeamRevision != revision {
            let style = LightStyle.guide
            let color = style.color(space: nil)
            LightTravel(
                paths: requests.map { style.path(ray: FloatingRayPath(from: $0.from, to: $0.to, in: bounds), color: color) },
                timing: style.timing,
            ) {
                finishedBeamRevision = revision
            }
            .id(revision)
            .accessibilityHidden(true)
        }
    }

    // MARK: - Progress

    private func progressBar(step: FloatingTourManager.Step) -> some View {
        HStack(spacing: Layout.progressPaddingH) {
            Capsule()
                .fill(.quaternary)
                .overlay(alignment: .leading) {
                    GeometryReader { track in
                        Capsule()
                            .fill(Color.appAccentColor)
                            .frame(width: track.size.width * tour.progress)
                    }
                }
                .frame(height: Layout.progressHeight)
            Text(step == .done ? "Done" : "\(step.completedSteps + 1) of \(FloatingTourManager.totalSteps)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, Layout.progressPaddingH)
        .padding(.vertical, Layout.progressPaddingV)
        .frame(width: Layout.progressWidth)
        .glassEffect(.regular, in: .capsule)
        .animation(reduceMotion ? nil : .snappy(duration: 0.4), value: tour.progress)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tour progress")
        .accessibilityValue("\(step.completedSteps) of \(FloatingTourManager.totalSteps) steps")
    }

    // MARK: - Card

    private var context: FloatingTourManager.Step.Context {
        .init(
            revealKey: revealKey,
            hasPage: windowState.activeTab != nil,
            lensIsOpen: windowState.showsCommandLens,
            layerRevealed: canvas.floatingVisibility.isRevealed,
            optionDragMovesPanel: windowState.controlIsland.configuration.optionDragTarget == .panel,
        )
    }

    private func card(_ step: FloatingTourManager.Step) -> some View {
        VStack(alignment: .leading, spacing: Layout.cardSpacing) {
            Label(step.title, systemImage: step.symbol)
                .font(.headline)
                .contentTransition(.symbolEffect(.replace))
            Text(step.instruction(in: context))
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if step == .done {
                    Button("Done") { tour.finish() }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.roundedRectangle(radius: Layout.cardInnerCornerRadius))
                }
                Spacer()
                if step != .done {
                    Button("Skip") { tour.skip() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("End the tour · Esc")
                }
            }
        }
        .padding(Layout.cardPadding)
        .frame(width: Layout.cardWidth, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Layout.cardCornerRadius))
        .onGeometryChange(for: CGSize.self) { $0.size } action: { cardSize = $0 }
        .accessibilityElement(children: .contain)
    }
}

/// The scrim's hit area: the whole window with every spotlight cut out, so a click on a lit
/// target reaches the target.
private nonisolated struct SpotlightCutout: Shape {
    var spotlights: [TourSpotlight]

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        for spot in spotlights {
            path.addRoundedRect(in: spot.rect, cornerSize: CGSize(width: spot.cornerRadius, height: spot.cornerRadius))
        }
        return path
    }
}
