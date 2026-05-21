import SwiftUI

struct SuggestionIconView: View {
    let suggestion: CommandLensSuggestion
    @Environment(\.commandLensIsSmall) private var isSmall
    
    var size: CGFloat {
        isSmall ? 22 : 28
    }
    
    var body: some View {
        switch suggestion.type {
        case let .richEntity(imageUrl):
            AsyncImage(url: imageUrl) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(systemName: suggestion.iconName)
                    .font(isSmall ? .system(size: 14, weight: .medium) : .system(size: 22, weight: .medium))
                    .frame(width: size, height: size, alignment: .center)
                    .foregroundStyle(.secondary)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
        case .askAI:
            Image(systemName: suggestion.iconName)
                .font(isSmall ? .system(size: 14, weight: .medium) : .system(size: 22, weight: .medium))
                .frame(width: size, height: size, alignment: .center)
                .foregroundStyle(.purple)

        default:
            Image(systemName: suggestion.iconName)
                .font(isSmall ? .system(size: 14, weight: .medium) : .system(size: 22, weight: .medium))
                .frame(width: size, height: size, alignment: .center)
                .foregroundStyle(.secondary)
        }
    }
}
