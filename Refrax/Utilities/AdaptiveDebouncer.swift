import Foundation

/// Debounces actions with adaptive delay based on typing speed and input length.
///
/// Combines two signals:
/// 1. **Input length**: Short strings (1-2 chars) get longer delays
/// 2. **Typing speed**: Fast typing → wait longer, slow typing → search sooner
///
/// This reduces useless searches (e.g., "a", "ap") while staying responsive
/// when the user knows what they want or pauses to read results.
///
/// ## Research References
/// - adaQAC (SIGIR 2015): Dwell time as implicit negative feedback
/// - IEEE 2025: Acceptance-rate feedback for adaptive suggestion timing
/// - Algolia: 200ms optimal, >300ms degrades UX
///
/// ## Usage
/// ```swift
/// let debouncer = AdaptiveDebouncer()
///
/// func onSearchTextChanged(_ text: String) {
///     debouncer.debounce(for: text) { [weak self] in
///         await self?.performSearch(text)
///     }
/// }
/// ```
@MainActor
final class AdaptiveDebouncer {
    private var task: Task<Void, Never>?
    private var lastKeystrokeTime: ContinuousClock.Instant?

    private enum Thresholds {
        // Base delays by input length
        static let singleChar: Duration = .milliseconds(350)
        static let twoChars: Duration = .milliseconds(200)
        static let threeOrMore: Duration = .milliseconds(100)

        // Typing speed thresholds
        static let fastTypingInterval: Duration = .milliseconds(150) // < 150ms = fast
        static let slowTypingInterval: Duration = .milliseconds(400) // > 400ms = slow/paused

        // Bounds (never go below/above these)
        static let minDelay: Duration = .milliseconds(50)
        static let maxDelay: Duration = .milliseconds(400)
    }

    /// Cancels any pending action and schedules a new one with adaptive delay.
    func debounce(for input: String, action: @escaping @MainActor () async -> Void) {
        task?.cancel()

        let now = ContinuousClock.now
        let keystrokeInterval = lastKeystrokeTime.map { now - $0 }
        lastKeystrokeTime = now

        let delay = calculateDelay(inputLength: input.count, keystrokeInterval: keystrokeInterval)

        task = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await action()
        }
    }

    /// Cancels any pending action and resets typing speed tracking.
    func cancel() {
        task?.cancel()
        task = nil
        lastKeystrokeTime = nil
    }

    /// Calculates adaptive delay based on input length and typing speed.
    private func calculateDelay(inputLength: Int, keystrokeInterval: Duration?) -> Duration {
        // Base delay from input length
        let baseDelay: Duration = switch inputLength {
        case 0: .zero
        case 1: Thresholds.singleChar
        case 2: Thresholds.twoChars
        default: Thresholds.threeOrMore
        }

        guard inputLength > 0 else { return .zero }

        // Adjust based on typing speed
        guard let interval = keystrokeInterval else {
            // First keystroke - use base delay
            return baseDelay
        }

        let speedMultiplier = if interval < Thresholds.fastTypingInterval {
            // Fast typing (< 150ms) → increase delay by 50%
            1.5
        } else if interval > Thresholds.slowTypingInterval {
            // Slow typing / paused (> 400ms) → reduce delay by 50%
            0.5
        } else {
            // Normal typing speed → use base delay
            1.0
        }

        let adjustedDelay = baseDelay * speedMultiplier

        // Clamp to bounds
        return min(max(adjustedDelay, Thresholds.minDelay), Thresholds.maxDelay)
    }
}
