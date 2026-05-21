import SwiftUI

/// Delays content visibility until a grace period expires.
/// Shows immediately if `shouldDelay` is false, otherwise waits for the grace period.
struct GracePeriodModifier: ViewModifier {
    @State private var showContent = false
    @State private var delayTask: Task<Void, Never>?

    let shouldDelay: Bool
    let gracePeriod: Duration

    func body(content: Content) -> some View {
        content
            .opacity(showContent ? 1 : 0)
            .onChange(of: shouldDelay, initial: true) { _, shouldDelay in
                delayTask?.cancel()
                if shouldDelay {
                    delayTask = Task {
                        try? await Task.sleep(for: gracePeriod)
                        guard !Task.isCancelled else { return }
                        showContent = true
                    }
                } else {
                    showContent = true
                }
            }
            .onDisappear { delayTask?.cancel() }
    }
}

extension View {
    /// Delays the appearance of content until after a grace period.
    ///
    /// Use this to prevent brief flashes of fallback content when primary content
    /// is expected to arrive shortly.
    ///
    /// - Parameters:
    ///   - shouldDelay: Whether to delay showing the content.
    ///   - delay: How long to wait before showing content. Defaults to 400ms.
    /// - Returns: A view that delays its appearance when `shouldDelay` is true.
    func delayedAppearance(
        shouldDelay: Bool,
        delay: Duration = .milliseconds(400),
    ) -> some View {
        modifier(GracePeriodModifier(shouldDelay: shouldDelay, gracePeriod: delay))
    }
}
