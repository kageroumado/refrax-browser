import Foundation

/// Manages pending human intervention requests from the program interpreter.
///
/// When a DSL program executes `request_human "description"`, the interpreter
/// suspends via a `CheckedContinuation` and registers the request here.
/// The UI shows a banner prompting the user, and calling ``resolve(id:)``
/// resumes execution. ``cancel(id:)`` aborts the suspended command with an error.
///
/// Thread safety: all access is `@MainActor` — the interpreter, UI, and control
/// server all run on main.
@MainActor @Observable
final class HumanInterventionManager {
    /// A pending request waiting for human intervention.
    struct PendingRequest: Identifiable {
        let id: UUID
        let token: String
        let description: String
        let continuation: CheckedContinuation<Void, any Error>
        let createdAt: Date
    }

    private(set) var pendingRequests: [PendingRequest] = []

    /// The most recent pending request, displayed in the UI banner.
    ///
    /// Derived from ``pendingRequests`` — SwiftUI tracks this because
    /// `@Observable` observes changes to the backing stored property.
    var activePendingRequest: PendingRequest? {
        pendingRequests.last
    }

    /// Whether any human intervention request is pending.
    var hasPendingRequest: Bool {
        !pendingRequests.isEmpty
    }

    /// Registers a new human intervention request.
    ///
    /// Called by the interpreter inside `withCheckedThrowingContinuation`.
    /// The continuation is stored until the user resolves or cancels the request.
    ///
    /// - Parameters:
    ///   - id: Unique identifier for the request.
    ///   - token: Wire-format token for CLI resume messages.
    ///   - description: Human-readable description of what's needed.
    ///   - continuation: The suspended continuation to resume later.
    func register(
        id: UUID,
        token: String,
        description: String,
        continuation: CheckedContinuation<Void, any Error>,
    ) {
        let request = PendingRequest(
            id: id,
            token: token,
            description: description,
            continuation: continuation,
            createdAt: Date(),
        )
        pendingRequests.append(request)
    }

    /// Resumes the interpreter successfully after the human has finished.
    func resolve(id: UUID) {
        guard let index = pendingRequests.firstIndex(where: { $0.id == id }) else { return }
        let request = pendingRequests.remove(at: index)
        request.continuation.resume()
    }

    /// Resumes the interpreter by token (used by CLI `resumeProgram`).
    func resolve(token: String) {
        guard let index = pendingRequests.firstIndex(where: { $0.token == token }) else { return }
        let request = pendingRequests.remove(at: index)
        request.continuation.resume()
    }

    /// Cancels a pending request, resuming the interpreter with an error.
    func cancel(id: UUID) {
        guard let index = pendingRequests.firstIndex(where: { $0.id == id }) else { return }
        let request = pendingRequests.remove(at: index)
        request.continuation.resume(throwing: HumanInterventionError.cancelled)
    }

    /// Cancels all pending requests (e.g., on program timeout).
    func cancelAll() {
        let requests = pendingRequests
        pendingRequests.removeAll()
        for request in requests {
            request.continuation.resume(throwing: HumanInterventionError.cancelled)
        }
    }
}

// MARK: - Errors

enum HumanInterventionError: LocalizedError {
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cancelled: "Human intervention request was cancelled"
        }
    }
}
