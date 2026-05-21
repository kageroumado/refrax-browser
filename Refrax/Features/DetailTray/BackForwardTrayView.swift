import SwiftUI

// MARK: - Back/Forward Tray View

/// Navigation history panel for the detail tray.
///
/// Displays the back and forward lists for the currently active page,
/// allowing quick navigation to any previously visited page.
struct BackForwardTrayView: View {
    @Environment(WindowState.self) private var windowState

    private var webPage: WebPage? {
        windowState.focusedWebPage
    }

    private var backList: [WebPage.BackForwardList.Item] {
        webPage?.backList.reversed() ?? []
    }

    private var forwardList: [WebPage.BackForwardList.Item] {
        webPage?.forwardList ?? []
    }

    private var currentItem: WebPage.BackForwardList.Item? {
        webPage?.backForwardList.currentItem
    }

    private var isEmpty: Bool {
        backList.isEmpty && forwardList.isEmpty
    }

    var body: some View {
        Group {
            if isEmpty {
                emptyState
            } else {
                navigationList
            }
        }
        .safeAreaBar(edge: .top) { header }
    }

    // MARK: - Header

    private var header: some View {
        DetailTrayHeader(
            title: "Navigation",
            currentMode: .backForward,
            onClose: {
                windowState.hideDetailTray()
            },
        )
    }

    // MARK: - Empty State

    private var emptyState: some View {
        DetailTrayEmptyState(
            icon: "arrow.left.arrow.right",
            title: "No History",
            message: "Navigate to pages to build your history",
        )
    }

    // MARK: - Navigation List

    private var navigationList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                // Back section (most recent first)
                if !backList.isEmpty {
                    Section {
                        ForEach(backList) { item in
                            NavigationItemRow(
                                item: item,
                                isCurrent: false,
                                onNavigate: { navigateTo(item) },
                            )
                        }
                    } header: {
                        sectionHeader("Back")
                    }
                }

                // Current page section
                if let current = currentItem {
                    Section {
                        NavigationItemRow(
                            item: current,
                            isCurrent: true,
                            onNavigate: nil,
                        )
                    } header: {
                        sectionHeader("Current")
                    }
                }

                // Forward section
                if !forwardList.isEmpty {
                    Section {
                        ForEach(forwardList) { item in
                            NavigationItemRow(
                                item: item,
                                isCurrent: false,
                                onNavigate: { navigateTo(item) },
                            )
                        }
                    } header: {
                        sectionHeader("Forward")
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            Spacer()
        }
    }

    private func navigateTo(_ item: WebPage.BackForwardList.Item) {
        webPage?.loadBackForwardItem(item)
        windowState.hideDetailTray()
    }
}

// MARK: - Navigation Item Row

private struct NavigationItemRow: View {
    let item: WebPage.BackForwardList.Item
    let isCurrent: Bool
    let onNavigate: (() -> Void)?

    @State private var isHovered = false

    private enum Constants {
        static let iconSize: CGFloat = 28
        static let rowVerticalPadding: CGFloat = 10
        static let rowHorizontalPadding: CGFloat = 12
    }

    var body: some View {
        Button {
            onNavigate?()
        } label: {
            HStack(spacing: 12) {
                // Favicon
                FaviconView(url: item.url, size: Constants.iconSize)

                // Title and URL
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title ?? "Untitled")
                        .font(.system(size: 13))
                        .fontWeight(isCurrent ? .semibold : .regular)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(item.url.host ?? item.url.absoluteString)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                // Current indicator
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.green)
                }
            }
            .padding(.horizontal, Constants.rowHorizontalPadding)
            .padding(.vertical, Constants.rowVerticalPadding)
            .background {
                if isHovered, !isCurrent {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isCurrent)
        .onHover { isHovered = $0 }
    }
}
