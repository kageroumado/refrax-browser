import SwiftUI

/// A button that executes an async action and disables itself while running.
///
/// Prevents double-clicks and provides visual feedback during async operations.
/// Automatically re-enables when the action completes (success or failure).
///
/// ## Usage
/// ```swift
/// AsyncButton("Save") {
///     await saveData()
/// }
///
/// AsyncButton {
///     await deleteItem()
/// } label: {
///     Label("Delete", systemImage: "trash")
/// }
/// ```
struct AsyncButton<Label: View>: View {
    let role: ButtonRole?
    let action: @MainActor () async -> Void
    let label: Label

    @State private var isRunning = false

    init(
        role: ButtonRole? = nil,
        action: @escaping @MainActor () async -> Void,
        @ViewBuilder label: () -> Label,
    ) {
        self.role = role
        self.action = action
        self.label = label()
    }

    var body: some View {
        Button(role: role) {
            isRunning = true
            Task {
                await action()
                isRunning = false
            }
        } label: {
            label
        }
        .disabled(isRunning)
    }
}

extension AsyncButton where Label == Text {
    init(
        _ title: LocalizedStringKey,
        role: ButtonRole? = nil,
        action: @escaping @MainActor () async -> Void,
    ) {
        self.init(role: role, action: action) { Text(title) }
    }

    init(
        _ title: String,
        role: ButtonRole? = nil,
        action: @escaping @MainActor () async -> Void,
    ) {
        self.init(role: role, action: action) { Text(title) }
    }
}
