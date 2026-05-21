import SwiftUI

/// A compact popover for renaming a space inline.
///
/// Provides a text field for quick renaming without opening the full edit sheet.
struct SpaceRenamePopover: View {
    @Binding var spaceName: String
    @Binding var isPresented: Bool
    var onCommit: () -> Void

    @FocusState private var isTextFieldFocused: Bool

    private var isValid: Bool {
        !spaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: Layout.spacing) {
            Text("Rename Space")
                .font(.headline)

            TextField("Space Name", text: $spaceName)
                .textFieldStyle(.roundedBorder)
                .focused($isTextFieldFocused)
                .onSubmit {
                    if isValid {
                        onCommit()
                        isPresented = false
                    }
                }

            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Rename") {
                    onCommit()
                    isPresented = false
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(Layout.padding)
        .frame(width: Layout.popoverWidth)
        .onAppear {
            isTextFieldFocused = true
        }
    }
}

// MARK: - Layout Constants

private extension SpaceRenamePopover {
    enum Layout {
        static let padding: CGFloat = 16
        static let spacing: CGFloat = 12
        static let popoverWidth: CGFloat = 260
    }
}
