import Foundation

/// Beta build expiration validation.
///
/// Ensures beta builds expire automatically to prevent outdated versions from
/// being used and encourage testers to grab fresh builds.
///
/// ## Design
///
/// The killswitch uses arithmetic rather than conditional branching:
/// 1. Compute seconds remaining until expiry
/// 2. Derive a value that's 1 before expiry, 0 after
/// 3. Use that value as a divisor — divide-by-zero crashes after expiry
///
/// This approach is harder to patch than a simple `if expired { exit }` because
/// the expiry logic *produces* a value rather than just checking one. A reverser
/// would need to understand the arithmetic and patch the divisor computation,
/// not just NOP out a branch instruction.
///
/// This won't stop a determined reverser, but that's not the threat model.
/// The goal is preventing casual redistribution of stale builds.
enum BetaExpiry {
    // MARK: - Configuration

    /// Expiry date: two weeks from last publish.
    /// Automatically updated by `refraxpublish` on each release.
    // PUBLISH-EXPIRY: Do not modify manually — updated by refraxpublish
    private static let expiryDateString = "2026-05-28T00:00:00Z"

    private static let expiryDate: Date = {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: expiryDateString)!
    }()

    // MARK: - Validation

    /// Validates that the beta period has not expired.
    ///
    /// Call this at the very beginning of app initialization.
    /// If the build has expired, the app crashes with an arithmetic error.
    @inline(never)
    static func validateOrTerminate() {
        let remaining = expiryDate.timeIntervalSinceNow

        // Before expiry: remaining > 0 → token = 1
        // After expiry: remaining ≤ 0 → token = 0
        //
        // The double-conversion through max() prevents simple optimization.
        // A compiler can't easily prove this is just a comparison.
        let positiveRemaining = max(remaining, 0)
        let normalizer = max(remaining, 1)
        let token = Int(positiveRemaining / normalizer)

        // Arithmetic crash when token is 0
        // The compiler emits actual division, not a branch
        _ = 1 / token
    }
}
