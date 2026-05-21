import SwiftUI

// MARK: - Address Lens Overlay

/// Overlay for the address lens with staged animation.
///
/// The animation works in two phases:
/// - **Opening**: Instantly appears at address bar size, then animates to expanded size
/// - **Closing**: Animates back to address bar size, then instantly disappears
struct AddressLensOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(WindowState.self) private var windowState

    private enum AnimationPhase {
        case hidden
        case matchingAddressBar
        case expanded
    }

    @State private var phase: AnimationPhase = .hidden
    @State private var opacity = 1.0

    private enum Constants {
        static let expandedWidthMultiplier: CGFloat = 2.5
        static let expandedHeightPadding: CGFloat = 0
        static let expandedCornerRadius: CGFloat = 16 // Match CommandLensView.Layout.cornerRadiusSmall
        static let shadowOpacity: CGFloat = 0.15
        static let shadowRadius: CGFloat = 16
        static let shadowY: CGFloat = 8
        static let expandDuration: CGFloat = 0.25
        static let collapseDuration: CGFloat = 0.2
    }

    private var addressBarFrame: CGRect {
        windowState.addressBarFrame
    }

    private var addressBarCornerRadius: CGFloat {
        Refrax.Constants.AddressBar.height / 2
    }

    private var isExpanded: Bool {
        phase == .expanded
    }

    private var currentWidth: CGFloat {
        isExpanded
            ? addressBarFrame.width * Constants.expandedWidthMultiplier
            : addressBarFrame.width
    }

    private var currentHeight: CGFloat {
        isExpanded
            ? addressBarFrame.height + Constants.expandedHeightPadding
            : addressBarFrame.height
    }

    private var currentCornerRadius: CGFloat {
        isExpanded ? Constants.expandedCornerRadius : addressBarCornerRadius
    }

    var body: some View {
        if phase != .hidden {
            ZStack(alignment: .topLeading) {
                clickCapture

                CommandLensView()
                    .smallStyle()
                    .frame(width: currentWidth)
                    .frame(minHeight: currentHeight)
                    .offset(x: addressBarFrame.minX, y: 0)
                    .opacity(opacity)
                    .allowsHitTesting(true)
            }
        }

        Color.clear
            .onChange(of: windowState.showsAddressLens) { wasShowing, isShowing in
                if isShowing, !wasShowing {
                    openLens()
                } else if !isShowing, wasShowing {
                    closeLens()
                }
            }
    }

    private var clickCapture: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .onTapGesture {
                windowState.closeAddressLens()
            }
    }

    private func openLens() {
        phase = .matchingAddressBar

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
            phase = .matchingAddressBar
            opacity = 0
        } completion: {
            phase = .hidden
        }
    }
}
