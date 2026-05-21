import SwiftUI

/// Error toast notification (top-right corner - macOS standard)
struct ErrorToast: View {
    let message: String
    @Binding var isPresented: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            
            Text(message)
                .font(.callout)
            
            Button(action: { isPresented = false }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Material.thick)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 4)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring, value: isPresented)
    }
}
