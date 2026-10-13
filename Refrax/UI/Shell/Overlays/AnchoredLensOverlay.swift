import SwiftUI

// MARK: - Anchored Lens Overlay

/// The Command Lens in the page card's place, small style, with the page address in it.
///
/// Opening starts at the anchor's size and springs to the lens's width; closing springs back
/// to the anchor and then disappears. The island hides the card for as long as the lens is up
/// (``PageCardLensHandoff``), so the lens glass that springs from the card's frame is the only
/// object there.
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
        static let expandDuration: CGFloat = 0.25
        static let collapseDuration: CGFloat = 0.2
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
                        .frame(width: lensWidth(in: geometry.size))
                        .frame(minHeight: currentHeight)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                        .offset(lensOrigin(in: geometry.size))
                        .opacity(opacity)
                        .allowsHitTesting(true)
                }
            }
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
        let preferred = isExpanded ? 640.0 : ControlIslandPlacement.pageBranchWidth
        return min(preferred, max(1, size.width - 40))
    }

    private func lensOrigin(in size: CGSize) -> CGSize {
        guard windowState.usesFloatingTabs else { return CGSize(width: anchor.minX, height: 0) }
        return CGSize(
            width: min(max(20, anchor.minX), max(20, size.width - lensWidth(in: size) - 20)),
            height: min(max(20, anchor.minY), max(20, size.height - contentHeight - 20)),
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
