import SwiftUI

/// The telemetry choice: onboarding's second screen, and the one-time prompt
/// for installs that finished onboarding without choosing.
///
/// ``TelemetryTier/recommended`` is preselected; the choice is saved when the
/// user continues.
struct OnboardingTelemetryView: View {
    @Environment(BrowserSettings.self) private var settings

    /// A line shown above the explanation, for the one-time prompt.
    var note: String?
    let onNext: () -> Void

    @State private var tier: TelemetryTier = .recommended

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    if let note {
                        Text(note)
                            .font(.callout)
                            .fontWeight(.medium)
                            .multilineTextAlignment(.center)
                    }

                    Text("Your call on telemetry")
                        .font(.title)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)

                    Text("Refrax is free and made by one person. Anonymous counts tell me whether people use it, and crash reports tell me what to fix. Pick what you\u{2019}re comfortable with.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    TelemetryTierPicker(tier: $tier)
                    TelemetryDisclosureView(tier: tier)
                }
                .padding(12)
                .frame(maxWidth: 400, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

                Text("You can change this any time in Settings \u{2192} Privacy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    settings.telemetryTier = tier
                    onNext()
                } label: {
                    Text("Continue")
                        .frame(width: 120)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(40)
        }
    }
}

#Preview {
    OnboardingTelemetryView {}
        .environment(BrowserSettings())
        .frame(width: 520, height: 720)
}
