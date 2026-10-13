import SwiftUI

/// Stages visibility and order changes until the user chooses Done.
struct ControlIslandCustomizationSheet: View {
    let configuration: ControlIslandConfiguration
    @Environment(\.dismiss) private var dismiss
    @Environment(BrowserSettings.self) private var settings
    @State private var items: [ControlIslandItemPreference]
    @State private var avoidsPageControls: Bool
    @State private var restsWhenIdle: Bool
    @State private var tintsWithSpaceColor: Bool

    private enum Layout {
        static let width: CGFloat = 480
        static let height: CGFloat = 780
        static let padding: CGFloat = 20
    }

    init(configuration: ControlIslandConfiguration) {
        self.configuration = configuration
        _items = State(initialValue: configuration.items)
        _avoidsPageControls = State(initialValue: configuration.avoidsPageControls)
        _restsWhenIdle = State(initialValue: configuration.restsWhenIdle)
        _tintsWithSpaceColor = State(initialValue: configuration.tintsWithSpaceColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Control Island")
                    .font(.title2.weight(.semibold))
                Text("Choose what appears. Drag rows to change their order. Additional controls gather below a divider; the grip at the bottom moves the island.")
                    .fixedSize(horizontal: false, vertical: true)
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
                backgroundEditor
                Divider()
                Toggle("Rest when the pointer is away or still", isOn: $restsWhenIdle)
                    .help("The glass clears and the symbols fade; moving toward the controls brings them back")
                Toggle("Carry the window color", isOn: $tintsWithSpaceColor)
                    .help("The glass takes on the window background color: the space, website, or custom color chosen above")
                Toggle("Move aside when covering a page control", isOn: $avoidsPageControls)
                    .help("Makes a small adjustment after a page loads, while the pointer is away")
                HStack {
                    Button("Restore Defaults") {
                        items = ControlIslandConfiguration.defaultItems
                        avoidsPageControls = true
                        restsWhenIdle = true
                        tintsWithSpaceColor = true
                    }
                    Spacer()
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Done") {
                        configuration.apply(
                            items,
                            avoidsPageControls: avoidsPageControls,
                            restsWhenIdle: restsWhenIdle,
                            tintsWithSpaceColor: tintsWithSpaceColor,
                        )
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

    /// The window background behind the island: the same choices as Settings › Appearance.
    private var backgroundEditor: some View {
        @Bindable var settings = settings
        return VStack(alignment: .leading, spacing: 10) {
            SettingsColorPicker(
                label: "Window background",
                selectedColor: $settings.customWindowBackgroundColor,
                systemColor: Color(.windowBackgroundColor),
            )
            Toggle("Tint the window with the space color", isOn: $settings.enableSpaceWindowColoring)
            Toggle("Tint the window with the website color", isOn: $settings.enableWebsiteWindowColoring)
            HStack {
                Text("Blend strength")
                Spacer()
                Slider(value: $settings.windowBackgroundMixAmount, in: 0 ... 1)
                    .frame(width: 200)
                Text("\(Int(settings.windowBackgroundMixAmount * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }

    private func move(_ id: ControlIslandItem, by offset: Int) {
        guard let source = items.firstIndex(where: { $0.id == id }),
              items.indices.contains(source + offset) else { return }
        items.move(fromOffsets: IndexSet(integer: source), toOffset: source + offset + (offset > 0 ? 1 : 0))
    }
}
