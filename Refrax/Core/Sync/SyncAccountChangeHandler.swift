import CloudKit
import SwiftData

/// Manages UI state for iCloud account transitions (sign-out, switch, sign-back-in).
///
/// When the sync engine detects an account change, this handler determines whether
/// user interaction is required and presents the appropriate prompt. The user's choice
/// is delivered back to the caller via a `CheckedContinuation`.
///
/// ## Flow
///
/// 1. `SyncCoordinator` receives `.accountChange` from CKSyncEngine
/// 2. Coordinator calls ``promptForAccountAction(event:previousAccountID:)`` (crosses to MainActor)
/// 3. For sign-out and account switch: handler presents a sheet asking keep/remove
/// 4. For sign-back-in to the same account: returns `.signedBackIn` immediately (no UI)
/// 5. The coordinator uses the result to wipe sync metadata, optionally delete local data, or resume
///
/// ## Thread Safety
///
/// `@MainActor` because it drives SwiftUI sheet presentation. The continuation is stored
/// until the user taps a button, then resumed exactly once.
@MainActor @Observable
final class SyncAccountChangeHandler {

    // MARK: - Types

    /// The event that triggered the account change prompt.
    enum AccountEvent {
        /// User signed out of iCloud entirely.
        case signedOut
        /// User switched to a different iCloud account.
        case switchedAccount
    }

    /// The user's response to the account change prompt.
    enum AccountAction: Sendable {
        /// Keep local data, wipe sync metadata only.
        case keepData
        /// Delete all synced models, wipe sync metadata.
        case removeData
        /// The user signed back into the same account — no action needed.
        case signedBackIn
    }

    // MARK: - Observable State

    /// Whether the account change sheet is currently presented.
    private(set) var isPresentingSheet = false

    /// The event type driving the current prompt, if any.
    private(set) var activeEvent: AccountEvent?

    // MARK: - Private State

    private var pendingContinuation: CheckedContinuation<AccountAction, Never>?

    // MARK: - Public API

    /// Evaluates an account change and returns the appropriate action.
    ///
    /// For sign-out and account switch, this presents a sheet and suspends until the user
    /// chooses. For sign-back-in to the same account, returns immediately.
    ///
    /// - Parameters:
    ///   - event: The type of account change detected by CKSyncEngine.
    ///   - previousAccountID: The `SyncState.accountID` before the change, used to detect
    ///     same-account sign-back-in.
    ///   - currentAccountID: The new account's record name, if available.
    /// - Returns: The action to take in response to the account change.
    func promptForAccountAction(
        event: CKSyncEngine.Event.AccountChange,
        previousAccountID: String?
    ) async -> AccountAction {
        switch event.changeType {
        case .signIn(let currentUser):
            if currentUser.recordName == previousAccountID {
                Logger.info("Same account signed back in — resuming sync", category: Logger.sync)
                return .signedBackIn
            }
            // New account after being signed out — treat as sign-in with no prior data conflict.
            // If there was a previous account, the sign-out or switch event handles the prompt.
            Logger.info("New account signed in", category: Logger.sync)
            return .signedBackIn

        case .signOut:
            Logger.info("iCloud account signed out — prompting user", category: Logger.sync)
            return await presentSheet(for: .signedOut)

        case .switchAccounts(_, _):
            Logger.info("iCloud account switched — prompting user", category: Logger.sync)
            return await presentSheet(for: .switchedAccount)

        @unknown default:
            Logger.warning("Unknown account change type — treating as sign-out", category: Logger.sync)
            return await presentSheet(for: .signedOut)
        }
    }

    /// Called by the UI when the user makes their choice on the account change sheet.
    ///
    /// Resumes the suspended continuation from ``promptForAccountAction(event:previousAccountID:)``.
    func handleUserChoice(_ action: AccountAction) {
        isPresentingSheet = false
        activeEvent = nil

        guard let continuation = pendingContinuation else {
            Logger.error("handleUserChoice called with no pending continuation", category: Logger.sync)
            return
        }
        pendingContinuation = nil
        continuation.resume(returning: action)
    }

    // MARK: - Private

    private func presentSheet(for event: AccountEvent) async -> AccountAction {
        activeEvent = event
        isPresentingSheet = true

        return await withCheckedContinuation { continuation in
            self.pendingContinuation = continuation
        }
    }
}
