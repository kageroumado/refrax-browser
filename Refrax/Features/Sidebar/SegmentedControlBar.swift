import SwiftUI

/// A custom segmented control with smooth sliding animation and visual feedback.
///
/// Displays space names or icons in each segment with a blue capsule that slides to indicate
/// the current selection. Dividers appear between unselected segments for visual separation.
///
/// ## Features
/// - Smooth animated transitions between selections
/// - Material background for depth
/// - Dynamic divider visibility
/// - Accessible button areas
struct SegmentedControlBar: View {
    @Binding var selection: UUID
    let spaces: [Space]
    var cornerRadius: CGFloat = 16
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let segmentWidth = if !spaces.isEmpty {
                    geometry.size.width / CGFloat(spaces.count)
                } else {
                    geometry.size.width
                }
                let selectedIndex = spaces.firstIndex(where: { $0.id == selection }) ?? 0
                let gap: CGFloat = 2
                let highlightWidth = spaces.count > 1 ? segmentWidth - (gap * 2) : segmentWidth - (gap * 2)
                let highlightOffset = CGFloat(selectedIndex) * segmentWidth + gap
                
                // Sliding selection indicator
                Capsule()
                    .fill(Color.appAccentColor)
                    .frame(width: highlightWidth, height: geometry.size.height - (gap * 2))
                    .offset(x: highlightOffset, y: gap)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selection)
                
                // Segment buttons
                HStack(spacing: 0) {
                    ForEach(spaces) { space in
                        Button {
                            selection = space.id
                        } label: {
                            Text(space.name)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                                .foregroundStyle(selection == space.id ? .white : .primary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .frame(width: segmentWidth)
                    }
                }
                
                // Dividers (only between unselected segments)
                HStack(spacing: 0) {
                    ForEach(Array(spaces.enumerated()), id: \.element.id) { index, _ in
                        Spacer()
                        
                        if index < spaces.count - 1 {
                            let isCurrentSelected = spaces[index].id == selection
                            let isNextSelected = spaces[index + 1].id == selection
                            let shouldShowDivider = !isCurrentSelected && !isNextSelected
                            
                            Rectangle()
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: 1, height: geometry.size.height * 0.5)
                                .opacity(shouldShowDivider ? 1 : 0)
                                .animation(.easeInOut(duration: 0.2), value: selection)
                        }
                    }
                    Spacer()
                }
            }
        }
        .frame(height: 32)
        .background(Material.thin)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
