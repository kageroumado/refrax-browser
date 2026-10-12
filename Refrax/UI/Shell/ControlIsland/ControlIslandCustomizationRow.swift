import SwiftUI

struct ControlIslandCustomizationRow: View {
    @Binding var preference: ControlIslandItemPreference
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $preference.isVisible) {
                HStack(spacing: 12) {
                    Image(systemName: preference.item.symbol)
                        .font(.body.weight(.semibold))
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(preference.item.title)
                        Text(preference.item.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .toggleStyle(.checkbox)
            .accessibilityLabel("Show \(preference.item.title)")
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .help("Drag to reorder")
                .accessibilityHidden(true)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Move Up", systemImage: "arrow.up", action: moveUp).disabled(!canMoveUp)
            Button("Move Down", systemImage: "arrow.down", action: moveDown).disabled(!canMoveDown)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Move up", moveUp)
        .accessibilityAction(named: "Move down", moveDown)
    }
}
