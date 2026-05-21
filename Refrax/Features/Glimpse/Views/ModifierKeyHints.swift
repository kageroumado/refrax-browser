import AppKit
import SwiftUI

/// An overlay that shows hints when modifier keys are held.
///
/// Displays contextual tips for:
/// - **Option (⌥)**: Click link to open in Glimpse
/// - **Shift (⇧)**: Click link to open Link Preview
///
/// ## Usage
///
/// Add as an overlay to a web content container:
/// ```swift
/// WebViewContainer(page: page)
///     .overlay(alignment: .bottom) {
///         ModifierKeyHints()
///     }
/// ```
struct ModifierKeyHints: View {
    @Environment(BrowserSettings.self) private var settings
    @State private var activeModifier: ActiveModifier = .none

    /// Monitor for flag change events.
    @State private var flagsMonitor: Any?

    private enum ActiveModifier: Equatable {
        case none
        case option
        case shift
    }

    private enum Layout {
        static let animationDuration: Double = 0.15
        static let bottomPadding: CGFloat = 48
    }

    var body: some View {
        if settings.showModifierKeyHints {
            VStack {
                Spacer()

                if activeModifier != .none {
                    hintContent
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity,
                        ))
                }
            }
            .animation(.easeInOut(duration: Layout.animationDuration), value: activeModifier)
            .onAppear {
                setupMonitor()
            }
            .onDisappear {
                removeMonitor()
            }
        }
    }

    @ViewBuilder
    private var hintContent: some View {
        switch activeModifier {
        case .none:
            EmptyView()

        case .option:
            hintLabel(
                symbol: "⌥",
                text: "+Click link to open in Glimpse",
                systemImage: "cursorarrow.click.2",
            )

        case .shift:
            hintLabel(
                symbol: "⇧",
                text: "+Click link to open Link Preview",
                systemImage: "text.magnifyingglass",
            )
        }
    }

    private func hintLabel(symbol: String, text: String, systemImage: String) -> some View {
        Label {
            Text("\(symbol)\(text)")
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, Layout.bottomPadding)
        .allowsHitTesting(false)
    }

    private func setupMonitor() {
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            let flags = event.modifierFlags
            let hasCommand = flags.contains(.command)
            let hasControl = flags.contains(.control)
            let hasOption = flags.contains(.option)
            let hasShift = flags.contains(.shift)

            // Determine which single modifier is pressed (if any)
            // We only show hints for isolated modifier presses
            let newModifier: ActiveModifier = if hasOption, !hasCommand, !hasShift, !hasControl {
                .option
            } else if hasShift, !hasCommand, !hasOption, !hasControl {
                .shift
            } else {
                .none
            }

            if activeModifier != newModifier {
                activeModifier = newModifier
            }

            return event
        }
    }

    private func removeMonitor() {
        if let monitor = flagsMonitor {
            NSEvent.removeMonitor(monitor)
            flagsMonitor = nil
        }
    }
}

#Preview(traits: .modifier(RefraxPreviewModifier())) {
    ZStack {
        Color.gray.opacity(0.3)
        ModifierKeyHints()
    }
    .frame(width: 600, height: 400)
}
