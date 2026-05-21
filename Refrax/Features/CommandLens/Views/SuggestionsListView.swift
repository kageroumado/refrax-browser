import SwiftUI

struct SuggestionsListView: View {
    @Environment(CommandLensManager.self) private var manager
    @Environment(\.commandLensIsSmall) private var isSmall

    private enum Layout {
        static let maxHeight: CGFloat = 500
        static let maxHeightSmall: CGFloat = 360
    }

    var body: some View {
        let suggestions = manager.suggestions
        let selection = manager.selection

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    if shouldShowHeader(for: index, in: suggestions) {
                        SuggestionHeaderView(title: suggestion.groupHeader!)
                    }
                    SuggestionRowView(
                        suggestion: suggestion,
                        selection: selection.index == index ? selection : nil,
                    )
                }
            }
            .padding(.vertical, isSmall ? 2 : 4)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: isSmall ? Layout.maxHeightSmall : Layout.maxHeight)
    }

    /// Only show headers for "Search Suggestions" section.
    /// All other suggestions appear in a flat list without section headers.
    private func shouldShowHeader(for index: Int, in suggestions: [CommandLensSuggestion]) -> Bool {
        guard let header = suggestions[index].groupHeader else { return false }
        // Only show header for Search Suggestions
        guard header == "Search Suggestions" else { return false }
        return index == 0 || suggestions[index - 1].groupHeader != header
    }
}
