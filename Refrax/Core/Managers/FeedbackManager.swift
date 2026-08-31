import AppKit
import Foundation

/// Manages feedback composition, attachment collection, and submission.
///
/// Coordinates the feedback workflow: collecting system information,
/// pre-populating saved contact details, auto-attaching log files,
/// and submitting the composed feedback through ``FeedbackSubmissionService``.
///
/// ## Lifecycle
///
/// 1. Call ``prepareForPresentation()`` before showing the feedback window
/// 2. User fills in form fields (bound to published properties)
/// 3. Call ``submit()`` to validate and send
/// 4. Call ``reset()`` to clear state for next use
@Observable
@MainActor
final class FeedbackManager {
    // MARK: - Form State

    var name: String = ""
    var email: String = ""
    var subject: String = ""
    var body: String = ""
    var category: FeedbackCategory = .general
    var attachments: [FeedbackAttachment] = []

    // MARK: - Submission State

    var isSubmitting = false
    var submissionError: String?
    var didSubmitSuccessfully = false

    /// Confirmation copy for the success screen, tailored to where the
    /// feedback went (GitHub issue vs. the crash backend).
    var successMessage = "Your report has been saved and will help improve Refrax."

    // MARK: - Collected Data

    @ObservationIgnored
    var systemInfo: SystemInfo?

    // MARK: - Dependencies

    @ObservationIgnored
    unowned let settings: BrowserSettings

    @ObservationIgnored
    unowned var browserState: BrowserState!

    @ObservationIgnored
    unowned var extensionManager: ExtensionManager!

    // MARK: - Initialization

    init(settings: BrowserSettings) {
        self.settings = settings
    }

    // MARK: - Public Methods

    /// Prepares the manager for presenting the feedback window.
    ///
    /// Collects system information, pre-populates name and email from
    /// saved settings, and auto-attaches available log files. If a crash
    /// was detected, also attaches crash reports and sets the category
    /// to ``FeedbackCategory/crash``.
    func prepareForPresentation() async {
        let tabCount = browserState.spaces.flatMap(\.tabs).count
        let spaceCount = browserState.spaces.count
        let extensionCount = extensionManager.installedExtensions.count
        systemInfo = SystemInfo.collect(
            tabCount: tabCount,
            spaceCount: spaceCount,
            extensionCount: extensionCount,
        )
        name = settings.feedbackName
        email = settings.feedbackEmail

        attachments.removeAll()
        let logURLs = await PersistentLogWriter.shared.allLogFileURLs()
        for url in logURLs {
            if let attachment = makeAttachment(from: url, isAutoAttached: true) {
                attachments.append(attachment)
            }
        }

        if CrashMonitor.didCrashPreviously() {
            category = .crash
            let crashReports = CrashMonitor.collectCrashReports()
            for url in crashReports {
                if let attachment = makeAttachment(from: url, isAutoAttached: true) {
                    attachments.append(attachment)
                }
            }
        }
    }

    /// Adds a user-selected file as an attachment.
    ///
    /// - Parameter url: The file URL to attach.
    func addAttachment(from url: URL) {
        guard let attachment = makeAttachment(from: url, isAutoAttached: false) else { return }
        attachments.append(attachment)
    }

    /// Removes the attachment at the specified index.
    ///
    /// - Parameter index: The index of the attachment to remove.
    func removeAttachment(at index: Int) {
        guard attachments.indices.contains(index) else { return }
        attachments.remove(at: index)
    }

    /// Validates and submits the feedback.
    ///
    /// On success, saves the user's name and email to settings for
    /// future pre-population and sets ``didSubmitSuccessfully`` to `true`.
    /// On failure, populates ``submissionError`` with a description.
    func submit() async {
        guard !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            submissionError = "Please enter a subject."
            return
        }

        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            submissionError = "Please describe your feedback."
            return
        }

        isSubmitting = true
        submissionError = nil

        let selectedAttachments = attachments.filter(\.isSelected)

        let payload = FeedbackSubmissionService.FeedbackPayload(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            email: email.trimmingCharacters(in: .whitespacesAndNewlines),
            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
            body: body,
            category: category.apiValue,
            systemInfo: systemInfo,
            attachmentURLs: selectedAttachments.map(\.url),
        )

        settings.feedbackName = name
        settings.feedbackEmail = email

        // Crash reports go to the backend; everything else becomes a GitHub
        // issue the user reviews and submits under their own account.
        if category == .crash {
            do {
                try await FeedbackSubmissionService.submit(payload)
                successMessage = "Your report has been saved and will help improve Refrax."
                didSubmitSuccessfully = true
            } catch {
                submissionError = error.localizedDescription
            }
        } else {
            if let url = FeedbackIssueComposer.issueURL(for: payload) {
                NSWorkspace.shared.open(url)
                successMessage = "GitHub is opening with your report pre-filled — review it and click “Submit new issue” to finish."
                didSubmitSuccessfully = true
            } else {
                submissionError = "Couldn't open GitHub to file your report. Please try again."
            }
        }

        isSubmitting = false
    }

    /// Resets all form and submission state for a fresh feedback session.
    func reset() {
        name = ""
        email = ""
        subject = ""
        body = ""
        category = .general
        attachments = []
        isSubmitting = false
        submissionError = nil
        didSubmitSuccessfully = false
        successMessage = "Your report has been saved and will help improve Refrax."
        systemInfo = nil
    }

    // MARK: - Private

    private func makeAttachment(from url: URL, isAutoAttached: Bool) -> FeedbackAttachment? {
        let fm = FileManager.default
        guard let attributes = try? fm.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? Int64
        else {
            return nil
        }

        return FeedbackAttachment(
            url: url,
            filename: url.lastPathComponent,
            fileSize: fileSize,
            isAutoAttached: isAutoAttached,
            isSelected: true,
        )
    }
}
