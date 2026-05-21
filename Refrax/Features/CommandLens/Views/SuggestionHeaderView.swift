import SwiftUI

struct SuggestionHeaderView: View {
    let title: String
    @Environment(\.commandLensIsSmall) private var isSmall

    var body: some View {
        Text(title)
            .font(isSmall ? .caption2 : .caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, isSmall ? 16 : 18)
            .padding(.top, isSmall ? 4 : 6)
            .padding(.bottom, isSmall ? 2 : 2)
    }
}
