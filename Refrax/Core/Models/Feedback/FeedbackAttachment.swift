import Foundation

/// A file attachment for a feedback submission.
///
/// Attachments can be auto-attached (log files, crash reports) or manually
/// added by the user. Auto-attached files are pre-selected but can be
/// deselected before submission.
nonisolated struct FeedbackAttachment: Identifiable, Equatable, Sendable {
    let id = UUID()
    let url: URL
    let filename: String
    let fileSize: Int64
    let isAutoAttached: Bool
    var isSelected: Bool
}
