import SwiftUI

/// View displaying the progress of an ongoing import operation.
///
/// Shows a progress bar and status message while data is being imported
/// from the selected browser. The import is started by the parent view
/// and this view just displays the progress.
struct ImportProgressView: View {
    @Bindable var viewModel: ImportWizardViewModel

    var body: some View {
        VStack(spacing: Constants.verticalSpacing) {
            Spacer()

            progressIndicator
            statusText
            progressBar

            Spacer()
        }
        .padding(Constants.padding)
    }

    private enum Constants {
        static let verticalSpacing: CGFloat = 16
        static let padding: CGFloat = 40
        static let iconSize: CGFloat = 48
        static let progressBarWidth: CGFloat = 300
    }
}

// MARK: - Components

private extension ImportProgressView {
    var progressIndicator: some View {
        Group {
            if viewModel.progress < 1.0 {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(height: Constants.iconSize)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: Constants.iconSize))
                    .foregroundStyle(.green)
            }
        }
    }

    var statusText: some View {
        VStack(spacing: 4) {
            if let browser = viewModel.selectedBrowser {
                Text("Importing from \(browser.displayName)")
                    .font(.headline)
            }

            Text(viewModel.progressMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    var progressBar: some View {
        ProgressView(value: viewModel.progress)
            .frame(width: Constants.progressBarWidth)
    }
}
