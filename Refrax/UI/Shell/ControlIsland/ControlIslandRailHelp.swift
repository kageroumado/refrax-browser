import AppKit
import SwiftUI

/// The help label a rail control shows beside the rail, on the side away from the window
/// edge, so it never covers the next control. It keeps the system tooltip's timing: it
/// appears after the pointer rests on a control for the initial tooltip delay, and at once
/// while the pointer moves from one control to the next.
@MainActor
@Observable
final class ControlIslandRailHelp {
    /// The help on screen: its text and the control it describes, in the rail's coordinate space.
    struct Shown: Equatable {
        let text: String
        let anchor: CGRect
    }

    private enum Timing {
        /// The system's default delay before a tooltip appears.
        static let defaultInitialDelay: Duration = .milliseconds(1_000)
        /// A label that went away this recently lets the next control's appear at once.
        static let handoff: TimeInterval = 0.5
    }

    private(set) var shown: Shown?
    @ObservationIgnored private var hiddenAt: Date?

    /// The delay before a label appears: the system's tooltip delay, or none while the pointer
    /// moves on from a label that just showed.
    var delay: Duration {
        if shown != nil {
            return .zero
        }
        if let hiddenAt, Date().timeIntervalSince(hiddenAt) < Timing.handoff {
            return .zero
        }
        let milliseconds = UserDefaults.standard.integer(forKey: "NSInitialToolTipDelay")
        return milliseconds > 0 ? .milliseconds(milliseconds) : Timing.defaultInitialDelay
    }

    func show(_ text: String, beside anchor: CGRect) {
        shown = Shown(text: text, anchor: anchor)
    }

    /// Hides the label, when it still describes `anchor`.
    func hide(_ anchor: CGRect) {
        guard shown?.anchor == anchor else { return }
        shown = nil
        hiddenAt = Date()
    }

    /// Hides any label at once, as moving the rail does.
    func dismiss() {
        shown = nil
        hiddenAt = nil
    }
}

extension View {
    /// Help for a control on the rail, shown beside the rail rather than over it; plain
    /// `.help` where no rail hosts the control.
    func railHelp(_ text: String) -> some View {
        modifier(RailHelpModifier(text: text))
    }
}

private struct RailHelpModifier: ViewModifier {
    let text: String

    @Environment(ControlIslandRailHelp.self) private var railHelp: ControlIslandRailHelp?
    @State private var frame = CGRect.zero
    @State private var isHovered = false

    func body(content: Content) -> some View {
        if let railHelp {
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("browserControls")) } action: { frame = $0 }
                .onHover { isHovered = $0 }
                .onDisappear { railHelp.hide(frame) }
                .task(id: isHovered) {
                    guard isHovered else {
                        railHelp.hide(frame)
                        return
                    }
                    try? await Task.sleep(for: railHelp.delay)
                    guard !Task.isCancelled, isHovered else { return }
                    railHelp.show(text, beside: frame)
                }
                .accessibilityHint(text)
        } else {
            content.help(text)
        }
    }
}

/// The label itself: one line of help on frosted glass.
struct ControlIslandRailHelpLabel: View {
    let text: String

    private enum Layout {
        static let horizontalPadding: CGFloat = 8
        static let verticalPadding: CGFloat = 4
        static let cornerRadius: CGFloat = 7
    }

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.primary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Layout.horizontalPadding)
            .padding(.vertical, Layout.verticalPadding)
            .background(.regularMaterial, in: .rect(cornerRadius: Layout.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Layout.cornerRadius)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
