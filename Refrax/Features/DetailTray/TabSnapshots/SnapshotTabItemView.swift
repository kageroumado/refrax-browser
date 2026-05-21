import AppKit
import SwiftUI

// MARK: - Snapshot Tab Item View

/// A row displaying a single tab from a snapshot.
///
/// Shows:
/// - Favicon (from stored data or domain-based fallback)
/// - Page title
/// - Domain as secondary text
///
/// Interactions:
/// - Click: Navigate current tab to URL
/// - Cmd+Click: Open in new background tab
/// - Right-click: Context menu
struct SnapshotTabItemView: View {
    let item: TabSnapshotItem
    let onClick: () -> Void
    let onCmdClick: () -> Void

    @State private var isHovered = false

    private enum Constants {
        static let iconSize: CGFloat = 24
        static let verticalPadding: CGFloat = 8
        static let horizontalPadding: CGFloat = 12
    }

    var body: some View {
        HStack(spacing: 10) {
            // Favicon
            faviconView

            // Title and domain
            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Text(domain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.vertical, Constants.verticalPadding)
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) {
                onCmdClick()
            } else {
                onClick()
            }
        }
        .contextMenu {
            contextMenu
        }
    }

    // MARK: - Favicon View

    @ViewBuilder
    private var faviconView: some View {
        if let faviconData = item.faviconData,
           let nsImage = NSImage(data: faviconData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: Constants.iconSize, height: Constants.iconSize)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            // Fallback: domain-based icon
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(domainColor.opacity(0.15))

                Text(String(domain.prefix(1)).uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(domainColor)
            }
            .frame(width: Constants.iconSize, height: Constants.iconSize)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var contextMenu: some View {
        Button("Open") {
            onClick()
        }

        Button("Open in New Tab") {
            onCmdClick()
        }

        Divider()

        Button("Copy URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.url.absoluteString, forType: .string)
        }
    }

    // MARK: - Computed Properties

    private var displayTitle: String {
        if let customName = item.customName, !customName.isEmpty {
            return customName
        }
        if let title = item.title, !title.isEmpty {
            return title
        }
        return domain
    }

    private var domain: String {
        item.url.host ?? item.url.absoluteString
    }

    private var domainColor: Color {
        let hash = domain.hashValue
        let colors: [Color] = [.blue, .purple, .pink, .red, .orange, .yellow, .green, .teal, .cyan, .indigo]
        return colors[abs(hash) % colors.count]
    }
}
