import CoreServices
import Foundation

/// Manages macOS quarantine attributes for downloaded files.
///
/// Quarantine attributes are a critical security feature that enables Gatekeeper
/// to warn users about potentially dangerous downloaded files. Safari and other
/// browsers set these attributes on all downloads.
///
/// ## What Quarantine Does
///
/// When a quarantined file is opened:
/// 1. Gatekeeper checks if the file is from an identified developer
/// 2. If unsigned or from unknown developer, user sees a warning
/// 3. For apps, additional checks like notarization are performed
///
/// ## Attribute Format
///
/// The `com.apple.quarantine` extended attribute is a semicolon-delimited string:
/// ```
/// flags;timestamp;agent;uuid
/// ```
///
/// Example: `0083;5991b778;Refrax;BC4DFC58-0D26-460D-9688-81D119298642`
///
/// ## Usage
///
/// ```swift
/// try QuarantineManager.setQuarantine(
///     onFileAt: downloadedFileURL,
///     downloadedFrom: originalURL,
///     originPage: referringPageURL
/// )
/// ```
enum QuarantineManager {
    // MARK: - Constants

    /// The extended attribute name for quarantine data.
    static let attributeName = "com.apple.quarantine"

    /// Quarantine flags for web downloads.
    ///
    /// - `0x0002`: User has been warned (not set for new downloads)
    /// - `0x0040`: Downloaded via app that was itself quarantined
    /// - `0x0080`: Type mask for download type
    ///
    /// `0x0083` = Web download, not yet opened/warned
    static let webDownloadFlags = "0083"

    /// Application name for quarantine attribution.
    private static var appName: String {
        Bundle.main.infoDictionary?[kCFBundleNameKey as String] as? String ?? "Refrax"
    }

