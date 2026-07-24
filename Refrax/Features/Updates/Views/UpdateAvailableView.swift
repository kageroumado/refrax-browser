import SwiftUI

/// Sheet shown when an update has been downloaded and is ready to install.
///
/// Displays the available version, release notes, and a restart button.
/// The update has already been downloaded — the user just needs to restart.
///
/// ## Actions
///
/// - **Restart Now**: Transitions the sheet to a loading state, then initiates
///   ``AppUpdateManager/restartToUpdate()`` which mounts the DMG, verifies
///   code signing, stages the new app, and terminates. The sheet stays open
///   until the process exits.
/// - **Later**: Dismisses the sheet. The update remains downloaded and the sidebar
///   continues to show the restart indicator.
struct UpdateAvailableView: View {
    @Environment(AppUpdateManager.self) private var updateManager
    @Environment(\.dismiss) private var dismiss

    /// Captured on appear so the view doesn't lose its data when phase
    /// transitions to `.installing`.
    @State private var update: AppUpdate?
    @State private var isInstalling = false

    var body: some View {
        Group {
            if isInstalling {
                installingView
            } else {
                contentView
            }
        }
        .frame(width: 480, height: 400)
        .onAppear {
            if case .readyToInstall(let u) = updateManager.phase {
                update = u
            }
        }
        .onChange(of: updateManager.phase) {
            if case .failed = updateManager.phase {
                isInstalling = false
            }
        }
    }

    private var contentView: some View {
        VStack(spacing: 0) {
            header
            Divider()
            releaseNotesSection
            Divider()
            actionButtons
        }
    }

    private var installingView: some View {
        VStack(spacing: Constants.Spacing.medium) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)

            Text("Installing update…")
                .font(.system(size: Constants.Typography.headerSizeLarge, weight: .semibold))

            Text("Refrax will restart automatically")
                .font(.system(size: Constants.Typography.captionSize))
                .foregroundStyle(.tertiary)

            Spacer()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: Constants.Spacing.small) {
            Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                .font(.system(size: 36))
                .foregroundStyle(.green)

            if let update {
                Text("Refrax \(update.version) is ready")
                    .font(.system(size: Constants.Typography.headerSizeLarge, weight: .semibold))

                Text("You're currently on \(Constants.App.version)")
                    .font(.system(size: Constants.Typography.captionSize))
                    .foregroundStyle(.tertiary)
            } else {
                Text("Update Ready")
                    .font(.system(size: Constants.Typography.headerSizeLarge, weight: .semibold))
            }
        }
        .padding(.vertical, Constants.Spacing.medium)
    }

    // MARK: - Release Notes

    private var releaseNotesSection: some View {
        VStack(alignment: .leading, spacing: Constants.Spacing.small) {
            Text("Release Notes")
                .font(.system(size: Constants.Typography.bodyMediumSize, weight: .medium))
                .foregroundStyle(.secondary)

            ScrollView {
                if let update, !update.releaseNotes.isEmpty {
                    ReleaseNotesText(markdown: update.releaseNotes)
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

            Button("Later") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button("Restart Now") {
                isInstalling = true
                Task {
                    await updateManager.restartToUpdate()
                }
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(Constants.Spacing.medium)
    }

}
