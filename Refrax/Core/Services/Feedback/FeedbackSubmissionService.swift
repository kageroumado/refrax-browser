import Foundation

/// Submits crash reports to the self-hosted backend.
///
/// Sends form data and file attachments as a multipart POST request.
/// If the server is unreachable, falls back to saving locally so no
/// user input is lost. Bug reports, feature requests, and general
/// feedback take the GitHub route via ``FeedbackIssueComposer`` instead.
nonisolated enum FeedbackSubmissionService: Sendable {
    /// The complete feedback payload sent to the backend.
    nonisolated struct FeedbackPayload: Codable, Sendable {
        let name: String
        let email: String
        let subject: String
        let body: String
        let category: String
        let systemInfo: SystemInfo?
        let attachmentURLs: [URL]

        private enum CodingKeys: String, CodingKey {
            case name
            case email
            case subject
            case body
            case category
            case systemInfo
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(email, forKey: .email)
            try container.encode(subject, forKey: .subject)
            try container.encode(body, forKey: .body)
            try container.encode(category, forKey: .category)
            try container.encodeIfPresent(systemInfo, forKey: .systemInfo)
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try container.decode(String.self, forKey: .name)
            self.email = try container.decode(String.self, forKey: .email)
            self.subject = try container.decode(String.self, forKey: .subject)
            self.body = try container.decode(String.self, forKey: .body)
            self.category = try container.decode(String.self, forKey: .category)
            self.systemInfo = try container.decodeIfPresent(SystemInfo.self, forKey: .systemInfo)
            self.attachmentURLs = []
        }

        init(
            name: String,
            email: String,
            subject: String,
            body: String,
            category: String,
            systemInfo: SystemInfo?,
            attachmentURLs: [URL],
        ) {
            self.name = name
            self.email = email
            self.subject = subject
            self.body = body
            self.category = category
            self.systemInfo = systemInfo
            self.attachmentURLs = attachmentURLs
        }
    }

    /// Submits feedback, falling back to local storage if the server is unreachable.
    ///
    /// - Parameter payload: The feedback payload to submit.
    /// - Throws: If both remote submission and local fallback fail.
    static func submit(_ payload: FeedbackPayload) async throws {
        do {
            try await submitRemotely(payload)
        } catch {
            Logger.warning(
                "Remote feedback submission failed: \(error.localizedDescription). Saving locally.",
                category: Logger.network,
            )
            try saveLocally(payload)
        }
    }

    /// Submits crash reports automatically on relaunch.
    ///
    /// Uses the same feedback endpoint with fixed metadata fields.
    /// Fire-and-forget — network failures are silently ignored
    /// (same pattern as telemetry heartbeats).
    static func submitAutomaticCrashReport(crashReports: [URL]) async {
        let systemInfo = await SystemInfo.collect(tabCount: 0, spaceCount: 0, extensionCount: 0)
        let payload = FeedbackPayload(
            name: "Automatic Report",
            email: "",
            subject: "Automatic Crash Report",
            body: "This crash report was sent automatically on relaunch.",
            category: "crash",
            systemInfo: systemInfo,
            attachmentURLs: crashReports
        )

        do {
            try await submitRemotely(payload)
            Logger.info("Automatic crash report submitted with \(crashReports.count) report(s)", category: Logger.system)
        } catch {
            Logger.warning(
                "Automatic crash report submission failed: \(error.localizedDescription)",
                category: Logger.network
            )
        }
    }

    // MARK: - Remote Submission

    private static func submitRemotely(_ payload: FeedbackPayload) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        var parts: [MultipartPart] = []

        let metadataJSON = try encoder.encode(payload)
        parts.append(MultipartPart(
            name: "metadata",
            filename: "metadata.json",
            contentType: "application/json",
            data: metadataJSON,
        ))

        for url in payload.attachmentURLs {
            guard let data = try? Data(contentsOf: url) else { continue }
            parts.append(MultipartPart(
                name: "attachment",
                filename: url.lastPathComponent,
                contentType: mimeType(for: url),
                data: data,
            ))
        }

        guard let feedback = Constants.API.feedback else {
            throw URLError(.unsupportedURL)
        }
        try await HTTPClient.uploadMultipart(feedback, parts: parts)
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "json": "application/json"
        case "log", "txt": "text/plain"
        case "crash", "ips": "text/plain"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "zip": "application/zip"
        default: "application/octet-stream"
        }
    }

    // MARK: - Local Fallback

    private static func saveLocally(_ payload: FeedbackPayload) throws {
        let fm = FileManager.default
        let reportsDirectory = Directories.appStorage
            .appendingPathComponent("FeedbackReports", isDirectory: true)

        if !fm.fileExists(atPath: reportsDirectory.path) {
            try fm.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
        }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let reportDirectory = reportsDirectory
            .appendingPathComponent(timestamp, isDirectory: true)
        try fm.createDirectory(at: reportDirectory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(payload)
        try jsonData.write(to: reportDirectory.appendingPathComponent("feedback.json"))

        for attachmentURL in payload.attachmentURLs {
            let destination = reportDirectory.appendingPathComponent(attachmentURL.lastPathComponent)
            try? fm.copyItem(at: attachmentURL, to: destination)
        }
    }
}
