import SwiftUI

/// Toolbar for HistoryGraphView with date picker and zoom controls.
struct HistoryGraphToolbar: View {
    @Binding var selectedDate: Date
    let zoomLevel: GraphCoordinates.ZoomLevel

    var onZoomIn: () async -> Void
    var onZoomOut: () async -> Void
    var onNavigateToToday: () async -> Void

    var body: some View {
        HStack {
            // Date picker
            DatePicker(
                "Select date",
                selection: $selectedDate,
                displayedComponents: .date,
            )
            .labelsHidden()

            Spacer()

            // Zoom controls
            HStack(spacing: 8) {
                Text("Zoom:")
                    .foregroundStyle(.secondary)

                Button(action: {
                    Task { await onZoomOut() }
                }) {
                    Image(systemName: "minus.magnifyingglass")
                }
                .disabled(zoomLevel == .compressed)

                Text(zoomLevel.description)
                    .frame(minWidth: 60)
                    .foregroundStyle(.secondary)

                Button(action: {
                    Task { await onZoomIn() }
                }) {
                    Image(systemName: "plus.magnifyingglass")
                }
                .disabled(zoomLevel == .extremeZoom)
            }
            .padding(.horizontal)

            // Today button
            Button("Today") {
                Task { await onNavigateToToday() }
            }
        }
        .padding()
    }
}
