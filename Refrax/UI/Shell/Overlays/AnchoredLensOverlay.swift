import SwiftUI

// MARK: - Anchored Lens Overlay

/// The Command Lens in the page card's place, small style, with the page address in it.
///
/// With the Control Island the lens is the card becoming a field: it opens on the card's exact
/// frame with the card's height, radius, tint and favicon (``CommandLensFieldStyle``), while
/// the island removes the card, then widens away from the rail. Closing narrows it back to
/// the card's frame as the card returns. The overlay ignores the safe area because the island
/// measures the card in full window coordinates.
struct AnchoredLensOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(WindowState.self) private var windowState

    private enum AnimationPhase {
        case hidden
        case matchingAnchor
        case expanded
    }

    @State private var phase: AnimationPhase = .hidden
    @State private var opacity = 1.0
    @State private var contentHeight: CGFloat = 400
    /// The anchor the lens opened at, kept through the closing animation.
    @State private var anchor: CGRect = .zero

    private enum Constants {
        static let expandedWidthMultiplier: CGFloat = 2.5
        static let expandedCornerRadius: CGFloat = 16 // Match CommandLensView.Layout.cornerRadiusSmall
        static let expandDuration: CGFloat = 0.28
        static let collapseDuration: CGFloat = 0.2
        /// The field's width once it has unfolded from the card.
        static let fieldWidth: CGFloat = 640
    }

    private var anchorCornerRadius: CGFloat {
        Refrax.Constants.AddressBar.height / 2
    }

    private var isExpanded: Bool {
        phase == .expanded
    }

    private var currentWidth: CGFloat {
        isExpanded ? anchor.width * Constants.expandedWidthMultiplier : anchor.width
    }

    private var currentHeight: CGFloat {
        anchor.height
    }

    private var currentCornerRadius: CGFloat {
        isExpanded ? Constants.expandedCornerRadius : anchorCornerRadius
    }

    var body: some View {
        if phase != .hidden {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    clickCapture

                    CommandLensView()
                        .smallStyle()
                        .environment(\.commandLensFieldStyle, fieldStyle)
                        .frame(width: lensWidth(in: geometry.size))
                        .frame(minHeight: currentHeight)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                        .offset(lensOrigin(in: geometry.size))
                        .opacity(opacity)
                        .allowsHitTesting(true)
                }
            }
            .ignoresSafeArea(edges: windowState.usesFloatingTabs ? .all : [])
        }

        Color.clear
            .onChange(of: windowState.showsAnchoredLens) { wasShowing, isShowing in
                if isShowing, !wasShowing {
                    openLens()
                } else if !isShowing, wasShowing {
                    closeLens()
                }
            }
    }

    private func lensWidth(in size: CGSize) -> CGFloat {
        guard windowState.usesFloatingTabs else { return currentWidth }
        let preferred = isExpanded ? max(Constants.fieldWidth, anchor.width) : anchor.width
        return min(preferred, max(1, size.width - ControlIslandPlacement.margin * 2))
    }

    /// The field keeps the card's edge nearest the rail and grows away from it.
    private func lensOrigin(in size: CGSize) -> CGSize {
        guard windowState.usesFloatingTabs else { return CGSize(width: anchor.minX, height: 0) }
        let width = lensWidth(in: size)
        let margin = ControlIslandPlacement.margin
        let growsLeft = anchor.midX > size.width / 2
        let x = growsLeft ? anchor.maxX - width : anchor.minX
        return CGSize(
            width: min(max(margin, x), max(margin, size.width - width - margin)),
            height: min(max(margin, anchor.minY), max(margin, size.height - contentHeight - margin)),
        )
    }

    private var fieldStyle: CommandLensFieldStyle? {
        guard windowState.usesFloatingTabs else { return nil }
        return CommandLensFieldStyle(
            height: ControlIslandPlacement.pageBranchHeight,
            cornerRadius: ControlIslandPlacement.pageBranchHeight / 2,
            leadingInset: ControlIslandPageBranch.Layout.leadingInset,
            trailingInset: ControlIslandPageBranch.Layout.leadingInset,
            iconSize: ControlIslandPageBranch.Layout.faviconSize,
            iconGap: ControlIslandPageBranch.Layout.faviconGap,
            tint: windowState.controlIslandTint,
        )
    }

    private var clickCapture: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .onTapGesture {
                windowState.closeCommandLens()
            }
    }

    private func openLens() {
        anchor = windowState.commandLensEntrance?.anchor ?? windowState.addressBarFrame
        phase = .matchingAnchor

        let animation: Animation? = reduceMotion
            ? nil
            : .spring(duration: Constants.expandDuration)

        opacity = 1
        withAnimation(animation) {
            phase = .expanded
        }
    }

    private func closeLens() {
        let animation: Animation? = reduceMotion
            ? nil
            : .spring(duration: Constants.collapseDuration)

        withAnimation(animation) {
            phase = .matchingAnchor
            opacity = 0
        } completion: {
            phase = .hidden
        }
    }
}
