import SwiftUI

struct SearchEngineBadge: View {
    let engine: SearchEngine
    @Environment(\.commandLensIsSmall) private var isSmall

    private enum Layout {
        static let iconSize: CGFloat = 12
        static let fontSize: CGFloat = 11
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: engine.iconName)
                .font(.system(size: Layout.iconSize, weight: .medium))
            Text(engine.name)
                .font(.system(size: Layout.fontSize, weight: .medium))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
    }
}
