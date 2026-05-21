import SwiftUI

struct SuggestionActionView: View {
    @Environment(BrowserSettings.self) private var settings
    let suggestion: CommandLensSuggestion
    let selection: CommandLensSelection?

    var body: some View {
        HStack(spacing: 8) {
            if case .openTab = suggestion.type {
                Text("Switch to tab")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.pillBackground), in: Capsule())
            } else if case .referenceTab = suggestion.type {
                Text("Open in pane")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color(.pillBackground), in: Capsule())
            } else if case .searchProvider = suggestion.type {
                let isSelected = selection?.buttonSelection == .switchProvider
                HStack(spacing: 4) {
                    Image(systemName: "arrow.right")
                        .font(.caption)
                    Text("tab")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color(.pillBackground), in: RoundedRectangle(cornerRadius: 6))
                }
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isSelected ? Color.white : Color(.pillBackground),
                    in: Capsule(),
                )
            } else if case let .setting(key, _) = suggestion.type {
                SettingToggleIndicator(settingKey: key, settings: settings)
            } else {
                SuggestionActionButtonsView(suggestion: suggestion, selection: selection)
            }
        }
    }
}

// MARK: - Setting Toggle Indicator

private struct SettingToggleIndicator: View {
    let settingKey: String
    let settings: BrowserSettings

    var body: some View {
        if let key = BrowserSettingKey(rawValue: settingKey) {
            switch key.metadata.valueKind {
            case .toggle:
                Toggle("", isOn: toggleBinding(for: key))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
            case .picker:
                Text(key.displayValue(in: settings))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.pillBackground), in: Capsule())
            case .navigateOnly:
                EmptyView()
            }
        }
    }

    private func toggleBinding(for key: BrowserSettingKey) -> Binding<Bool> {
        Binding(
            get: {
                if case let .bool(value) = key.currentValue(in: settings) {
                    return value
                }
                return false
            },
            set: { _ in key.toggle(in: settings) },
        )
    }
}
