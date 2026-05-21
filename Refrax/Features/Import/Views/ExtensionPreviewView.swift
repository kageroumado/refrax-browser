import SwiftUI

/// View displaying the extensions found during import.
///
/// Since Refrax doesn't yet support extensions, this view shows what
/// extensions were detected for informational purposes only.
struct ExtensionPreviewView: View {
    @Bindable var viewModel: ImportWizardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.sectionSpacing) {
            headerSection
            extensionList
        }
    }

    private enum Constants {
        static let sectionSpacing: CGFloat = 12
        static let horizontalPadding: CGFloat = 20
        static let topPadding: CGFloat = 16
        static let bottomPadding: CGFloat = 16
    }
}

// MARK: - Header

private extension ExtensionPreviewView {
    var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "puzzlepiece.extension.fill")
                    .foregroundStyle(.purple)

                Text("\(viewModel.comprehensiveResult.extensionsFound) Extension\(viewModel.comprehensiveResult.extensionsFound == 1 ? "" : "s") Found")
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("The following extensions were detected in your browser profile.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 4) {
                    Image(systemName: "info.circle")
                        .font(.caption)
                    Text("Extension support is planned for a future release of Refrax.")
                        .font(.caption)
                }
                .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.top, Constants.topPadding)
    }
}

// MARK: - Extension List

private extension ExtensionPreviewView {
    var extensionList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(viewModel.comprehensiveResult.extensionsList) { ext in
                    ExtensionRow(extension: ext)
                }
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.bottom, Constants.bottomPadding)
        }
    }
}

// MARK: - Extension Row

private struct ExtensionRow: View {
    let `extension`: ImportedExtension

    var body: some View {
        HStack(spacing: 12) {
            extensionIcon
            extensionInfo
            Spacer()
            statusBadge
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.vertical, Constants.verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: Constants.cornerRadius)
                .fill(Color.primary.opacity(0.03)),
        )
    }

    private var extensionIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.purple.opacity(0.15))
                .frame(width: Constants.iconBoxSize, height: Constants.iconBoxSize)

            Image(systemName: "puzzlepiece.extension")
                .font(.title3)
                .foregroundStyle(.purple)
        }
    }

    private var extensionInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(`extension`.name)
                .font(.body)
                .fontWeight(.medium)

            HStack(spacing: 8) {
                if let version = `extension`.version {
                    Text("v\(version)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Text(`extension`.id)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if let description = `extension`.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }

    private var statusBadge: some View {
        Text(`extension`.isEnabled ? "Enabled" : "Disabled")
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(`extension`.isEnabled ? Color.green.opacity(0.15) : Color.secondary.opacity(0.15)),
            )
            .foregroundStyle(`extension`.isEnabled ? .green : .secondary)
    }

    private enum Constants {
        static let horizontalPadding: CGFloat = 12
        static let verticalPadding: CGFloat = 10
        static let cornerRadius: CGFloat = 10
        static let iconBoxSize: CGFloat = 40
    }
}
