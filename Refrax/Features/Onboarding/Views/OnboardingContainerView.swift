import SwiftUI

/// Container for the multi-step onboarding flow.
///
/// Manages step transitions and provides consistent layout.
struct OnboardingContainerView: View {
    let onCompleted: () -> Void

    @State private var step: OnboardingStep = .welcome

    enum OnboardingStep: Int, CaseIterable {
        case welcome
        case alphaInfo
        case `import`
    }

    var body: some View {
        Group {
            switch step {
            case .welcome:
                OnboardingWelcomeView {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        step = .alphaInfo
                    }
                }
            case .alphaInfo:
                OnboardingAlphaInfoView {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        step = .import
                    }
                }
            case .import:
                OnboardingImportView(onCompleted: onCompleted)
            }
        }
        .frame(width: 520, height: 720)
        .background(Color(.windowBackgroundColor))
    }
}
