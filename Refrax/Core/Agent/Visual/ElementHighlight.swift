import SwiftUI

/// Overlay view for highlighting page elements during agent interaction.
///
/// Renders a rounded rectangle with border and subtle fill based on the
/// highlight style. Supports standard, about-to-act (pulsing), and
/// reading styles.
///
/// ## Animation
///
/// Uses explicit `.animation()` modifiers for transitions. The "about to act"
/// pulse is driven by a local `@State` phase to avoid polluting observed state.
/// Continuous animations respect `accessibilityReduceMotion`.
struct ElementHighlightView: View {
    let info: ElementHighlightInfo

    /// Phase driver for the "about to act" pulse.
    @State private var pulsePhase: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Constants {
        static let borderWidth: CGFloat = 2
        static let cornerRadius: CGFloat = 6
        static let fillOpacity: CGFloat = 0.08
        static let borderOpacity: CGFloat = 0.6
        static let pulseMaxScale: CGFloat = 1.03
    }

    var body: some View {
        highlightShape
            .position(
                x: info.rect.midX,
                y: info.rect.midY,
            )
            .opacity(info.opacity)
            .animation(.easeInOut(duration: 0.2), value: info.opacity)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var highlightShape: some View {
        switch info.style {
        case .standard:
            standardHighlight
        case .aboutToAct:
            pulsingHighlight
        case .reading:
            readingHighlight
        }
    }

    private var standardHighlight: some View {
        RoundedRectangle(cornerRadius: Constants.cornerRadius)
            .fill(Color.appAccentColor.opacity(Constants.fillOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: Constants.cornerRadius)
                    .stroke(Color.appAccentColor.opacity(Constants.borderOpacity), lineWidth: Constants.borderWidth),
            )
            .frame(width: info.rect.width, height: info.rect.height)
    }

    private var pulsingHighlight: some View {
        RoundedRectangle(cornerRadius: Constants.cornerRadius)
            .fill(Color.appAccentColor.opacity(Constants.fillOpacity + pulsePhase * 0.06))
            .overlay(
                RoundedRectangle(cornerRadius: Constants.cornerRadius)
                    .stroke(
                        Color.appAccentColor.opacity(Constants.borderOpacity + pulsePhase * 0.2),
                        lineWidth: Constants.borderWidth,
                    ),
            )
            .frame(width: info.rect.width, height: info.rect.height)
            .scaleEffect(1.0 + pulsePhase * (Constants.pulseMaxScale - 1.0))
            .onAppear {
                guard !reduceMotion else {
                    pulsePhase = 0.5
                    return
                }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    pulsePhase = 1
                }
            }
    }

    private var readingHighlight: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(Color.appAccentColor.opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Color.appAccentColor.opacity(0.4), lineWidth: 1),
            )
            .frame(width: info.rect.width, height: info.rect.height)
    }
}

/// Container view that renders all active element highlights.
///
/// Positioned within the overlay coordinate space. Each highlight
/// fades in on appearance with a 0.2s ease transition.
struct ElementHighlightLayer: View {
    let highlights: [ElementHighlightInfo]

    var body: some View {
        ForEach(highlights) { info in
            ElementHighlightView(info: info)
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
        }
    }
}

// MARK: - Preview

#Preview("Highlight Styles") {
    ZStack {
        Color.white

        // Standard
        ElementHighlightView(info: ElementHighlightInfo(
            rect: CGRect(x: 50, y: 50, width: 200, height: 40),
            style: .standard,
        ))

        // About to act
        ElementHighlightView(info: ElementHighlightInfo(
            rect: CGRect(x: 50, y: 120, width: 200, height: 40),
            style: .aboutToAct,
        ))

        // Reading
        ElementHighlightView(info: ElementHighlightInfo(
            rect: CGRect(x: 50, y: 190, width: 200, height: 80),
            style: .reading,
        ))
    }
    .frame(width: 300, height: 300)
}
