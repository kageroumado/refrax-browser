import SwiftUI

// MARK: - Reminders Widget Button

/// Button in the sidebar bottom bar that toggles the reminders widget.
///
/// Only visible when there are pending page reminders.
struct RemindersWidgetButton: View {
    @Environment(PageReminderManager.self) private var reminderManager

    @State private var isExpanded = false

    var body: some View {
        if reminderManager.hasPendingReminders {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isExpanded ? Color.appAccentColor : .primary)

                    Text("\(reminderManager.pendingItems.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isExpanded ? Color.appAccentColor : .secondary)
                }
                .frame(height: Layout.buttonSize)
                .padding(.horizontal, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .adaptiveBackground(.subtle, in: RoundedRectangle(cornerRadius: Layout.buttonCornerRadius))
            .accessibilityIdentifier("sidebar-reminders")
            .accessibilityLabel("Reminders (\(reminderManager.pendingItems.count) pending)")
            .help("Page Reminders")
            .popover(isPresented: $isExpanded, arrowEdge: .bottom) {
                RemindersWidgetPopover()
                    .environment(reminderManager)
            }
        }
    }
}

// MARK: - Reminders Widget Popover

/// Popover content showing pending page reminders.
struct RemindersWidgetPopover: View {
    @Environment(PageReminderManager.self) private var reminderManager

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            content
        }
        .frame(width: 280)
        .frame(minHeight: 80, maxHeight: 400)
        .task {
            await reminderManager.refreshPendingItems()
        }
    }

    private var header: some View {
        HStack {
            Text("Page Reminders")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            Button {
                Task {
                    await reminderManager.refreshPendingItems()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if reminderManager.pendingItems.isEmpty {
            emptyStateView
        } else {
            remindersList
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell.slash")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)

            Text("No pending reminders")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var remindersList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(reminderManager.pendingItems) { item in
                    ReminderRow(item: item)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Reminder Row

/// Individual row displaying a pending reminder.
private struct ReminderRow: View {
    @Environment(PageReminderManager.self) private var reminderManager

    let item: PendingReminderItem

    @State private var isHovering = false

    private var isSoon: Bool {
        item.fireDate.timeIntervalSinceNow < 15 * 60
    }

    var body: some View {
        HStack(spacing: 8) {
            // Bell icon
            Image(systemName: isSoon ? "bell.badge.fill" : "bell")
                .font(.system(size: 11))
                .foregroundStyle(isSoon ? .orange : .secondary)
                .frame(width: 16)

            // Reminder details
            VStack(alignment: .leading, spacing: 2) {
                Text(item.pageTitle)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(item.formattedAbsoluteTime)
                        .font(.system(size: 10))
                        .foregroundStyle(isSoon ? .orange : .secondary)

                    Text("• \(item.host)")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // Cancel button (visible on hover)
            if isHovering {
                Button {
                    Task {
                        await reminderManager.cancelReminder(identifier: item.id)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Cancel reminder")
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(backgroundStyle, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }

    private var backgroundStyle: some ShapeStyle {
        if isSoon {
            AnyShapeStyle(Color.orange.opacity(0.08))
        } else if isHovering {
            AnyShapeStyle(Color.primary.opacity(0.05))
        } else {
            AnyShapeStyle(Color.clear)
        }
    }
}

// MARK: - Layout Constants

private enum Layout {
    static let buttonSize: CGFloat = 32
    static let buttonCornerRadius: CGFloat = 16
}
