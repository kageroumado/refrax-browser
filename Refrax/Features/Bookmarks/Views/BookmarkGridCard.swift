import SwiftUI

/// Grid card with loading indicator, selection state, and drag support
struct BookmarkGridCard: View {
    let bookmark: Bookmark
    let isLoadingFavicon: Bool
    let isSelected: Bool
    let selectedBookmarkIDs: Set<Bookmark.ID>
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    // Compute drag item - if this bookmark is selected, include all selected, otherwise just this one
    private var dragItem: BookmarkDragItem {
        if isSelected, !selectedBookmarkIDs.isEmpty {
            // Drag all selected items
            BookmarkDragItem(
                bookmarkIDs: Array(selectedBookmarkIDs),
                primaryURL: bookmark.url,
                primaryTitle: bookmark.title,
            )
        } else {
            // Drag just this bookmark
            BookmarkDragItem(
                bookmarkIDs: [bookmark.id],
                primaryURL: bookmark.url,
                primaryTitle: bookmark.title,
            )
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            ViewThatFits {
                // Full layout: Icon + Title + Domain
                fullCardLayout
                
                // Medium layout: Icon + Title
                mediumCardLayout
                
                // Minimal layout: Icon only
                minimalCardLayout
            }
            .padding(10)
            .background(Material.regular)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) {
                // Status indicators as overlay (doesn't shift content)
                HStack(spacing: 2) {
                    if bookmark.isOfflineAvailable {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.green)
                            .help("Available Offline")
                    } else if bookmark.isDownloadingOffline {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 14, height: 14)
                    }

                    if bookmark.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(6)
            }
            .overlay(alignment: .topLeading) {
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.selection)
                        .padding(6)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? Color.appAccentColor : Color.primary.opacity(isHovered ? 0.2 : 0.1),
                        lineWidth: isSelected ? 2 : 1,
                    )
            }
            .shadow(color: Color.black.opacity(isHovered ? 0.1 : 0.05), radius: isHovered ? 6 : 3, y: 2)
        }
        .buttonStyle(.plain)
        .draggable(dragItem)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .frame(height: 120)
    }
    
    private var fullCardLayout: some View {
        VStack(alignment: .center, spacing: 8) {
            faviconView
            
            VStack(alignment: .center, spacing: 2) {
                Text(bookmark.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
                
                Text(bookmark.domain)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    private var mediumCardLayout: some View {
        VStack(alignment: .center, spacing: 6) {
            faviconView
            
            Text(bookmark.title)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private var minimalCardLayout: some View {
        VStack(alignment: .center, spacing: 6) {
            faviconView
        }
        .frame(maxWidth: .infinity)
    }
    
    @ViewBuilder
    private var faviconView: some View {
        if isLoadingFavicon {
            ProgressView()
                .scaleEffect(0.8)
                .frame(width: 48, height: 48)
        } else if let customIcon = bookmark.customIcon {
            customIcon.view(size: 48)
        } else {
            FaviconView(data: bookmark.faviconData, url: bookmark.url, size: 48)
        }
    }
}
