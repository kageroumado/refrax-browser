import SwiftUI

/// Notification panel shown in the sidebar after an automatic crash report is sent.
///
/// Follows the same layout and animation pattern as ``UpdateNotificationPanel``.
/// Auto-dismisses after 60 seconds.
struct CrashReportPanel: View {
    @Environment(AppUpdateManager.self) private var updateManager
    @State private var showDetailSheet = false

    var body: some View {
        if updateManager.crashReportSent {
            panel
        }
    }

    private var panel: some View {
        Button {
            showDetailSheet = true
        } label: {
            HStack(spacing: Constants.Spacing.small) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)

                Text("Crash report sent")
                    .font(.system(size: Constants.Typography.bodySize))
                    .lineLimit(1)

                Spacer()

                circularButton(icon: "xmark") {
                    dismiss()
                }
            }
            .padding(.horizontal, Constants.Spacing.small)
            .padding(.vertical, 6)
            .adaptiveBackground(.subtle, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .sheet(isPresented: $showDetailSheet) {
            crashDetailSheet
        }
        .task {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            dismiss()
        }
    }

    private var crashDetailSheet: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Crash Detected")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Refrax crashed during your last session. A crash report was automatically sent to help us fix this.\n\nIf you'd like to share more details about what happened, use the feedback form (⌘T).")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)

            Button("Got it") {
                showDetailSheet = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .frame(width: 440, height: 320)
    }

    private func dismiss() {
        withAnimation(.easeOut(duration: 0.3)) {
            updateManager.crashReportSent = false
        }
    }

    private func circularButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
    }
}
