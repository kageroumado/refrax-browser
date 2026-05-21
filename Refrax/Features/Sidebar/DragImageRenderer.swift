import AppKit
import SwiftUI

/// Renders SwiftUI drag overlays as NSImage for AppKit drag sessions.
///
/// When transitioning from SwiftUI to AppKit drag, this class captures
/// the current overlay appearance as a bitmap image. The image is used
/// as the drag image in the `NSDraggingSession`.
///
/// ## Caching Strategy
///
/// The rendered image is cached to avoid re-rendering on every handoff
/// attempt. The cache is invalidated when the overlay content changes
/// (e.g., different tab being dragged).
///
/// ## Thread Safety
///
/// All rendering happens on the main thread (required for SwiftUI).

enum DragImageRenderer {
    /// Render a tab row overlay as an NSImage.
    ///
    /// Creates an image matching the MorphingDragOverlay tab appearance.
    ///
    /// - Parameters:
    ///   - tab: Tab to render
    ///   - size: Target size for the image
    /// - Returns: Rendered image, or nil if rendering fails
    static func renderTabOverlay(tab: Tab, size: CGSize) -> NSImage? {
        let view = TabDragImageView(tab: tab)
            .frame(width: size.width, height: size.height)

        return renderSwiftUIView(view, size: size)
    }

    /// Render a favorite tile overlay as an NSImage.
    ///
    /// Creates an image matching the MorphingDragOverlay tile appearance.
    ///
    /// - Parameters:
    ///   - favorite: Favorite item to render
    ///   - size: Target size for the image
    /// - Returns: Rendered image, or nil if rendering fails
    static func renderTileOverlay(favorite: FavoriteItem, size: CGSize) -> NSImage? {
        let view = FavoriteDragImageView(favorite: favorite)
            .frame(width: size.width, height: size.height)

        return renderSwiftUIView(view, size: size)
    }

    /// Render a multi-selection stack overlay as an NSImage.
    ///
    /// Creates a stacked card visualization with count badge.
    ///
    /// - Parameters:
    ///   - items: All items being dragged
    ///   - primaryItem: The primary (front) item
    ///   - size: Base size for the primary card
    /// - Returns: Rendered image, or nil if rendering fails
    static func renderMultiDragOverlay(
        items: [Sidebar.DragCoordinator.DraggedItem],
        primaryItem: Sidebar.DragCoordinator.DraggedItem,
        size: CGSize,
    ) -> NSImage? {
        let view = MultiDragImageView(items: items, primaryItem: primaryItem, baseSize: size)

        // Account for stacked offset in total size
        let stackOffset: CGFloat = 4
        let stackCount = min(items.count, 3)
        let totalWidth = size.width + CGFloat(stackCount - 1) * stackOffset
        let totalHeight = size.height + CGFloat(stackCount - 1) * stackOffset

        return renderSwiftUIView(view, size: CGSize(width: totalWidth, height: totalHeight))
    }

    /// Render the current drag overlay based on coordinator state.
    ///
    /// Convenience method that selects the appropriate render method
    /// based on the current overlay mode and dragged items.
    ///
    /// - Parameter coordinator: The drag coordinator with current state
    /// - Returns: Rendered image, or nil if not dragging or rendering fails
    static func renderCurrentOverlay(
        from coordinator: Sidebar.DragCoordinator,
    ) -> NSImage? {
        guard !coordinator.draggedItems.isEmpty,
              let primaryItem = coordinator.primaryDraggedItem else {
            return nil
        }

        let size = coordinator.overlayTargetSize

        // Multi-drag: render stacked overlay
        if coordinator.draggedItems.count > 1 {
            return renderMultiDragOverlay(
                items: coordinator.draggedItems,
                primaryItem: primaryItem,
                size: size,
            )
        }

        // Single drag: render based on item type and mode
        switch coordinator.currentOverlayMode {
        case .tabRow:
            if let tab = primaryItem.tab {
                return renderTabOverlay(tab: tab, size: size)
            } else if let favorite = primaryItem.favorite {
                // Favorite being dragged in tab mode (converting to tab)
                return renderFavoriteAsTabOverlay(favorite: favorite, size: size)
            }

        case let .tile(tileSize):
            if let favorite = primaryItem.favorite {
                return renderTileOverlay(favorite: favorite, size: tileSize)
            } else if let tab = primaryItem.tab {
                // Tab being dragged in tile mode (converting to favorite)
                return renderTabAsTileOverlay(tab: tab, size: tileSize)
            }
        }

        return nil
    }

