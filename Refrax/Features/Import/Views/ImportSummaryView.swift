import SwiftUI

/// View displaying the summary of a completed import operation.
///
/// Shows comprehensive statistics about all imported data types:
/// bookmarks, history, passwords, and extensions scanned.
struct ImportSummaryView: View {
    @Bindable var viewModel: ImportWizardViewModel

    var body: some View {
        ScrollView {
            VStack(spacing: Constants.sectionSpacing) {
                Spacer(minLength: Constants.topSpacing)

                statusIcon
                statusTitle

                if viewModel.error == nil {
                    comprehensiveStats
                }

                if let error = viewModel.error {
                    errorSection(error)
                }

                Spacer(minLength: Constants.bottomSpacing)
            }
            .padding(.horizontal, Constants.horizontalPadding)
        }
    }

    private enum Constants {
        static let sectionSpacing: CGFloat = 20
        static let horizontalPadding: CGFloat = 24
        static let topSpacing: CGFloat = 20
        static let bottomSpacing: CGFloat = 20
        static let iconSize: CGFloat = 56
        static let statsSpacing: CGFloat = 16
        static let statItemSpacing: CGFloat = 4
    }
}

// MARK: - Status Components

private extension ImportSummaryView {
    @ViewBuilder
    var statusIcon: some View {
        if viewModel.error != nil {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: Constants.iconSize))
                .foregroundStyle(.orange)
        } else if viewModel.hasFailedBookmarks {
            Image(systemName: "checkmark.circle.badge.questionmark.fill")
                .font(.system(size: Constants.iconSize))
                .foregroundStyle(.yellow)
        } else {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: Constants.iconSize))
                .foregroundStyle(.green)
        }
    }

    var statusTitle: some View {
        Text(statusMessage)
            .font(.title3)
            .fontWeight(.semibold)
    }

    var statusMessage: String {
        if viewModel.error != nil {
            "Import Failed"
        } else if viewModel.hasFailedBookmarks {
            "Import Completed with Errors"
        } else {
            "Import Successful"
        }
    }
}

// MARK: - Comprehensive Statistics

private extension ImportSummaryView {
    var comprehensiveStats: some View {
        VStack(spacing: Constants.statsSpacing) {
            if viewModel.importOptions.importBookmarks {
                statsRow(
                    title: "Bookmarks",
                    icon: "bookmark.fill",
                    color: .blue,
                    stats: [
                        ("Imported", viewModel.comprehensiveResult.bookmarksImported),
                        ("Folders", viewModel.comprehensiveResult.foldersCreated),
                        ("Skipped", viewModel.comprehensiveResult.bookmarkDuplicatesSkipped),
                    ],
                )
            }

            if viewModel.importOptions.importHistory {
                statsRow(
                    title: "History",
                    icon: "clock.fill",
                    color: .orange,
                    stats: [
                        ("Entries", viewModel.comprehensiveResult.historyEntriesImported),
                    ],
                )
            }

            if viewModel.importOptions.importPasswords {
                statsRow(
                    title: "Passwords",
                    icon: "key.fill",
                    color: .green,
                    stats: [
                        ("Imported", viewModel.comprehensiveResult.credentialsImported),
                        ("Conflicts", viewModel.comprehensiveResult.credentialConflictsResolved),
                    ],
                )
            }

            if viewModel.importOptions.importExtensions {
                statsRow(
                    title: "Extensions",
                    icon: "puzzlepiece.extension.fill",
                    color: .purple,
                    stats: [
                        ("Found", viewModel.comprehensiveResult.extensionsFound),
                    ],
                )
            }
        }
    }

    func statsRow(
        title: String,
        icon: String,
        color: Color,
        stats: [(label: String, value: Int)],
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .fontWeight(.medium)
            }

            HStack(spacing: 20) {
                ForEach(stats, id: \.label) { stat in
                    HStack(spacing: 4) {
                        Text("\(stat.value)")
                            .font(.headline)
                            .fontWeight(.bold)
                        Text(stat.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.03)),
        )
    }
}

// MARK: - Error Section

private extension ImportSummaryView {
    func errorSection(_ error: ImportError) -> some View {
        VStack(spacing: 8) {
            Text("Error")
                .font(.headline)
                .foregroundStyle(.red)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.1)),
        )
    }
}
