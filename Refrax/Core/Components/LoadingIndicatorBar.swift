import SwiftUI

/// A reusable loading progress indicator bar.
///
/// This component displays a capsule-shaped progress bar that:
/// - Animates width based on loading progress
/// - Shows a minimum visible width when loading starts
/// - Fades out smoothly when loading completes
///
/// ## Usage
///
/// Apply as an overlay at the bottom of a container:
///
/// ```swift
/// SomeView()
///     .overlay(alignment: .bottom) {
///         LoadingIndicatorBar(isLoading: webPage.isLoading, progress: webPage.estimatedProgress)
///     }
/// ```
struct LoadingIndicatorBar: View {
    /// Whether the content is currently loading.
    let isLoading: Bool

    /// The current loading progress (0.0 to 1.0).
    let progress: Double

    /// The bar height. Defaults to 2pt.
    var height: CGFloat = 2

    /// Horizontal padding from container edges.
    var horizontalInset: CGFloat = 0

    @State private var isVisible = false
    @State private var fadeOutTask: Task<Void, Never>?

    private enum Constants {
        static let minimumProgress: Double = 0.1
        static let completionAnimationDuration: Double = 0.15
        static let fadeOutDelay: Double = 0.1
        static let fadeOutDuration: Double = 0.2
    }

    /// The effective progress value, ensuring a minimum visible width when loading.
    ///
    /// Returns 1.0 when loading completes to animate the bar to full width before fading.
    private var effectiveProgress: Double {
        if isLoading {
            return max(progress, Constants.minimumProgress)
        }
        return 1.0
    }

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.appAccentColor)
                .frame(width: geo.size.width * effectiveProgress)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: height)
        .padding(.horizontal, horizontalInset)
        .opacity(isVisible ? 1 : 0)
        .animation(.easeOut(duration: Constants.completionAnimationDuration), value: effectiveProgress)
        .animation(
            .easeInOut(duration: Constants.fadeOutDuration)
                .delay(isVisible ? 0 : Constants.fadeOutDelay),
            value: isVisible,
        )
        .onAppear {
            syncVisibility()
        }
        .onChange(of: isLoading) { _, _ in
            syncVisibility()
        }
    }

    /// Synchronizes visibility state with loading state.
    ///
    /// This is called both on appear and on change to handle cases where
    /// SwiftUI's observation doesn't trigger `.onChange` (e.g., when accessing
    /// properties through dictionary lookups on @Observable objects).
    private func syncVisibility() {
        fadeOutTask?.cancel()

        if isLoading {
            isVisible = true
        } else if isVisible {
            // Delay fade-out to allow progress bar to animate to 100%
            fadeOutTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(
                    Constants.completionAnimationDuration + Constants.fadeOutDelay,
                ))
                guard !Task.isCancelled else { return }
                isVisible = false
            }
        }
    }
}