    // MARK: - Private Helpers

    private static func renderSwiftUIView(_ view: some View, size: CGSize) -> NSImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2.0

        guard let cgImage = renderer.cgImage else { return nil }

        return NSImage(cgImage: cgImage, size: size)
    }

    private static func renderFavoriteAsTabOverlay(
        favorite: FavoriteItem,
        size: CGSize,
    ) -> NSImage? {
        let view = FavoriteAsTabDragImageView(favorite: favorite)
            .frame(width: size.width, height: size.height)

        return renderSwiftUIView(view, size: size)
    }

    private static func renderTabAsTileOverlay(
        tab: Tab,
        size: CGSize,
    ) -> NSImage? {
        let view = TabAsTileDragImageView(tab: tab)
            .frame(width: size.width, height: size.height)

        return renderSwiftUIView(view, size: size)
    }
}

// MARK: - Drag Image Views

/// Simple tab row for drag image rendering.
private struct TabDragImageView: View {
    let tab: Tab

    var body: some View {
        HStack(spacing: 8) {
            // Favicon placeholder
            if let faviconData = tab.activePage.faviconData,
               let image = NSImage(data: faviconData) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            Text(tab.displayTitle)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}

/// Simple tile for drag image rendering.
private struct FavoriteDragImageView: View {
    let favorite: FavoriteItem

    var body: some View {
        VStack(spacing: 4) {
            // Favicon
            if let faviconData = favorite.faviconData,
               let image = NSImage(data: faviconData) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
            }

            Text(favorite.displayName)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.tail)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}

/// Favorite rendered as tab row (for tab conversion preview).
private struct FavoriteAsTabDragImageView: View {
    let favorite: FavoriteItem

    var body: some View {
        HStack(spacing: 8) {
            if let faviconData = favorite.faviconData,
               let image = NSImage(data: faviconData) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            Text(favorite.displayName)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}

/// Tab rendered as tile (for favorite conversion preview).
private struct TabAsTileDragImageView: View {
    let tab: Tab

    var body: some View {
        VStack(spacing: 4) {
            if let faviconData = tab.activePage.faviconData,
               let image = NSImage(data: faviconData) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
            }

            Text(tab.displayTitle)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.tail)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
    }
}

/// Multi-item stacked drag image.
private struct MultiDragImageView: View {
    let items: [Sidebar.DragCoordinator.DraggedItem]
    let primaryItem: Sidebar.DragCoordinator.DraggedItem
    let baseSize: CGSize

    private let stackOffset: CGFloat = 4
    private var visibleCount: Int { min(items.count, 3) }

    var body: some View {
        ZStack {
            // Background cards (stacked effect)
            ForEach(0 ..< visibleCount - 1, id: \.self) { index in
                let reverseIndex = visibleCount - 1 - index
                RoundedRectangle(cornerRadius: 8)
                    .fill(.regularMaterial)
                    .frame(width: baseSize.width, height: baseSize.height)
                    .shadow(color: .black.opacity(0.1), radius: 2, y: 1)
                    .offset(
                        x: CGFloat(reverseIndex) * stackOffset,
                        y: -CGFloat(reverseIndex) * stackOffset,
                    )
            }

            // Front card with content
            frontCard
                .frame(width: baseSize.width, height: baseSize.height)

            // Count badge
            if items.count > 1 {
                Text("\(items.count)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.appAccentColor)
                    .clipShape(Capsule())
                    .offset(x: baseSize.width / 2 - 8, y: baseSize.height / 2 - 8)
            }
        }
    }

    @ViewBuilder
    private var frontCard: some View {
        if let tab = primaryItem.tab {
            TabDragImageView(tab: tab)
        } else if let favorite = primaryItem.favorite {
            FavoriteDragImageView(favorite: favorite)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.regularMaterial)
        }
    }
}
