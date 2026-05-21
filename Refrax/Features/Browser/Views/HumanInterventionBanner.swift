import SwiftUI

/// Banner overlay shown when a DSL program has requested human intervention.
///
/// Appears at the top of the content area when the interpreter executes
/// `request_human "description"`. The user reads the description, performs
/// the requested action (e.g., solving a captcha), then presses "Done"
/// to resume program execution.
struct HumanInterventionBanner: View {
    @Environment(HumanInterventionManager.self) private var humanIntervention

    var body: some View {
        if let request = humanIntervention.activePendingRequest {
            bannerContent(for: request)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(duration: 0.3), value: request.id)
        }
    }

    private func bannerContent(for request: HumanInterventionManager.PendingRequest) -> some View {
        HStack(spacing: Constants.spacing) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: Constants.iconSize))
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: Constants.textSpacing) {
                Text("Agent needs help")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(request.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button {
                humanIntervention.resolve(id: request.id)
            } label: {
                Text("Done")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

            Button {
                humanIntervention.cancel(id: request.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.vertical, Constants.verticalPadding)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Constants.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: Constants.cornerRadius)
                .strokeBorder(.orange.opacity(0.3), lineWidth: 1)
        }
        .padding(.horizontal, Constants.outerPadding)
        .padding(.top, Constants.topPadding)
    }
}

// MARK: - Constants

private extension HumanInterventionBanner {
    enum Constants {
        static let spacing: CGFloat = 12
        static let textSpacing: CGFloat = 2
        static let iconSize: CGFloat = 18
        static let horizontalPadding: CGFloat = 16
        static let verticalPadding: CGFloat = 12
        static let cornerRadius: CGFloat = 12
        static let outerPadding: CGFloat = 16
        static let topPadding: CGFloat = 12
    }
}
