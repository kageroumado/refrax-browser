import SwiftUI

/// Notification panel shown in the sidebar bottom controls for update events.
///
/// Displays two distinct states:
/// - **Post-update**: After a successful update (``AppUpdateManager/justUpdated``).
///   Auto-dismisses after 60 seconds. Tapping opens ``UpdateCompletedSheet``.
/// - **Failed update**: When ``AppUpdateManager/showFailedPanel`` is set after
///   clicking the warning icon. Shows the error message with retry and close buttons.
///   Closing dismisses the failure and suppresses checks until the next scheduler cycle.
///
/// Follows the same layout pattern as ``MediaControlsPanel`` and ``ShelfPanel``.
struct UpdateNotificationPanel: View {
    @Environment(AppUpdateManager.self) private var updateManager
    @State private var showCompletedSheet = false

    var body: some View {
        if let info = updateManager.justUpdated {
            successPanel(info: info)
        } else if updateManager.showFailedPanel, case .failed(let message) = updateManager.phase {
            failedPanel(message: message)
        }
    }

    // MARK: - Success Panel

    private func successPanel(info: AppUpdateManager.PostUpdateInfo) -> some View {
        Button {
            showCompletedSheet = true
        } label: {
            HStack(spacing: Constants.Spacing.small) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)

                Text("Updated to v\(info.version)")
                    .font(.system(size: Constants.Typography.bodySize))
                    .lineLimit(1)

                Spacer()

                circularButton(icon: "xmark") {
                    withAnimation(.easeOut(duration: 0.2)) {
                        updateManager.justUpdated = nil
                    }
                }
            }
            .padding(.horizontal, Constants.Spacing.small)
            .padding(.vertical, 6)
            .adaptiveBackground(.subtle, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .sheet(isPresented: $showCompletedSheet) {
            UpdateCompletedSheet(info: info)
        }
        .task {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                updateManager.justUpdated = nil
            }
        }
    }

    // MARK: - Failed Panel

    private func failedPanel(message: String) -> some View {
        HStack(spacing: Constants.Spacing.small) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            Text(message)
                .font(.system(size: Constants.Typography.bodySize))
                .lineLimit(2)
                .foregroundStyle(.secondary)

            Spacer()

            circularButton(icon: "arrow.clockwise") {
                withAnimation(.easeOut(duration: 0.2)) {
                    updateManager.showFailedPanel = false
                }
                Task {
                    await updateManager.checkForUpdates(manual: true)
                }
            }

            circularButton(icon: "xmark") {
                withAnimation(.easeOut(duration: 0.2)) {
                    updateManager.dismissFailure()
                }
            }
        }
        .padding(.horizontal, Constants.Spacing.small)
        .padding(.vertical, 6)
        .adaptiveBackground(.subtle, in: RoundedRectangle(cornerRadius: 10))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Shared

    private func circularButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
    }
}
