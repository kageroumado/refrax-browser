import SwiftUI

/// Stages visibility and order changes until the user chooses Done.
struct ControlIslandCustomizationSheet: View {
    let configuration: ControlIslandConfiguration
    @Environment(\.dismiss) private var dismiss
    @State private var items: [ControlIslandItemPreference]
    @State private var optionDragTarget: ControlIslandDragTarget
    @State private var avoidsPageControls: Bool

    private enum Layout {
        static let width: CGFloat = 480
        static let height: CGFloat = 610
        static let padding: CGFloat = 20
    }

    init(configuration: ControlIslandConfiguration) {
        self.configuration = configuration
        _items = State(initialValue: configuration.items)
        _optionDragTarget = State(initialValue: configuration.optionDragTarget)
        _avoidsPageControls = State(initialValue: configuration.avoidsPageControls)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Customize Controls")
                    .font(.title2.weight(.semibold))
                Text("Choose what appears. Drag rows to change their order.")
                    .foregroundStyle(.secondary)
            }
            .padding(Layout.padding)

            List {
                ForEach($items) { $preference in
                    ControlIslandCustomizationRow(
                        preference: $preference,
                        canMoveUp: preference.id != items.first?.id,
                        canMoveDown: preference.id != items.last?.id,
                        moveUp: { move(preference.id, by: -1) },
                        moveDown: { move(preference.id, by: 1) },
                    )
                }
                .onMove { source, destination in
                    items.move(fromOffsets: source, toOffset: destination)
                }
            }
            .listStyle(.inset)

            VStack(alignment: .leading, spacing: 16) {
                Toggle("Move aside when covering a page control", isOn: $avoidsPageControls)
                    .help("Makes a small adjustment after a page loads, while the pointer is away")
                Picker("Option-drag moves", selection: $optionDragTarget) {
                    ForEach(ControlIslandDragTarget.allCases, id: \.self) { target in
                        Text(target.title).tag(target)
                    }
                }
                Text(optionDragTarget.help)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Restore Defaults") {
                        items = ControlIslandConfiguration.defaultItems
                        optionDragTarget = .panel
                        avoidsPageControls = true
                    }
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Done") {
                        configuration.apply(items, optionDragTarget: optionDragTarget, avoidsPageControls: avoidsPageControls)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(Layout.padding)
        }
        .frame(width: Layout.width, height: Layout.height)
        .font(.body)
        .foregroundStyle(.primary)
        .buttonStyle(.automatic)
    }

    private func move(_ id: ControlIslandItem, by offset: Int) {
        guard let source = items.firstIndex(where: { $0.id == id }),
              items.indices.contains(source + offset) else { return }
        items.move(fromOffsets: IndexSet(integer: source), toOffset: source + offset + (offset > 0 ? 1 : 0))
    }
}
