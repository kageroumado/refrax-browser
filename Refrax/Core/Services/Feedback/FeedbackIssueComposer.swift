import Foundation

/// Turns feedback the user composed in Refrax into a pre-filled GitHub
/// "new issue" URL. Opening it lets the user review and submit the issue on
/// github.com under their own account — no API token or server round-trip.
///
/// Used for bug reports, feature requests, and general feedback. Crash reports
/// keep going to the backend through ``FeedbackSubmissionService``.
nonisolated enum FeedbackIssueComposer: Sendable {
    /// The public repository issues are filed against.
    static let repositorySlug = "kageroumado/refrax-browser"

    /// Builds the pre-filled issue URL, or `nil` if the components can't form a
    /// valid URL.
    static func issueURL(for payload: FeedbackSubmissionService.FeedbackPayload) -> URL? {
        var components = URLComponents(string: "https://github.com/\(repositorySlug)/issues/new")

        var queryItems = [
            URLQueryItem(name: "title", value: payload.subject),
            URLQueryItem(name: "body", value: body(for: payload)),
        ]
        if let label = label(for: payload.category) {
            queryItems.append(URLQueryItem(name: "labels", value: label))
        }
        components?.queryItems = queryItems

        return components?.url
    }

    /// Maps a feedback category to a default GitHub label. `bug` and
    /// `enhancement` ship with every repository; other categories go unlabeled.
    private static func label(for category: String) -> String? {
        switch category {
        case "bug": "bug"
        case "feature": "enhancement"
        default: nil
        }
    }

    private static func body(for payload: FeedbackSubmissionService.FeedbackPayload) -> String {
        var sections = [payload.body]

        if let systemInfo = payload.systemInfo {
            sections.append("---")
            sections.append("### System Information\n\n\(systemInfo.markdownReport)")
        }

        sections.append("_Drag any logs or screenshots into this issue after it opens if they help._")

        return sections.joined(separator: "\n\n")
    }
}
