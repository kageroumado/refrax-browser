import SwiftUI

struct SuggestionActionButtonsView: View {
    @Environment(CommandLensManager.self) private var manager
    let suggestion: CommandLensSuggestion
    let selection: CommandLensSelection?

    var body: some View {
        HStack(spacing: 8) {
            if let keyword = suggestion.keywordAction {
                Button {
                    manager.inputText = "\(keyword) "
                } label: {
                    SuggestionActionButton(
                        text: keyword,
                        iconName: "arrow.turn.down.left",
                        isSelected: selection?.buttonSelection == .keyword,
                    )
                }
                .buttonStyle(.plain)
            }
            if suggestion.isRemovable {
                Button {
                    manager.removeSuggestion(suggestion)
                } label: {
                    SuggestionActionButton(
                        iconName: "xmark",
                        isSelected: selection?.buttonSelection == .remove,
                        isDestructive: true,
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
