import SwiftUI
import UniformTypeIdentifiers

/// View for selecting a browser to import data from.
///
/// Displays a list of installed browsers with their icons and names.
/// Users can also choose to import from an HTML file.
struct BrowserSelectionView: View {
    @Bindable var viewModel: ImportWizardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.sectionSpacing) {
            Text("Select a browser to import from:")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Constants.horizontalPadding)
                .padding(.top, Constants.topPadding)

            ScrollView {
                LazyVStack(spacing: Constants.rowSpacing) {
                    ForEach(viewModel.installedBrowsers) { browser in
                        BrowserRow(browser: browser) {
                            viewModel.selectBrowser(browser)
                        }
                    }

                    Divider()
                        .padding(.vertical, Constants.dividerPadding)

                    BrowserRow(browser: .htmlFile) {
                        showHTMLFilePicker()
                    }
                }
                .padding(.horizontal, Constants.horizontalPadding)
                .padding(.bottom, Constants.bottomPadding)
            }
        }
    }

    private enum Constants {
        static let sectionSpacing: CGFloat = 12
        static let rowSpacing: CGFloat = 8
        static let horizontalPadding: CGFloat = 20
        static let topPadding: CGFloat = 16
        static let bottomPadding: CGFloat = 16
        static let dividerPadding: CGFloat = 8
    }

    private func showHTMLFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select an HTML bookmarks file exported from another browser"
        panel.prompt = "Import"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        viewModel.htmlFileURL = url
        viewModel.selectedBrowser = .htmlFile
        viewModel.currentStep = .importing
    }
}

// MARK: - Browser Row

/// A row displaying a browser option in the selection list.
struct BrowserRow: View {
    let browser: ThirdPartyBrowser
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Constants.iconSpacing) {
                browserIcon
                    .frame(width: Constants.iconSize, height: Constants.iconSize)

                Text(browser.displayName)
                    .font(.body)

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

    @ViewBuilder
    private var browserIcon: some View {
        if let icon = browser.iconImage {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Image(systemName: "doc.text")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}
