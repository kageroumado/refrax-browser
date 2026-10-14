import AppKit
import SwiftUI

/// The floating layer's empty area while a lasso can start: a ⇧-drag draws the lasso, and the
/// cards it encircles become the selection.
struct FloatingLassoSurface: View {
    let area: CGRect
    @Environment(TabCanvasManager.self) private var canvas
    @State private var lasso: LassoSelection?

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("floatingTabs"))
                .onChanged { value in
                    if lasso == nil {
                        lasso = LassoSelection(at: value.startLocation)
                        canvas.beginFloatingManipulation()
                    }
                    lasso?.extend(to: value.location)
                }
                .onEnded { _ in
                    if let lasso {
                        canvas.finishFloatingLasso(lasso, in: area)
                    }
                    lasso = nil
                    canvas.endFloatingManipulation()
                })
            .overlay {
                if let lasso, lasso.isDrawing {
                    LassoShape(lasso: lasso)
                        .fill(Color.appAccentColor.opacity(LassoSelection.fillOpacity))
                    LassoShape(lasso: lasso)
                        .stroke(Color.appAccentColor, style: StrokeStyle(
                            lineWidth: LassoSelection.lineWidth, lineCap: .round, lineJoin: .round, dash: LassoSelection.dash,
                        ))
                }
            }
            .accessibilityHidden(true)
    }
}

/// The options for the selected cards, in a glass capsule under the selection: Group, filled
/// as the primary option, then Arrange, Move to Space, and Close.
struct FloatingSelectionCapsule: View {
    let area: CGRect
    @Environment(TabCanvasManager.self) private var canvas
    @State private var size = CGSize.zero

    private enum Layout {
        static let spacing: CGFloat = 2
        static let horizontalPadding: CGFloat = 8
        static let verticalPadding: CGFloat = 4
        static let buttonPadding: CGFloat = 8
        static let buttonHeight: CGFloat = 28
        static let shadowRadius: CGFloat = 14
        static let shadowY: CGFloat = 6
    }

    var body: some View {
        if canvas.floatingVisibility.isRevealed, let bounds = canvas.floatingSelectionBounds(in: area) {
            let origin = FloatingArrangement.capsuleOrigin(for: bounds, size: size, in: area)
            capsule
                .fixedSize()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                .offset(x: origin.x, y: origin.y)
                .onChange(of: CGRect(origin: origin, size: size), initial: true) { _, frame in
                    canvas.floatingSelectionCapsuleFrame = frame
                }
                .onDisappear { canvas.floatingSelectionCapsuleFrame = .zero }
                .transition(.opacity)
        }
    }

    private var capsule: some View {
        let count = canvas.selectedFloatingTabIDs.count
        let spaces = canvas.otherSpaces
        return HStack(spacing: Layout.spacing) {
            Text("\(count) selected")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Layout.buttonPadding)
            groupButton(isPrimary: count > 1)
            Menu {
                ForEach(FloatingArrangement.allCases, id: \.self) { arrangement in
                    Button(arrangement.title, systemImage: arrangement.symbol) {
                        canvas.arrange(arrangement, selection: canvas.selectedFloatingTabs)
                    }
                }
            } label: {
                Label("Arrange", systemImage: "square.grid.3x2")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.horizontal, Layout.buttonPadding)
            Menu {
                ForEach(spaces) { space in
                    Button(space.name) { canvas.moveFloatingSelection(to: space) }
                }
            } label: {
                Label("Move to Space", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.horizontal, Layout.buttonPadding)
            .disabled(spaces.isEmpty)
            button("Close \(count)", systemImage: "xmark") { canvas.closeFloatingSelection() }
        }
        .labelStyle(.titleAndIcon)
        .font(.callout)
        .frame(height: Layout.buttonHeight)
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
        .glassEffect(.regular, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: Layout.shadowRadius, y: Layout.shadowY)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(count) selected tabs")
    }

    /// Group, the selection's primary option: filled with the accent once two or more cards are selected.
    private func groupButton(isPrimary: Bool) -> some View {
        Button { canvas.groupFloatingSelection() } label: {
            Label("Group", systemImage: "rectangle.3.group")
                .fontWeight(isPrimary ? .semibold : nil)
                .foregroundStyle(isPrimary ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .padding(.horizontal, Layout.buttonPadding)
                .frame(height: Layout.buttonHeight)
                .background(isPrimary ? Color.appAccentColor : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isPrimary)
        .help("Group the selected tabs")
    }

    private func button(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .padding(.horizontal, Layout.buttonPadding)
                .frame(height: Layout.buttonHeight)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Carries a grouped card into its group's header as the group folds, and back out as it
/// unfolds.
struct FoldTravel: ViewModifier {
    let offset: CGSize
    let isFolded: Bool

    func body(content: Content) -> some View {
        content
            .scaleEffect(isFolded ? 0.4 : 1, anchor: .topLeading)
            .offset(isFolded ? offset : .zero)
            .opacity(isFolded ? 0 : 1)
    }
}

extension AnyTransition {
    /// A card's fold into the header at `offset` from it; a fade alone under Reduce Motion.
    static func fold(toward offset: CGSize?) -> AnyTransition {
        guard let offset, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return .opacity }
        return .modifier(active: FoldTravel(offset: offset, isFolded: true), identity: FoldTravel(offset: offset, isFolded: false))
    }
}
