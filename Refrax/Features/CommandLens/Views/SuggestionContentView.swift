import SwiftUI

struct SuggestionContentView: View {
    let suggestion: CommandLensSuggestion
    let selection: CommandLensSelection?
    @Environment(\.commandLensIsSmall) private var isSmall

    var body: some View {
        HStack(spacing: 12) {
            SuggestionIconView(suggestion: suggestion)

            // Text Content
            VStack(alignment: .leading, spacing: 1) {
                Text(suggestion.text)
                    .font(isSmall ? .body : .system(size: 15, weight: .regular))
                    .lineLimit(1)

                if !suggestion.description.isEmpty {
                    Text(suggestion.description)
                        .font(isSmall ? .caption : .subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Action indicators
            SuggestionActionView(suggestion: suggestion, selection: selection)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, isSmall ? 4 : 6)
    }
}
