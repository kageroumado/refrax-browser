import SwiftUI

/// A vertical space selector with a recessed track and one selected segment.
struct ControlIslandSpaces: View {
    let destinations: [Space]
    var focusedControl: FocusState<String?>.Binding

    @Environment(WindowState.self) private var windowState
    @Environment(SpaceManager.self) private var spaces
    @Environment(TabSwitcherManager.self) private var tabSwitcher
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(\.appearsActive) private var appearsActive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @Namespace private var selectionAnimation
    @State private var showsSpaceManagement = false

    private enum Layout {
        static let inset = ControlIslandPlacement.horizontalInset
        static let iconSize: CGFloat = 14
        static let trackOpacity: Double = 0.10
        static let selectionOpacity: Double = 0.70
        static let shadowOpacity: Double = 0.12
        static let cornerRadius = ControlIslandPlacement.contentWidth / 2
    }

    /// One space is a place, not a choice: its icon stands alone without a track or selection.
    private var isSelector: Bool { destinations.count > 1 }

    var body: some View {
        Group {
            if destinations.count <= ControlIslandPlacement.maximumVisibleSpaces {
                spaceButtons
            } else {
                scrollableSpaces
            }
        }
        .background {
            if isSelector {
                RoundedRectangle(cornerRadius: Layout.cornerRadius)
                    .fill(Color.primary.opacity(Layout.trackOpacity).shadow(.inner(
                        color: .black.opacity(Layout.shadowOpacity), radius: 2, y: 1,
                    )))
            }
        }
        .clipShape(.rect(cornerRadius: Layout.cornerRadius))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Spaces")
        .contextMenu {
            Button("Manage Spaces…") { showsSpaceManagement = true }
        }
        .sheet(isPresented: $showsSpaceManagement) { SpaceManagementSheet() }
        .onChange(of: showsSpaceManagement) { _, presented in
            windowState.controlIsland.isPresenting = presented
        }
    }

    private var spaceButtons: some View {
        let selectedID = windowState.activeSpaceID
        return VStack(spacing: 0) {
            ForEach(destinations) { space in
                spaceButton(space, selected: space.id == selectedID)
            }
        }
    }

    private var scrollableSpaces: some View {
        ScrollViewReader { reader in
            ScrollView(.vertical) {
                spaceButtons
            }
            .scrollIndicators(.visible)
            .frame(height: CGFloat(ControlIslandPlacement.maximumVisibleSpaces) * ControlIslandPlacement.spaceRowHeight)
            .onAppear {
                if let id = windowState.activeSpaceID { reader.scrollTo(id) }
            }
            .onChange(of: windowState.activeSpaceID) { _, id in
                if let id { reader.scrollTo(id) }
            }
        }
    }

    private func iconColor(selected: Bool) -> Color {
        if appearsActive {
            return Color(nsColor: selected ? .labelColor : .secondaryLabelColor)
        }
        return Color(nsColor: selected ? .secondaryLabelColor : .tertiaryLabelColor)
    }

    private func spaceButton(_ space: Space, selected: Bool) -> some View {
        Button {
            guard !selected else { return }
            tabSwitcher.cancel()
            windowState.closeCommandLens()
            windowState.pageVisit.end()
            Task.immediate(name: "Switch control island space") {
                if canvas.floatingVisibility.isRevealed { canvas.spaceToReveal = space.id }
                await spaces.switchToSpace(space, for: windowState)
                if windowState.activeSpaceID != space.id { canvas.spaceToReveal = nil }
            }
        } label: {
            Group {
                if space.isEmoji {
                    if selected && appearsActive {
                        Text(space.iconName)
                    } else {
                        Text(space.iconName).hidden()
                            .overlay { Rectangle().fill(iconColor(selected: selected)).mask(Text(space.iconName)) }
                    }
                } else {
                    Image(systemName: space.iconName)
                        .symbolRenderingMode(.monochrome)
                }
            }
            .font(.system(size: Layout.iconSize, weight: .semibold))
            .foregroundStyle(iconColor(selected: selected))
            .frame(maxWidth: .infinity)
            .frame(height: ControlIslandPlacement.spaceRowHeight)
            .contentShape(Rectangle())
            .background {
                if selected, isSelector {
                    Circle()
                        .fill(.background.opacity(Layout.selectionOpacity))
                        .overlay {
                            if contrast == .increased {
                                Circle().strokeBorder(.primary, lineWidth: 1)
                            }
                        }
                        .padding(Layout.inset)
                        .matchedGeometryEffect(id: "selected-space", in: selectionAnimation)
                }
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: windowState.activeSpaceID)
        .focusable()
        .focused(focusedControl, equals: "space-\(space.id)")
        .focusEffectDisabled()
        .help("Switch to \(space.name)")
        .accessibilityLabel("Space: \(space.name)")
        .accessibilityValue(selected ? "Current space" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
