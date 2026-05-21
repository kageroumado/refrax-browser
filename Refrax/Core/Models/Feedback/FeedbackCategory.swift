/// The type of feedback being submitted.
nonisolated enum FeedbackCategory: String, CaseIterable, Sendable {
    case bug = "Bug Report"
    case feature = "Feature Request"
    case general = "General Feedback"
    case crash = "Crash Report"

    /// Short display name for compact UI (category picker).
    var displayName: String {
        switch self {
        case .bug: "Bug"
        case .feature: "Feature"
        case .general: "General"
        case .crash: "Crash"
        }
    }

    /// API value sent to the feedback server.
    var apiValue: String {
        switch self {
        case .bug: "bug"
        case .feature: "feature"
        case .general: "general"
        case .crash: "crash"
        }
    }
}
