import SwiftUI

/// Second onboarding screen: alpha disclaimer with diagnostics notice and contact info.
struct OnboardingAlphaInfoView: View {
    @Environment(BrowserSettings.self) private var settings

    let onNext: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "testtube.2")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("Welcome to the Alpha")
                    .font(.title)
                    .fontWeight(.semibold)

                VStack(alignment: .leading, spacing: 12) {
                    infoCard(
                        title: "What to expect",
                        icon: "sparkles",
                        description: "This is an early build — most features work well, but expect rough edges. Extensions require manual installation and are experimental; password manager extensions won't work. Please report anything that feels off."
                    )

                    infoCard(
                        title: "Diagnostics are always on",
                        icon: "heart.fill",
                        description: "To help improve Refrax during the alpha, anonymous diagnostics and crash reports are sent automatically.\n\n\(TelemetryService.heartbeatDescription)\n\n\(TelemetryService.crashReportDescription)\n\nThis will become optional in a future release."
                    )

                    infoCard(
                        title: "Get in touch",
                        icon: "bubble.left.and.bubble.right.fill",
                        description: "Share feedback directly from the browser (⌘T) or reach out:\n\nfeedback@refrax.website\n@kageroumado on X\nkagerou.glass · refrax.browser\n\nLove it? Tell your friends to sign up for the alpha."
                    )
                }
                .frame(maxWidth: 380)

                Button {
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
        .onAppear {
            if Constants.App.releaseChannel.forceTelemetry {
                settings.telemetryEnabled = true
            }
        }
    }

    private func infoCard(title: String, icon: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.headline)

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
