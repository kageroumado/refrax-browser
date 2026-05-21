import SwiftUI

// MARK: - Snapshot Card View

/// A card displaying a single snapshot with header, actions, and tab list.
///
/// Each card shows:
/// - Header: Time, tab count, and space name badge
/// - Action buttons: Restore Snapshot and Add Tabs
/// - Tab list: Individual tabs with favicons and domains
struct SnapshotCardView: View {
    let snapshot: TabSnapshot
    let spaceName: String?
    let onRestore: () -> Void
    let onAddTabs: () -> Void
    let onTabClick: (TabSnapshotItem) -> Void
    let onTabCmdClick: (TabSnapshotItem) -> Void

    private enum Constants {
        static let cornerRadius: CGFloat = 12
        static let headerVerticalPadding: CGFloat = 10
        static let headerHorizontalPadding: CGFloat = 12
        static let buttonHeight: CGFloat = 28
        static let buttonCornerRadius: CGFloat = 6
        static let maxVisibleTabs = 10
    }

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            cardHeader

            // Divider
            Divider()
                .padding(.horizontal, 8)

            // Action buttons
            actionButtons
                .padding(.horizontal, Constants.headerHorizontalPadding)
                .padding(.vertical, 8)

            // Divider
            Divider()
                .padding(.horizontal, 8)

            // Tab list
            tabList
        }
        .adaptiveBackground(.subtle, in: RoundedRectangle(cornerRadius: Constants.cornerRadius))
    }

    // MARK: - Header

    private var cardHeader: some View {
        HStack {
            // Time and tab count
            HStack(spacing: 8) {
                Text(formattedTime)
                    .font(.system(size: 13, weight: .semibold))

                Text("·")
                    .foregroundStyle(.secondary)

                Text(tabCountLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Space badge
            if let spaceName {
                Text(spaceName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule()
                            .fill(.quaternary)
                    }
            }
        }
        .padding(.horizontal, Constants.headerHorizontalPadding)
        .padding(.vertical, Constants.headerVerticalPadding)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 8) {
            // Restore Snapshot button
            Button(action: onRestore) {
                Label("Restore", systemImage: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(SnapshotActionButtonStyle(isPrimary: true))

            // Add Tabs button
            Button(action: onAddTabs) {
                Label("Add Tabs", systemImage: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(SnapshotActionButtonStyle(isPrimary: false))
        }
    }

    // MARK: - Tab List

    private var tabList: some View {
        VStack(spacing: 0) {
            let items = sortedItems
            let displayItems = isExpanded ? items : Array(items.prefix(Constants.maxVisibleTabs))

            ForEach(displayItems) { item in
                SnapshotTabItemView(
                    item: item,
                    onClick: { onTabClick(item) },
                    onCmdClick: { onTabCmdClick(item) },
                )
            }

            // Show more button if needed
            if items.count > Constants.maxVisibleTabs {
                showMoreButton(remaining: items.count - Constants.maxVisibleTabs)
            }
        }
    }

    private func showMoreButton(remaining: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        } label: {
            HStack {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))

                Text(isExpanded ? "Show Less" : "Show \(remaining) More")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Computed Properties

    private var formattedTime: String {
        snapshot.createdAt.formatted(date: .omitted, time: .shortened)
    }

    private var tabCountLabel: String {
        if snapshot.tabCount == 1 {
            "1 tab"
        } else {
            "\(snapshot.tabCount) tabs"
        }
    }

    private var sortedItems: [TabSnapshotItem] {
        snapshot.items.sorted { $0.position < $1.position }
    }
}

// MARK: - Snapshot Action Button Style

private struct SnapshotActionButtonStyle: ButtonStyle {
    let isPrimary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background {
                if isPrimary {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.blue)
                } else {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.clear)
                        .adaptiveBackground(.subtle, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .foregroundStyle(isPrimary ? .white : .primary)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
