import SwiftUI

/// A sheet for setting page reminders with quick duration presets.
struct RemindMeSheet: View {
    let pageURL: URL
    let pageTitle: String
    @Binding var isPresented: Bool

    @Environment(PageReminderManager.self) private var reminderManager
    @Environment(WindowState.self) private var windowState

    @State private var selectedDuration: ReminderDuration?
    @State private var customDate: Date = .init()
    @State private var showingCustomPicker = false
    @State private var useSystemReminder = false
    @State private var isScheduling = false
    @State private var errorMessage: String?

    private var displayTitle: String {
        if pageTitle.isEmpty {
            return pageURL.host ?? pageURL.absoluteString
        }
        if pageTitle.count > 80 {
            return String(pageTitle.prefix(77)) + "..."
        }
        return pageTitle
    }

    private var displayHost: String {
        pageURL.host ?? pageURL.absoluteString
    }

    private var canSchedule: Bool {
        selectedDuration != nil && !isScheduling
    }

    private var reminderDate: Date? {
        guard let duration = selectedDuration else { return nil }
        if duration == .custom {
            return customDate
        }
        return duration.date()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "bell.badge")
                    .foregroundStyle(.secondary)
                Text("Remind Me")
                    .font(.headline)
            }
            .padding(.bottom, 14)

            // Page info
            HStack(spacing: 8) {
                FaviconView(url: pageURL, size: 16)

                VStack(alignment: .leading, spacing: 1) {
                    Text(displayTitle)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(displayHost)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 14)

            // Duration grid
            durationGrid
                .padding(.bottom, 12)

            // Custom picker
            if showingCustomPicker {
                customDatePicker
                    .padding(.bottom, 12)
            }

            // System reminder toggle
            systemReminderToggle
                .padding(.bottom, 14)

            // Error
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 8)
            }

            // Actions
            actionButtons
        }
        .padding(Layout.padding)
        .frame(width: Layout.sheetWidth)
    }

    // MARK: - Duration Grid

    private var durationGrid: some View {
        LazyVGrid(columns: Layout.gridColumns, spacing: 6) {
            ForEach(ReminderDuration.allCases) { duration in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        handleDurationSelection(duration)
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: duration.icon)
                            .font(.system(size: 13))
                        Text(duration.label)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(selectedDuration == duration ? Color.appAccentColor : .primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedDuration == duration ? Color.appAccentColor.opacity(0.12) : Color.primary.opacity(0.04))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                selectedDuration == duration ? Color.appAccentColor.opacity(0.5) : Color.primary.opacity(0.08),
                                lineWidth: 1,
                            )
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Custom Date Picker

    @ViewBuilder
    private var customDatePicker: some View {
        DatePicker(
            "Reminder Time",
            selection: $customDate,
            in: Date()...,
            displayedComponents: [.date, .hourAndMinute],
        )
        .datePickerStyle(.compact)
        .labelsHidden()
        .onChange(of: customDate) { _, _ in
            if selectedDuration != .custom {
                selectedDuration = .custom
            }
        }
    }

    // MARK: - System Reminder Toggle

    private var systemReminderToggle: some View {
        Toggle(isOn: $useSystemReminder) {
            HStack(spacing: 6) {
                Image(systemName: "app.badge.checkmark")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Add to Reminders.app")
                        .font(.system(size: 12))
                    Text("Syncs to iPhone, iPad, and Watch")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .toggleStyle(.checkbox)
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack {
            Button("Cancel") {
                isPresented = false
            }
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button {
                Task {
                    await scheduleReminder()
                }
            } label: {
                if isScheduling {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.horizontal, 8)
                } else {
                    Text("Set Reminder")
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSchedule)
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func handleDurationSelection(_ duration: ReminderDuration) {
        if duration == .custom {
            showingCustomPicker = true
            if customDate <= Date() {
                customDate = Date().addingTimeInterval(3_600)
            }
        } else {
            showingCustomPicker = false
        }
        selectedDuration = duration
        errorMessage = nil
    }

    private func scheduleReminder() async {
        guard let date = reminderDate else { return }

        isScheduling = true
        errorMessage = nil

        let reminder = PageReminder(
            pageURL: pageURL,
            pageTitle: pageTitle.isEmpty ? displayHost : pageTitle,
            reminderDate: date,
            useSystemReminder: useSystemReminder,
        )

        do {
            try await reminderManager.scheduleReminder(reminder)
            isPresented = false

            let timeDescription = reminder.formattedTimeUntil
            windowState.showToast("Reminder set for \(timeDescription)")
        } catch {
            errorMessage = error.localizedDescription
        }

        isScheduling = false
    }
}

// MARK: - Layout Constants

private extension RemindMeSheet {
    enum Layout {
        static let padding: CGFloat = 18
        static let sheetWidth: CGFloat = 320
        static let gridColumns = [
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
            GridItem(.flexible(), spacing: 6),
        ]
    }
}

// MARK: - Preview

#Preview(traits: .modifier(RefraxPreviewModifier())) {
    RemindMeSheet(
        pageURL: URL.staticRequired("https://example.com/article/interesting-topic"),
        pageTitle: "An Interesting Article About Technology and Innovation",
        isPresented: .constant(true),
    )
}
