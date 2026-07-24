import SwiftUI

/// First onboarding screen: welcome branding.
struct OnboardingWelcomeView: View {
    @Environment(BrowserSettings.self) private var settings

    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(nsImage: NSApp.applicationIconImage!)
                .resizable()
                .frame(width: 128, height: 128)

            VStack(spacing: 8) {
                Text("Refrax")
                    .font(.system(size: 36, weight: .bold, design: .rounded))

                Text("A browser with soul.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                settings.isActivated = true
                onNext()
            } label: {
                Text("Get Started")
                    .frame(width: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
        .padding(40)
    }
}
