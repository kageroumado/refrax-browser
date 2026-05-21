import SwiftUI

/// Observable model for pane drag offset
///
/// Separated from the main view state to allow efficient updates during drag operations
/// without triggering unnecessary view recomputations.
@Observable
final class DragModel {
    var draggedPaneOffset: CGSize = .zero
}

/// Divider orientation for split view layouts
enum DividerType {
    case vertical
    case horizontal
}

/// Efficient identifier for size-based task triggers
///
/// Prevents unnecessary task invocations from floating-point precision noise
/// by rounding size values to nearest point. This is critical for performance
/// during window resizing where CGFloat values can change by tiny amounts.
struct SizeIdentifier: Equatable {
    let width: Int
    let height: Int

    init(_ size: CGSize) {
        self.width = Int(size.width.rounded())
        self.height = Int(size.height.rounded())
    }
}

/// Glass-styled button used in layout mode for pane controls
///
/// Features a semi-transparent background with hover effect using the Liquid Glass style.
struct GlassButton: View {
    let systemName: String
    let size: CGFloat
    let fontSize: CGFloat
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: fontSize))
                .frame(width: size, height: size)
                .contentShape(Rectangle())
                .glassEffect(.regular.tint(isHovered ? .primary.opacity(0.1) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
