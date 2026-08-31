import SwiftUI

/// Displays the result of a feedback submission.
///
/// Shows a success state with a thank-you message, or an error state
/// with the failure description and retry/close options.
struct FeedbackConfirmationView: View {
    @Environment(FeedbackManager.self) private var manager

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            if manager.didSubmitSuccessfully {
                successContent
            } else if let error = manager.submissionError {
                errorContent(error)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    // MARK: - Success

    private var successContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)

            Text("Thanks for your feedback")
                .font(.system(size: Constants.Typography.headerSize, weight: .semibold))

            Text(manager.successMessage)
                .font(.system(size: Constants.Typography.bodySize))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            closeButton
                .padding(.top, 4)
        }
    }

    // MARK: - Error

    private func errorContent(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.orange)

            Text("Couldn't send feedback")
                .font(.system(size: Constants.Typography.headerSize, weight: .semibold))

            Text(error)
                .font(.system(size: Constants.Typography.bodySize))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            HStack(spacing: 8) {
                Button("Try Again") {
                    manager.submissionError = nil
                    manager.didSubmitSuccessfully = false
                }
                .buttonStyle(.bordered)

                closeButton
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Shared

    private var closeButton: some View {
        Button("Close") {
            NSApp.keyWindow?.close()
        }
        .keyboardShortcut(.cancelAction)
    }
}
