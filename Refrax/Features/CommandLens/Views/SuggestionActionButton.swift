import SwiftUI

struct SuggestionActionButton: View {
    var text: String?
    let iconName: String
    let isSelected: Bool
    var isDestructive: Bool = false
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
            if let text {
                Text(text)
            }
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(foregroundColor)
        .background(backgroundColor, in: Capsule())
        .overlay(
            isSelected ? Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1) : nil,
        )
    }
    
    private var foregroundColor: Color {
        if isSelected { return isDestructive ? .white : .primary }
        if isDestructive { return .red }
        return .secondary
    }
    
    private var backgroundColor: Color {
        if isSelected { return isDestructive ? .red : .white }
        return Color(.pillBackground)
    }
}
