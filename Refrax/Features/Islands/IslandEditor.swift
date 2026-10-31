import SwiftUI

/// A group island's name, icon, and color, edited together in the popover its header opens;
/// each choice reaches the island as it is made.
struct IslandEditor: View {
    let islandID: UUID

    @Environment(IslandController.self) private var islands

    var body: some View {
        if let appearance = islands.appearance(of: islandID) {
            GroupSettingsPopover(
                name: binding(appearance, \.name),
                selectedIcon: binding(appearance, \.iconName),
                selectedColorHex: binding(appearance, \.colorString),
            )
        }
    }

    private func binding<Value>(_ appearance: IslandAppearance, _ keyPath: WritableKeyPath<IslandAppearance, Value>) -> Binding<Value> {
        Binding {
            appearance[keyPath: keyPath]
        } set: { value in
            var edit = islands.appearance(of: islandID) ?? appearance
            edit[keyPath: keyPath] = value
            islands.setAppearance(edit, of: islandID)
        }
    }
}
