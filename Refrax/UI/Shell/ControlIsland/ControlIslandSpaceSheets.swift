import SwiftUI

/// A space sheet or confirmation the control island shows: New Space, Edit, and the
/// confirmation before a space is deleted, or the last space cleared.
enum ControlIslandSpaceRequest: Identifiable {
    case create
    case edit(Space)
    case remove(Space)

    var id: String {
        switch self {
        case .create: "create"
        case let .edit(space): "edit.\(space.id)"
        case let .remove(space): "remove.\(space.id)"
        }
    }
}

extension View {
    /// Presents the island's ``ControlIslandState/spaceRequest`` and keeps the island awake
    /// while it is up.
    func controlIslandSpaceSheets() -> some View {
        modifier(ControlIslandSpaceSheets())
    }
}

private struct ControlIslandSpaceSheets: ViewModifier {
    @Environment(WindowState.self) private var windowState
    @Environment(TabManager.self) private var tabs
    @Environment(SpaceManager.self) private var spaces

    private var state: ControlIslandState {
        windowState.controlIsland
    }

    /// New Space and Edit, as sheets.
    private var sheet: Binding<ControlIslandSpaceRequest?> {
        Binding {
            switch state.spaceRequest {
            case .create, .edit: state.spaceRequest
            case .remove, nil: nil
            }
        } set: { state.spaceRequest = $0 }
    }

    /// The space waiting for its delete or clear confirmation.
    private var spaceToRemove: Space? {
        if case let .remove(space) = state.spaceRequest {
            return space
        }
        return nil
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: sheet) { request in
                switch request {
                case .create: CreateSpaceSheet()
                case let .edit(space): EditSpaceSheet(space: space)
                case .remove: EmptyView()
                }
            }
            .alert(
                tabs.hasMultipleSpaces ? "Delete \(spaceToRemove?.name ?? "Space")?" : "Clear \(spaceToRemove?.name ?? "Space")?",
                isPresented: Binding { spaceToRemove != nil } set: {
                    if !$0 {
                        state.spaceRequest = nil
                    }
                },
                presenting: spaceToRemove,
            ) { space in
                if tabs.hasMultipleSpaces {
                    Button("Delete", role: .destructive) { spaces.deleteSpace(space, windowState: windowState) }
                } else {
                    Button("Clear All Tabs", role: .destructive) { tabs.clearSpace(space) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { space in
                if tabs.hasMultipleSpaces {
                    Text("Its \(tabs.state.tabs(in: space).count) tabs close with it.")
                } else {
                    Text("This is the last space: its tabs close, and it returns to its default name and icon.")
                }
            }
            .onChange(of: state.spaceRequest != nil) { _, presented in
                state.isPresenting = presented
            }
    }
}
