import SwiftUI

/// View for selecting a browser profile when multiple profiles exist.
///
/// Some browsers (like Chrome and Firefox) support multiple user profiles,
/// each with their own set of data. This view allows the user to
/// choose which profile to import from.
struct ProfileSelectionView: View {
    @Bindable var viewModel: ImportWizardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.sectionSpacing) {
            headerSection
            profileList
        }
    }

    private enum Constants {
        static let sectionSpacing: CGFloat = 12
        static let rowSpacing: CGFloat = 8
        static let horizontalPadding: CGFloat = 20
        static let topPadding: CGFloat = 16
        static let bottomPadding: CGFloat = 16
    }
}

// MARK: - Sections

private extension ProfileSelectionView {
    var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let browser = viewModel.selectedBrowser {
                HStack(spacing: 8) {
                    if let icon = browser.iconImage {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 24, height: 24)
                    }
                    Text(browser.displayName)
                        .font(.headline)
                }
            }

            Text("Multiple profiles found. Select one to import from:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.top, Constants.topPadding)
    }

    var profileList: some View {
        ScrollView {
            LazyVStack(spacing: Constants.rowSpacing) {
                ForEach(viewModel.profiles) { profile in
                    ProfileRow(profile: profile) {
                        viewModel.selectProfile(profile)
                    }
                }
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.bottom, Constants.bottomPadding)
        }
    }
}

// MARK: - Profile Row

/// A row displaying a browser profile option.
private struct ProfileRow: View {
    let profile: BrowserProfile
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Constants.iconSpacing) {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: Constants.iconSize, height: Constants.iconSize)

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.body)

                    Text(profile.path.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.vertical, Constants.verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: Constants.cornerRadius)
                    .fill(Color.primary.opacity(0.05)),
            )
        }
        .buttonStyle(.plain)
    }

    private enum Constants {
        static let iconSpacing: CGFloat = 12
        static let iconSize: CGFloat = 32
        static let horizontalPadding: CGFloat = 12
        static let verticalPadding: CGFloat = 10
        static let cornerRadius: CGFloat = 8
    }
}
