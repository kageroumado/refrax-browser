import SwiftUI

// MARK: - Snapshot Folder Row

/// A row representing a date folder in the snapshot list.
///
/// Displays the date label (Today, Yesterday, day name, or formatted date)
/// and the count of snapshots on that date. Tapping navigates into the folder.
struct SnapshotFolderRow: View {
    let dateComponents: DateComponents
    let snapshotCount: Int
    let action: () -> Void

    private enum Constants {
        static let iconSize: CGFloat = 28
        static let verticalPadding: CGFloat = 12
        static let horizontalPadding: CGFloat = 16
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Folder icon
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.blue.opacity(0.15))

                    Image(systemName: "folder.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.blue)
                }
                .frame(width: Constants.iconSize, height: Constants.iconSize)

                // Date label
                Text(formattedDate)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                // Snapshot count
                Text(countLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.vertical, Constants.verticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Computed Properties

    private var formattedDate: String {
        guard let date = Calendar.current.date(from: dateComponents) else {
            return "Unknown"
        }
        return SnapshotDateFormatter.formatDate(date, style: .folder)
    }

    private var countLabel: String {
        if snapshotCount == 1 {
            "1 save"
        } else {
            "\(snapshotCount) saves"
        }
    }
}