    /// Bundle identifier for quarantine attribution.
    private static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "com.refrax.browser"
    }

    // MARK: - Public API

    /// Sets quarantine attributes on a downloaded file.
    ///
    /// This marks the file as downloaded from the internet, enabling Gatekeeper
    /// protection when the user tries to open it.
    ///
    /// - Parameters:
    ///   - fileURL: The downloaded file URL.
    ///   - downloadURL: The URL the file was downloaded from.
    ///   - originURL: The page that linked to the download (referrer).
    /// - Throws: If setting the attribute fails.
    static func setQuarantine(
        onFileAt fileURL: URL,
        downloadedFrom downloadURL: URL?,
        originPage originURL: URL?,
    ) throws {
        // Use URLResourceValues API (modern, recommended)
        // Fall back to xattr if it fails (can happen with some file systems)
        do {
            try setQuarantineViaResourceValues(
                on: fileURL,
                downloadURL: downloadURL,
                originURL: originURL,
            )
        } catch {
            // Fallback to low-level xattr API
            try setQuarantineViaXattr(
                on: fileURL,
                downloadURL: downloadURL,
                originURL: originURL,
            )
        }
    }

    /// Removes quarantine attributes from a file.
    ///
    /// Only call this after explicit user consent (e.g., "Open Anyway").
    /// Removing quarantine bypasses Gatekeeper protection.
    ///
    /// - Parameter url: The file URL.
    /// - Throws: If removing the attribute fails.
    static func removeQuarantine(from url: URL) throws {
        var resourceValues = URLResourceValues()
        resourceValues.quarantineProperties = nil

        var mutableURL = url
        try mutableURL.setResourceValues(resourceValues)
    }

    /// Checks if a file has quarantine attributes.
    ///
    /// - Parameter url: The file URL to check.
    /// - Returns: `true` if the file is quarantined.
    static func isQuarantined(_ url: URL) -> Bool {
        do {
            let values = try url.resourceValues(forKeys: [.quarantinePropertiesKey])
            return values.quarantineProperties != nil
        } catch {
            return false
        }
    }

    /// Gets quarantine information from a file.
    ///
    /// - Parameter url: The file URL.
    /// - Returns: Quarantine info, or nil if not quarantined.
    static func getQuarantineInfo(from url: URL) -> QuarantineInfo? {
        do {
            let values = try url.resourceValues(forKeys: [.quarantinePropertiesKey])
            guard let props = values.quarantineProperties else { return nil }
            return QuarantineInfo(from: props)
        } catch {
            return nil
        }
    }

    // MARK: - Implementation

    /// Sets quarantine using the modern URLResourceValues API.
    private static func setQuarantineViaResourceValues(
        on url: URL,
        downloadURL: URL?,
        originURL: URL?,
    ) throws {
        // Build quarantine properties dictionary
        // Keys are defined in CoreServices/LaunchServices
        var properties: [String: Any] = [
            kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
            kLSQuarantineAgentNameKey as String: appName,
            kLSQuarantineAgentBundleIdentifierKey as String: bundleID,
            kLSQuarantineTimeStampKey as String: Date(),
        ]

        if let downloadURL {
            properties[kLSQuarantineDataURLKey as String] = downloadURL.absoluteString
        }

        if let originURL {
            properties[kLSQuarantineOriginURLKey as String] = originURL.absoluteString
        }

        var resourceValues = URLResourceValues()
        resourceValues.quarantineProperties = properties

        var mutableURL = url
        try mutableURL.setResourceValues(resourceValues)
    }

    /// Sets quarantine using low-level xattr API.
    ///
    /// Use this as a fallback if URLResourceValues fails, or when you need
    /// more control over the exact attribute format.
    private static func setQuarantineViaXattr(
        on url: URL,
        downloadURL _: URL?,
        originURL _: URL?,
    ) throws {
        // Generate unique ID for this download event
        let uuid = UUID().uuidString

        // Timestamp as hex (seconds since Unix epoch)
        let timestamp = String(format: "%x", Int(Date().timeIntervalSince1970))

        // Build quarantine string: flags;timestamp;agent;uuid
        let quarantineValue = "\(webDownloadFlags);\(timestamp);\(appName);\(uuid)"

        guard let data = quarantineValue.data(using: .utf8) else {
            throw CocoaError(.fileWriteInvalidFileName)
        }

        let result = data.withUnsafeBytes { bytes in
            url.withUnsafeFileSystemRepresentation { path in
                setxattr(path, attributeName, bytes.baseAddress, data.count, 0, 0)
            }
        }

        if result != 0 {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))],
            )
        }
    }
}

// MARK: - Quarantine Info

/// Information extracted from a file's quarantine attributes.
struct QuarantineInfo: Sendable {
    /// The type of quarantine (e.g., web download, email attachment).
    let type: String?

    /// Name of the application that downloaded the file.
    let agentName: String?

    /// Bundle identifier of the downloading application.
    let agentBundleID: String?

    /// When the file was downloaded.
    let timestamp: Date?

    /// Direct URL the file was downloaded from.
    let downloadURL: String?

    /// URL of the page that linked to the download.
    let originURL: String?

    init(from properties: [String: Any]) {
        self.type = properties[kLSQuarantineTypeKey as String] as? String
        self.agentName = properties[kLSQuarantineAgentNameKey as String] as? String
        self.agentBundleID = properties[kLSQuarantineAgentBundleIdentifierKey as String] as? String
        self.timestamp = properties[kLSQuarantineTimeStampKey as String] as? Date
        self.downloadURL = properties[kLSQuarantineDataURLKey as String] as? String
        self.originURL = properties[kLSQuarantineOriginURLKey as String] as? String
    }
}

// MARK: - URL Extension

extension URL {
    /// Sets quarantine attributes for a downloaded file.
    ///
    /// Convenience method that calls `QuarantineManager.setQuarantine`.
    ///
    /// - Parameters:
    ///   - downloadURL: The URL the file was downloaded from.
    ///   - originURL: The referring page URL.
    func setQuarantineAttributes(
        downloadURL: URL?,
        originURL: URL?,
    ) throws {
        try QuarantineManager.setQuarantine(
            onFileAt: self,
            downloadedFrom: downloadURL,
            originPage: originURL,
        )
    }
}
