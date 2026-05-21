import Foundation

/// Imports extension metadata from Safari's exported Extensions.json file.
///
/// Safari's File > Export Browsing Data produces a zip containing `Extensions.json`
/// with this format:
///
/// ```json
/// {
///   "metadata": { "version": 1, ... },
///   "extensions": [
///     {
///       "composed_identifier": "com.example.safari-extension",
///       "developer_name": "Developer",
///       "display_name": "Extension Name",
///       "marketplace_lookup": {
///         "store_identifier": "1234567890"
///       }
///     }
///   ]
/// }
/// ```
enum SafariExtensionJSONImporter {
    /// Parses extensions from a Safari Extensions.json file.
    ///
    /// - Parameter fileURL: URL of the Extensions.json file.
    /// - Returns: Array of imported extension metadata.
    static func importExtensions(from fileURL: URL) async throws -> [ImportedExtension] {
        let data = try Data(contentsOf: fileURL)
        let export = try JSONDecoder().decode(SafariExtensionExport.self, from: data)

        return export.extensions.map { ext in
            ImportedExtension(
                id: ext.composedIdentifier,
                name: ext.displayName,
                description: ext.developerName.map { "by \($0)" },
                isEnabled: true,
                sourceBrowser: .safari,
            )
        }
    }
}

// MARK: - JSON Structure

private struct SafariExtensionExport: Decodable {
    let extensions: [ExtensionItem]

    struct ExtensionItem: Decodable {
        let composedIdentifier: String
        let displayName: String
        let developerName: String?

        enum CodingKeys: String, CodingKey {
            case composedIdentifier = "composed_identifier"
            case displayName = "display_name"
            case developerName = "developer_name"
        }
    }
}
