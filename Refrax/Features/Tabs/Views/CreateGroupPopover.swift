import SwiftUI

/// Popover for creating a new tab group
///
/// Allows users to configure:
/// - Group name
/// - Group color (tint)
/// - Group icon (SF Symbol)
struct CreateGroupPopover: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(TabManager.self) private var tabManager
    @Environment(TabGroupManager.self) private var groupManager

    @State private var name: String = ""
    @State private var selectedColor: GroupColor = .steel
    @State private var selectedIcon: String = "folder.fill"

    @FocusState private var isNameFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Tab Group")
                .font(.headline)

            // Name field
            TextField("Group Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFieldFocused)

            // Color picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Color")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(GroupColor.allCases, id: \.self) { color in
                        Circle()
                            .fill(color.color)
                            .frame(width: 24, height: 24)
                            .overlay {
                                if selectedColor == color {
                                    Circle()
                                        .strokeBorder(.white, lineWidth: 2)
                                }
                            }
                            .onTapGesture {
                                selectedColor = color
                            }
                    }
                }
            }

            // Icon picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Icon")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(GroupIcon.allCases, id: \.self) { icon in
                        Image(systemName: icon.rawValue)
                            .font(.system(size: 16))
                            .foregroundColor(selectedColor.color)
                            .frame(width: 24, height: 24)
                            .background {
                                if selectedIcon == icon.rawValue {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.appAccentColor.opacity(0.2))
                                }
                            }
                            .onTapGesture {
                                selectedIcon = icon.rawValue
                            }
                    }
                }
            }

            // Actions
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("Create") {
                    createGroup()
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300)
        .onAppear {
            isNameFieldFocused = true
        }
    }

    private func createGroup() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        // TODO: add a visual indicator if failed
        _ = try? groupManager.createGroup(
            name: trimmedName,
            color: selectedColor.rawValue,
            iconName: selectedIcon,
        )

        dismiss()
    }
}
