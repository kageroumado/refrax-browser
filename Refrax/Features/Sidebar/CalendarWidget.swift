import SwiftUI

// MARK: - Calendar Widget Button

/// Button in the sidebar bottom bar that toggles the calendar widget.
struct CalendarWidgetButton: View {
    @Environment(CalendarManager.self) private var calendarManager
    @Environment(BrowserSettings.self) private var settings

    @State private var isExpanded = false

    var body: some View {
        if settings.showCalendarWidget, !calendarManager.upcomingEvents.isEmpty {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                ZStack {
                    Image(systemName: "calendar")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(badgeColor)
                        .frame(width: Layout.buttonSize, height: Layout.buttonSize)
                        .contentShape(Rectangle())

                    // Badge for imminent events
                    if calendarManager.hasImminentEvent {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                            .offset(x: 8, y: -8)
                    }
                }
            }
            .buttonStyle(.plain)
            .adaptiveBackground(.subtle, in: RoundedRectangle(cornerRadius: Layout.buttonCornerRadius))
            .accessibilityIdentifier("sidebar-calendar")
            .accessibilityLabel("Calendar")
            .if(isExpanded) { view in
                view.popover(isPresented: $isExpanded, arrowEdge: .bottom) {
                    CalendarWidgetPopover()
                        .environment(calendarManager)
                        .environment(settings)
                }
            }
            .onAppear {
                // Auto-expand on imminent event if setting enabled
                if settings.calendarAutoExpandOnImminent, calendarManager.hasImminentEvent {
                    isExpanded = true
                }
            }
            .onChange(of: calendarManager.hasImminentEvent) { _, hasImminent in
                if settings.calendarAutoExpandOnImminent, hasImminent, !isExpanded {
                    withAnimation {
                        isExpanded = true
                    }
                }
            }
        }
    }

    private var badgeColor: Color {
        if calendarManager.hasImminentEvent {
            .orange
        } else if isExpanded {
            .appAccentColor
        } else {
            .primary
        }
    }
}

// MARK: - Calendar Widget Popover

/// Popover content showing upcoming calendar events.
struct CalendarWidgetPopover: View {
    @Environment(CalendarManager.self) private var calendarManager
    @Environment(BrowserSettings.self) private var settings

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            content
        }
        .frame(width: 280)
        .frame(minHeight: 100, maxHeight: 400)
    }

    private var header: some View {
        HStack {
            Text("Upcoming Events")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            Button {
                calendarManager.refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(calendarManager.isRefreshing)
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if calendarManager.upcomingEvents.isEmpty {
            emptyStateView
        } else {
            eventsList
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)

            Text("No upcoming events")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Text("Events within the next \(settings.calendarLookAheadHours) hours will appear here.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var eventsList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(calendarManager.upcomingEvents) { event in
                    CalendarEventRow(event: event)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
    }
}

// MARK: - Calendar Event Row

/// Individual row displaying a calendar event.
struct CalendarEventRow: View {
    @Environment(CalendarManager.self) private var calendarManager

    let event: CalendarEvent

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            // Color indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(cgColor: event.calendarColor))
                .frame(width: 4, height: 36)

            // Event details
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(event.title)
                        .font(.system(size: 12, weight: event.isOngoing ? .semibold : .medium))
                        .lineLimit(1)

                    // Video icon for meetings
                    if event.hasMeeting {
                        Image(systemName: "video.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.appAccentColor)
                    }
                }

                HStack(spacing: 4) {
                    if event.isOngoing {
                        Text("Now")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.green)
                    } else if event.startsWithin(minutes: 15) {
                        Text("Soon")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.orange)
                    }

                    Text(event.formattedTime)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    if let duration = event.formattedDuration {
                        Text("(\(duration))")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }

                    // Calendar name
                    Text("• \(event.calendarTitle)")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                if let location = event.location, !location.isEmpty, !isLocationMeetingURL {
                    Label(location, systemImage: "location")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            // Action buttons (visible on hover)
            if isHovering {
                HStack(spacing: 4) {
                    // Join meeting button
                    if event.hasMeeting {
                        Button {
                            calendarManager.openEvent(event)
                        } label: {
                            Text("Join")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.appAccentColor, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Join Meeting")
                    }

                    // Open in Calendar button
                    Button {
                        calendarManager.openEventInCalendar(event)
                    } label: {
                        Image(systemName: "calendar")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open in Calendar")
                }
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
        .onTapGesture {
            calendarManager.openEvent(event)
        }
    }

    /// Whether the location field is actually a meeting URL (to avoid showing it twice).
    private var isLocationMeetingURL: Bool {
        guard let location = event.location,
              let url = URL(string: location) else {
            return false
        }
        return CalendarEvent.isMeetingURL(url)
    }

    private var backgroundStyle: some ShapeStyle {
        if event.isOngoing {
            AnyShapeStyle(Color.green.opacity(0.1))
        } else if event.startsWithin(minutes: 15) {
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
