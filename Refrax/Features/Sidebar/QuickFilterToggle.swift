import SwiftUI

/// A two-segment toggle for quick filtering between All tabs and Unread tabs.
///
/// Styled consistently with `SegmentedControlBar`, this component provides a quick way
/// to filter the tab list without opening the full filter interface.
///
/// ## Features
/// - Smooth animated transitions between states
/// - Material background for depth
/// - Dynamic divider visibility
/// - Accessible button areas
///
/// ## Usage
/// ```swift
/// QuickFilterToggle(filterState: filterState)
/// ```
struct QuickFilterToggle: View {
    let filterState: TabFilterState
    var cornerRadius: CGFloat = 16
    
    /// Current selection derived from filterState.searchUnread
    private var currentSelection: FilterOption {
        switch filterState.searchUnread {
        case .none:
            .all
        case .some(true):
            .unread
        case .some(false):
            .read
        }
    }
    
    /// Available filter options
    private enum FilterOption: String, CaseIterable, Identifiable {
        case all = "All"
        case unread = "Unread"
        case read = "Read"
        
        var id: String { rawValue }
    }
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                let segmentWidth = geometry.size.width / 2
                let selectedIndex = currentSelection == .all ? 0 : 1
                let gap: CGFloat = 2
                let highlightWidth = segmentWidth - (gap * 2)
                let highlightOffset = CGFloat(selectedIndex) * segmentWidth + gap
                
                // Sliding selection indicator
                Capsule()
                    .fill(Color.appAccentColor)
                    .frame(width: highlightWidth, height: geometry.size.height - (gap * 2))
                    .offset(x: highlightOffset, y: gap)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentSelection)
                
                // Segment buttons
                HStack(spacing: 0) {
                    // All button
                    Button {
                        handleSelection(.all)
                    } label: {
                        Text("All")
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(currentSelection == .all ? .white : .primary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: segmentWidth)
                    
                    // Unread button
                    Button {
                        handleSelection(.unread)
                    } label: {
                        Text("Unread")
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(currentSelection == .unread ? .white : .primary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: segmentWidth)
                }
                
                // Divider (only visible when neither segment is in the middle)
                HStack(spacing: 0) {
                    Spacer()
                    
                    Rectangle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 1, height: geometry.size.height * 0.5)
                        .opacity(currentSelection == .all || currentSelection == .unread ? 0 : 1)
                        .animation(.easeInOut(duration: 0.2), value: currentSelection)
                    
                    Spacer()
                }
            }
        }
        .frame(height: 32)
        .background(Material.thin)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
    
    /// Handles selection changes and updates the filter state.
    private func handleSelection(_ option: FilterOption) {
        switch option {
        case .all:
            // Clear unread filter (show all tabs)
            if filterState.searchUnread != nil {
                filterState.searchUnread = nil
            }
            
        case .unread:
            // Set unread filter to true (show only unread)
            filterState.searchUnread = true
            
        case .read:
            // Set unread filter to false (show only read)
            filterState.searchUnread = false
        }
    }
}
