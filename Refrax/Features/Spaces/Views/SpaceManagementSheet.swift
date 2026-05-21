import SwiftUI

/// Sheet for managing spaces - edit and delete.
struct SpaceManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TabManager.self) private var tabManager: TabManager
    @Environment(SpaceManager.self) private var spaceManager
    @Environment(WindowState.self) private var windowState: WindowState
    @Environment(BrowserState.self) private var browserState: BrowserState

    @State private var spaceToEdit: Space? = nil
    @State private var spaceToDelete: Space? = nil
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            spaceList
        }
        .frame(width: Layout.sheetWidth, height: Layout.sheetHeight)
        .sheet(item: $spaceToEdit) { space in
            EditSpaceSheet(space: space)
        }
        .alert("Delete Space", isPresented: $showDeleteConfirmation, presenting: spaceToDelete) { space in
            Button("Cancel", role: .cancel) {
                spaceToDelete = nil
            }

            if tabManager.hasMultipleSpaces {
                Button("Delete", role: .destructive) {
                    spaceManager.deleteSpace(space, windowState: windowState)
                    spaceToDelete = nil
                }
            } else {
                Button("Clear All Tabs", role: .destructive) {
                    handleLastSpaceClear(space)
                    spaceToDelete = nil
                }
            }
        } message: { space in
            if tabManager.hasMultipleSpaces {
                Text("Are you sure you want to delete '\(space.name)'? This will close all \(space.tabCount) tabs in this space.")
            } else {
                Text("This is your last space. All tabs will be closed and the space will be reset to default.")
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Manage Spaces")
                .font(.title2)
                .fontWeight(.semibold)
            Spacer()
            Button("Done") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    // MARK: - Space List

    private var spaceList: some View {
        List {
            ForEach(tabManager.state.spaces) { space in
                spaceRow(for: space)
            }
        }
    }

    private func spaceRow(for space: Space) -> some View {
        HStack {
            spaceIcon(for: space)

            VStack(alignment: .leading, spacing: 4) {
                Text(space.name)
                    .font(.headline)

                HStack(spacing: 8) {
                    Text("\(space.tabCount) tabs")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if space.id == windowState.activeSpaceID {
                        Text("Active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Material.thin)
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            rowActions(for: space)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func spaceIcon(for space: Space) -> some View {
        if space.isEmoji {
            Text(space.iconName)
                .font(.title3)
        } else {
            Image(systemName: space.iconName)
                .font(.title3)
                .foregroundStyle(space.color)
        }
    }

    private func rowActions(for space: Space) -> some View {
        HStack(spacing: 8) {
            Button {
                spaceToEdit = space
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(.primary)
            }
            .buttonStyle(.borderless)

            Button {
                spaceToDelete = space
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.borderless)
            .disabled(tabManager.state.spaces.count == 1)
        }
    }

    // MARK: - Actions

    private func handleLastSpaceClear(_ space: Space) {
        let tabsToClose = browserState.tabs(in: space)
        for tab in tabsToClose {
            tabManager.closeTab(tab)
        }

        spaceManager.updateSpace(
            space,
            name: SpaceManager.DefaultSpaceConfig.name,
            iconName: SpaceManager.DefaultSpaceConfig.iconName,
            color: SpaceManager.DefaultSpaceConfig.color,
        )
    }
}

// MARK: - Layout Constants

private extension SpaceManagementSheet {
    enum Layout {
        static let sheetWidth: CGFloat = 500
        static let sheetHeight: CGFloat = 400
    }
}
