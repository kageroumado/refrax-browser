import SwiftUI

struct ChatMessageView: View {
    let message: ChatMessage
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            Circle()
                .fill(message.role == .user ? Color.appAccentColor : Color.purple)
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: message.role == .user ? "person.fill" : "sparkles")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                }
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                Text(message.role == .user ? "You" : "AI")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                
                Text(message.content)
                    .font(.body)
                    .textSelection(.enabled)
                
                // Actions (on hover)
                if isHovered, message.role == .assistant {
                    HStack(spacing: 12) {
                        Button(action: {}) {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {}) {
                            Label("Regenerate", systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(
            message.role == .assistant
                ? Color.purple.opacity(0.05)
                : Color.clear,
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
