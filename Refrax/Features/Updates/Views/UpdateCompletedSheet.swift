import SwiftUI

/// Sheet displaying release notes after a successful update.
///
/// Shown when the user taps the ``UpdateNotificationPanel`` in the sidebar.
/// Displays the version transition and full markdown-formatted release notes.
struct UpdateCompletedSheet: View {
    let info: AppUpdateManager.PostUpdateInfo
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            releaseNotesSection
            Divider()
            actionButtons
        }
        .frame(width: 480, height: 400)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Constants.Spacing.small) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)

            Text("Refrax has been updated")
                .font(.system(size: Constants.Typography.headerSizeLarge, weight: .semibold))

            Text("v\(info.previousVersion) → v\(info.version)")
                .font(.system(size: Constants.Typography.bodyLargeSize))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, Constants.Spacing.medium)
    }

    // MARK: - Release Notes

    private var releaseNotesSection: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.small) {
            Text("What's New")
                .font(.system(size: Constants.Typography.bodyMediumSize, weight: .medium))
                .foregroundStyle(.secondary)

            ScrollView {
                if !info.releaseNotes.isEmpty {
                    ReleaseNotesText(markdown: info.releaseNotes)
                } else {
                    Text("No release notes available.")
                        .font(.system(size: Constants.Typography.bodySize))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(Constants.Spacing.medium)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Actions

    private var actionButtons: some View {
        HStack {
            Spacer()

            Button("Got it") {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(Constants.Spacing.medium)
    }

}
