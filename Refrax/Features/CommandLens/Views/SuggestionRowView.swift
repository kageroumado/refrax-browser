import AppKit
import SwiftUI

struct SuggestionRowView: View {
    @Environment(CommandLensManager.self) private var manager
    @Environment(\.commandLensIsSmall) private var isSmall
    let suggestion: CommandLensSuggestion
    let selection: CommandLensSelection?

    private enum Layout {
        static let horizontalInset: CGFloat = 8
        static let verticalSpacing: CGFloat = 1
        // Concentric with outer corner radius 26, inset 8 → inner 18
        static let cornerRadius: CGFloat = 18
        static let cornerRadiusSmall: CGFloat = 10
    }

    private var isHighlighted: Bool {
        (selection != nil) || (manager.hoveredSuggestionID == suggestion.id)
    }

    var body: some View {
        Button {
            if let index = manager.suggestions.firstIndex(where: { $0.id == suggestion.id }) {
                manager.selection = CommandLensSelection(index: index)
                let modifiers = NSEvent.modifierFlags
                let commandKeyHeld = modifiers.contains(.command)
                let optionKeyHeld = modifiers.contains(.option)
                manager.commitSelection(commandKeyHeld: commandKeyHeld, optionKeyHeld: optionKeyHeld)
            }
        } label: {
            SuggestionContentView(suggestion: suggestion, selection: selection)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .background(
            isHighlighted ? selectionBackground : Color.clear,
            in: RoundedRectangle(cornerRadius: isSmall ? Layout.cornerRadiusSmall : Layout.cornerRadius),
        )
        .padding(.horizontal, Layout.horizontalInset)
        .padding(.vertical, Layout.verticalSpacing)
        .contentShape(Rectangle())
        .help(tooltipText)
        .onHover { hovering in
            if hovering {
                manager.hoveredSuggestionID = suggestion.id
            } else if manager.hoveredSuggestionID == suggestion.id {
                manager.hoveredSuggestionID = nil
            }
        }
    }

    /// Selection background with saturated accent color for glass effect.
    private var selectionBackground: Color {
        // Use a more saturated, less transparent accent color for better visibility on glass
        Color.appAccentColor.opacity(0.3)
    }

    /// Tooltip text for the suggestion, if applicable.
    private var tooltipText: String {
        if case let .download(_, state) = suggestion.type {
            return state == .completed ? "Open in Finder" : "Show in Downloads"
        }
        return ""
    }
}
