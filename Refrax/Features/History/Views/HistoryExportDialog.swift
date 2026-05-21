import SwiftData
import SwiftUI

/// Dialog for exporting browsing history with date range selection.
///
/// Provides date pickers, quick presets, and a preview of the entry count
/// before exporting to Safari-compatible JSON format.
struct HistoryExportDialog: View {
    @Environment(HistoryManager.self) private var historyManager
    let onExport: (Date, Date) -> Void
    let onCancel: () -> Void

    @State private var fromDate: Date
    @State private var toDate: Date
    @State private var entryCount: Int = 0
    @State private var isCalculating = false
    @State private var updateTask: Task<Void, Never>?

    private enum Constants {
        static let dialogWidth: CGFloat = 400
        static let dialogMinHeight: CGFloat = 280
        static let sectionSpacing: CGFloat = 16
        static let estimatedBytesPerEntry: Int = 200
    }

    init(
        onExport: @escaping (Date, Date) -> Void,
        onCancel: @escaping () -> Void,
    ) {
        self.onExport = onExport
        self.onCancel = onCancel

        // Default to last 30 days
        let now = Date()
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        _fromDate = State(initialValue: thirtyDaysAgo)
        _toDate = State(initialValue: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.sectionSpacing) {
            header
            dateRangePickers
            quickPresets
            Divider()
            entryCountPreview
            Spacer()
            footer
        }
        .padding()
        .frame(width: Constants.dialogWidth)
        .frame(minHeight: Constants.dialogMinHeight)
        .task {
            await updateEntryCount()
        }
        .onChange(of: fromDate) {
            updateTask?.cancel()
            updateTask = Task { await updateEntryCount() }
        }
        .onChange(of: toDate) {
            updateTask?.cancel()
            updateTask = Task { await updateEntryCount() }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        Text("Export History")
            .font(.headline)
    }

    private var dateRangePickers: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Date Range")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("From")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    DatePicker(
                        "",
                        selection: $fromDate,
                        in: ...toDate,
                        displayedComponents: .date,
                    )
                    .labelsHidden()
                    .datePickerStyle(.field)
                }

                Text("to")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("To")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    DatePicker(
                        "",
                        selection: $toDate,
                        in: fromDate...,
                        displayedComponents: .date,
                    )
                    .labelsHidden()
                    .datePickerStyle(.field)
                }

                Spacer()
            }
        }
    }

    private var quickPresets: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Select")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                presetButton("Last 7 days", days: 7)
                presetButton("Last 30 days", days: 30)
                presetButton("Last 90 days", days: 90)
                presetButton("All time", days: nil)
            }
        }
    }

    private func presetButton(_ title: String, days: Int?) -> some View {
        Button(title) {
            applyPreset(days: days)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var entryCountPreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isCalculating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Calculating...")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("\(entryCount.formatted()) entries in selected range")
                    .font(.body)

                if entryCount > 0 {
                    Text("Estimated file size: ~\(estimatedFileSize)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()

            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.cancelAction)

            Button("Export...") {
                onExport(normalizedFromDate, normalizedToDate)
            }
            .keyboardShortcut(.defaultAction)
            .disabled(entryCount == 0 || isCalculating)
        }
    }

    // MARK: - Helpers

    private var normalizedFromDate: Date {
        Calendar.current.startOfDay(for: fromDate)
    }

    private var normalizedToDate: Date {
        // End of day for the to date
        let startOfDay = Calendar.current.startOfDay(for: toDate)
        return Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)?.addingTimeInterval(-1) ?? toDate
    }

    private var estimatedFileSize: String {
        let bytes = entryCount * Constants.estimatedBytesPerEntry
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func applyPreset(days: Int?) {
        let now = Date()
        toDate = now

        if let days {
            fromDate = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        } else {
            // All time: use a very old date
            fromDate = Calendar.current.date(byAdding: .year, value: -50, to: now) ?? now
        }
    }

    private func updateEntryCount() async {
        isCalculating = true
        // Small delay to debounce rapid date changes
        try? await Task.sleep(for: .milliseconds(100))

        // Check if cancelled during debounce
        guard !Task.isCancelled else {
            isCalculating = false
            return
        }

        let exporter = HistoryExporter(historyManager: historyManager)
        entryCount = await exporter.entryCount(from: normalizedFromDate, to: normalizedToDate)
        isCalculating = false
    }
}

// MARK: - Preview

private struct HistoryExportDialogPreview: View {
    var body: some View {
        HistoryExportDialog(
            onExport: { from, to in
                print("Export from \(from) to \(to)")
            },
            onCancel: {
                print("Cancelled")
            },
        )
    }
}

#Preview(traits: .modifier(RefraxPreviewModifier())) {
    HistoryExportDialogPreview()
}
