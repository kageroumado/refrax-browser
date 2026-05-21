import Foundation
import UniformTypeIdentifiers

/// Utilities for handling download filenames safely.
///
/// Provides:
/// - Filename sanitization (remove invalid characters)
/// - Conflict resolution (append numbers for duplicates)
/// - MIME type to extension mapping
/// - Content-Disposition header parsing
///
/// This enum is `nonisolated` to allow use from any isolation context,
/// including URLSession delegates and other nonisolated callbacks.
nonisolated enum FilenameUtilities {
    // MARK: - Invalid Characters

    /// Characters that are invalid in macOS/HFS+ filenames.
    ///
    /// While macOS is permissive, these characters cause issues:
    /// - `/`: Path separator
    /// - `:`: Classic Mac OS path separator, problematic in Finder
    /// - `\0`: Null byte, terminates strings
    private static let invalidCharacters = CharacterSet(charactersIn: "/:\0")

    /// Characters that should be escaped or avoided.
    ///
    /// These are technically allowed but cause problems:
    /// - Leading/trailing spaces or dots
    /// - Control characters
    /// - Characters that confuse shell commands
    private static let problematicCharacters = CharacterSet.controlCharacters
        .union(CharacterSet(charactersIn: "\"\\"))

    // MARK: - Sanitization

    /// Sanitizes a filename for safe use on macOS.
    ///
    /// Removes or replaces:
    /// - Path separators (`/`, `:`)
    /// - Null bytes
    /// - Control characters
    /// - Leading/trailing whitespace and dots
    ///
    /// - Parameter filename: The original filename.
    /// - Returns: A sanitized filename safe for the file system.
    static func sanitize(_ filename: String) -> String {
        // Single pass: replace invalid chars, remove control chars
        var result = String(filename.unicodeScalars.compactMap { scalar -> Character? in
            if CharacterSet.controlCharacters.contains(scalar) {
                return nil // Remove control characters
            } else if invalidCharacters.contains(scalar) {
                return "_" // Replace path separators with underscore
            } else {
                return Character(scalar)
            }
        })

        // Trim leading/trailing whitespace and dots
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: "."))

        // Ensure non-empty
        if result.isEmpty {
            result = "download"
        }

        // Limit length (macOS supports 255 bytes in UTF-8)
        if result.utf8.count > 255 {
            // Preserve extension if possible
            let ext = (result as NSString).pathExtension
            let name = (result as NSString).deletingPathExtension

            let maxNameLength = 255 - ext.utf8.count - 1 // -1 for dot
            if maxNameLength > 0 {
                // Truncate safely by character, then check byte count
                let truncatedName = truncateToUTF8ByteLength(name, maxBytes: maxNameLength)
                result = ext.isEmpty ? truncatedName : "\(truncatedName).\(ext)"
            } else {
                result = truncateToUTF8ByteLength(result, maxBytes: 255)
            }
        }

        return result
    }

    /// Truncates a string to fit within a maximum UTF-8 byte length.
    ///
    /// Unlike `String.prefix()`, this ensures we don't break multi-byte characters.
    private static func truncateToUTF8ByteLength(_ string: String, maxBytes: Int) -> String {
        guard string.utf8.count > maxBytes else { return string }

        var result = ""
        var byteCount = 0

        for char in string {
            let charBytes = String(char).utf8.count
            if byteCount + charBytes > maxBytes {
                break
            }
            result.append(char)
            byteCount += charBytes
        }

        return result
    }

    // MARK: - Conflict Resolution

    /// Returns a unique filename that doesn't conflict with existing files.
    ///
    /// Appends numbers like Safari: `file.pdf` → `file 1.pdf` → `file 2.pdf`
    ///
    /// - Parameters:
    ///   - filename: The desired filename.
    ///   - directory: The directory to check for conflicts.
    ///   - maxAttempts: Maximum number of alternatives to try (default: 10,000).
    /// - Returns: A unique filename.
    /// - Throws: If unable to find a unique name within attempts.
    static func uniqueFilename(
        for filename: String,
        in directory: URL,
        maxAttempts: Int = 10_000,
    ) throws -> String {
        let fm = FileManager.default

        // Get existing filenames in directory
        let existingNames: Set<String>
        do {
            let contents = try fm.contentsOfDirectory(atPath: directory.path)
            existingNames = Set(contents)
        } catch {
            // Directory doesn't exist or can't read - assume no conflicts
            existingNames = []
        }

        return try uniqueFilename(for: filename, existingNames: existingNames, maxAttempts: maxAttempts)
    }

    /// Returns a unique filename given a set of existing names.
    ///
    /// - Parameters:
    ///   - filename: The desired filename.
    ///   - existingNames: Set of filenames that already exist.
    ///   - maxAttempts: Maximum number of alternatives to try.
    /// - Returns: A unique filename.
    /// - Throws: If unable to find a unique name within attempts.
    static func uniqueFilename(
        for filename: String,
        existingNames: Set<String>,
        maxAttempts: Int = 10_000,
    ) throws -> String {
        // Check if original is available
        if !existingNames.contains(filename), !existingNames.contains("\(filename).download") {
            return filename
        }

        // Split into name and extension
        let nsFilename = filename as NSString
        let ext = nsFilename.pathExtension
        let baseName = nsFilename.deletingPathExtension

        // Try appending numbers
        for i in 1 ... maxAttempts {
            let candidate = ext.isEmpty ? "\(baseName) \(i)" : "\(baseName) \(i).\(ext)"

            if !existingNames.contains(candidate), !existingNames.contains("\(candidate).download") {
                return candidate
            }
        }

        // Fallback: append UUID fragment
        let uuid = UUID().uuidString.prefix(8)
        let fallback = ext.isEmpty ? "\(baseName) \(uuid)" : "\(baseName) \(uuid).\(ext)"
        return fallback
    }

    // MARK: - Content-Disposition Parsing

    /// Extracts filename from a Content-Disposition header.
    ///
    /// Supports RFC 5987 extended format (`filename*=`) and standard format.
    ///
    /// Examples:
    /// - `attachment; filename="report.pdf"`
    /// - `attachment; filename*=UTF-8''%E2%82%AC%20rates.pdf`
    ///
    /// - Parameter headerValue: The Content-Disposition header value.
    /// - Returns: Extracted and decoded filename, or nil.
    static func parseContentDisposition(_ headerValue: String) -> String? {
        let components = headerValue.split(separator: ";").map {
            $0.trimmingCharacters(in: .whitespaces)
        }

        // First, try RFC 5987 extended format (filename*=)
        for component in components {
            if component.lowercased().hasPrefix("filename*=") {
                return parseExtendedFilename(String(component.dropFirst(10)))
            }
        }

        // Fall back to standard format (filename=)
        for component in components {
            if component.lowercased().hasPrefix("filename=") {
                return parseStandardFilename(String(component.dropFirst(9)))
            }
        }

        return nil
    }

    /// Parses standard `filename="value"` format.
    private static func parseStandardFilename(_ value: String) -> String? {
        var result = value

        // Remove surrounding quotes
        if result.hasPrefix("\""), result.hasSuffix("\""), result.count >= 2 {
            result = String(result.dropFirst().dropLast())
        }

        // Decode percent-encoding
        result = result.removingPercentEncoding ?? result

        return result.isEmpty ? nil : sanitize(result)
    }

    /// Parses RFC 5987 extended `charset'language'value` format.
    private static func parseExtendedFilename(_ value: String) -> String? {
        // Format: charset'language'encoded-value
        // Example: UTF-8''%E2%82%AC%20rates.pdf
        let parts = value.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)

        guard parts.count >= 3 else {
            return parseStandardFilename(value)
        }

        let encodedValue = String(parts[2])

        // Decode percent-encoding
        guard let decoded = encodedValue.removingPercentEncoding else {
            return nil
        }

        return decoded.isEmpty ? nil : sanitize(decoded)
    }

    // MARK: - Extension Utilities

    /// Suggests a file extension based on MIME type.
    ///
    /// - Parameter mimeType: The MIME type (e.g., "application/pdf").
    /// - Returns: Suggested extension without dot (e.g., "pdf"), or nil.
    static func extensionForMIMEType(_ mimeType: String) -> String? {
        // Clean MIME type (remove charset, etc.)
        let cleanMIME = mimeType.split(separator: ";").first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? mimeType

        // Use UTType for modern mapping
        if let utType = UTType(mimeType: cleanMIME) {
            return utType.preferredFilenameExtension
        }

        // Fallback for common types
        return commonMIMEExtensions[cleanMIME.lowercased()]
    }

    /// Adds or updates a file extension based on MIME type.
    ///
    /// - Parameters:
    ///   - filename: The original filename.
    ///   - mimeType: The MIME type to use for extension.
    /// - Returns: Filename with appropriate extension.
    static func ensureExtension(for filename: String, mimeType: String?) -> String {
        guard let mimeType, !mimeType.isEmpty else { return filename }

        let nsFilename = filename as NSString
        let currentExt = nsFilename.pathExtension.lowercased()

        // If already has an extension, check if it matches MIME type
        if !currentExt.isEmpty {
            if let utType = UTType(filenameExtension: currentExt),
               utType.conforms(to: UTType(mimeType: mimeType) ?? .data) {
                return filename // Extension matches MIME type
            }
            // Extension doesn't match, but we'll keep it (user might want specific extension)
            return filename
        }

        // No extension, add one based on MIME type
        if let ext = extensionForMIMEType(mimeType) {
            return "\(filename).\(ext)"
        }

        return filename
    }

    /// Common MIME type to extension mappings for fallback.
    private static let commonMIMEExtensions: [String: String] = [
        "application/pdf": "pdf",
        "application/zip": "zip",
        "application/x-gzip": "gz",
        "application/x-tar": "tar",
        "application/x-7z-compressed": "7z",
        "application/x-rar-compressed": "rar",
        "application/json": "json",
        "application/xml": "xml",
        "application/javascript": "js",
        "text/plain": "txt",
        "text/html": "html",
        "text/css": "css",
        "text/csv": "csv",
        "image/jpeg": "jpg",
        "image/png": "png",
        "image/gif": "gif",
        "image/webp": "webp",
        "image/svg+xml": "svg",
        "audio/mpeg": "mp3",
        "audio/wav": "wav",
        "video/mp4": "mp4",
        "video/webm": "webm",
        "video/quicktime": "mov",
    ]
}

// MARK: - UTType Extensions

extension UTType {
    /// Creates a UTType from a MIME type string, handling charset and parameters.
    ///
    /// - Parameter mimeType: Full MIME type possibly with parameters.
    /// - Returns: The corresponding UTType, or nil.
    nonisolated static func fromMIMEType(_ mimeType: String) -> UTType? {
        let cleanMIME = mimeType.split(separator: ";").first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? mimeType
        return UTType(mimeType: cleanMIME)
    }

    /// Suggests the best filename extension for this type.
    var suggestedExtension: String? {
        preferredFilenameExtension ?? tags[.filenameExtension]?.first
    }
}
