import SwiftUI

/// View displaying a list of bookmarks that failed to import.
///
/// Shows each failed bookmark with its URL, title, and the reason
/// for the failure. Users can copy URLs to manually add bookmarks
/// that couldn't be imported automatically.
struct FailedBookmarksView: View {
    @Bindable var viewModel: ImportWizardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.sectionSpacing) {
            headerSection
            bookmarksList
        }
    }

    private enum Constants {
        static let sectionSpacing: CGFloat = 12
        static let horizontalPadding: CGFloat = 20
        static let topPadding: CGFloat = 16
        static let bottomPadding: CGFloat = 16
        static let rowSpacing: CGFloat = 8
    }
}

// MARK: - Sections

private extension FailedBookmarksView {
    var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Failed Imports")
                .font(.headline)

            Text("The following bookmarks could not be imported:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.top, Constants.topPadding)
    }

    var bookmarksList: some View {
        ScrollView {
            LazyVStack(spacing: Constants.rowSpacing) {
                if let result = viewModel.result {
                    ForEach(result.failedBookmarks) { failed in
                        FailedBookmarkRow(failedBookmark: failed)
                    }
                }
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.bottom, Constants.bottomPadding)
        }
    }
}

// MARK: - Failed Bookmark Row

/// A row displaying information about a failed bookmark import.
private struct FailedBookmarkRow: View {
    let failedBookmark: ImportResult.FailedBookmark

    var body: some View {
        HStack(spacing: Constants.spacing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(failedBookmark.bookmark.title)
                    .font(.body)
                    .lineLimit(1)

                Text(failedBookmark.bookmark.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(failedBookmark.reason)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            Spacer()

            Button(action: copyURL) {
                Image(systemName: "doc.on.doc")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .help("Copy URL")
        }
        .padding(Constants.padding)
        .background(
            RoundedRectangle(cornerRadius: Constants.cornerRadius)
                .fill(Color.red.opacity(0.05)),
        )
    }

    private enum Constants {
        static let spacing: CGFloat = 12
        static let padding: CGFloat = 12
        static let cornerRadius: CGFloat = 8
    }

    private func copyURL() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(failedBookmark.bookmark.url.absoluteString, forType: .string)
    }
}
