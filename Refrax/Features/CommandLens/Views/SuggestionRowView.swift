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
            manager.choose(suggestion)
            let modifiers = NSEvent.modifierFlags
            manager.commitSelection(commandKeyHeld: modifiers.contains(.command), optionKeyHeld: modifiers.contains(.option))
        } label: {
            SuggestionContentView(suggestion: suggestion, selection: selection)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .contextMenu {
            if case .openTab = suggestion.type {
                Button("Show Its Place", systemImage: "scope") { manager.showPlace(of: suggestion) }
            }
            if suggestion.url != nil {
                Button(PageVisitState.lookActionTitle, systemImage: "eye") { manager.look(at: suggestion) }
            } else if case .openTab = suggestion.type {
                Button(PageVisitState.lookActionTitle, systemImage: "eye") { manager.look(at: suggestion) }
            }
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
