import Foundation

/// Imports extension metadata from Chromium-based browsers.
///
/// Chromium browsers store extensions in a directory structure where each
/// extension has its own folder containing a `manifest.json` file with
/// metadata.
///
/// ## Directory Structure
///
/// ```
/// Profile/Extensions/
/// ├── extension_id_1/
/// │   └── version/
/// │       └── manifest.json
/// ├── extension_id_2/
/// │   └── version/
/// │       └── manifest.json
/// ```
///
/// ## Manifest Format
///
/// The `manifest.json` contains:
/// - `name`: Extension display name
/// - `version`: Extension version
/// - `description`: Extension description
/// - `homepage_url`: Developer's website (optional)
///
/// ## Disabled Extensions
///
/// Information about enabled/disabled state is stored in `Preferences` file
/// under `extensions.settings`. This importer reads that to determine
/// which extensions are currently enabled.
final class ChromiumExtensionImporter: ExtensionImporter, Sendable {
    let browser: ThirdPartyBrowser

    init(browser: ThirdPartyBrowser) {
        self.browser = browser
    }

    func canImport(from profile: BrowserProfile) -> Bool {
        let extensionsDir = profile.path.appendingPathComponent("Extensions")
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: extensionsDir.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    func importExtensions(from profile: BrowserProfile) async throws -> [ImportedExtension] {
        let extensionsDir = profile.path.appendingPathComponent("Extensions")

        guard FileManager.default.fileExists(atPath: extensionsDir.path) else {
            return []
        }

        let enabledExtensions = loadEnabledExtensions(from: profile)
        var extensions: [ImportedExtension] = []

        let contents = try FileManager.default.contentsOfDirectory(
            at: extensionsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
        )

        for extensionDir in contents {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: extensionDir.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                continue
            }

            let extensionID = extensionDir.lastPathComponent

            if let ext = try? loadExtension(
                from: extensionDir,
                id: extensionID,
                enabledExtensions: enabledExtensions,
            ) {
                extensions.append(ext)
            }
        }

        Logger.info(
            "Found \(extensions.count) extensions in \(browser.displayName)",
            category: Logger.data,
        )

        return extensions.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Enabled Extensions Loading

private extension ChromiumExtensionImporter {
    func loadEnabledExtensions(from profile: BrowserProfile) -> Set<String> {
        let preferencesFile = profile.path.appendingPathComponent("Preferences")

        guard let data = try? Data(contentsOf: preferencesFile),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let extensions = json["extensions"] as? [String: Any],
              let settings = extensions["settings"] as? [String: Any]
        else {
            return []
        }

        var enabled: Set<String> = []

        for (extensionID, settingsValue) in settings {
            guard let settingsDict = settingsValue as? [String: Any] else { continue }

            let state = settingsDict["state"] as? Int ?? 1
            if state == 1 {
                enabled.insert(extensionID)
            }
        }

        return enabled
    }
}

// MARK: - Extension Loading

private extension ChromiumExtensionImporter {
    func loadExtension(
        from extensionDir: URL,
        id: String,
        enabledExtensions: Set<String>,
    ) throws -> ImportedExtension? {
        guard let versionDir = findLatestVersionDir(in: extensionDir) else {
            return nil
        }

        let manifestURL = versionDir.appendingPathComponent("manifest.json")

        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: manifestURL)
        guard let manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let name = manifest["name"] as? String ?? "Unknown Extension"

        if name.hasPrefix("__MSG_") || name.isEmpty {
            return nil
        }

        let version = manifest["version"] as? String
        let description = manifest["description"] as? String
        let homepageURLString = manifest["homepage_url"] as? String
        let homepageURL = homepageURLString.flatMap { URL(string: $0) }

        let isEnabled = enabledExtensions.contains(id)

        return ImportedExtension(
            id: id,
            name: cleanExtensionName(name),
            version: version,
            description: cleanDescription(description),
            homepageURL: homepageURL,
            isEnabled: isEnabled,
            sourceBrowser: browser,
        )
    }

    func findLatestVersionDir(in extensionDir: URL) -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: extensionDir,
            includingPropertiesForKeys: [.isDirectoryKey],
        ) else {
            return nil
        }

        let versionDirs = contents.filter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }

        return versionDirs
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .first
    }

    func cleanExtensionName(_ name: String) -> String {
        var cleaned = name

        if cleaned.hasPrefix("__MSG_") {
            return "Extension"
        }

        cleaned = cleaned.trimmingCharacters(in: .whitespaces)

        return cleaned
    }

    func cleanDescription(_ description: String?) -> String? {
        guard let description else { return nil }

        if description.hasPrefix("__MSG_") {
            return nil
        }

        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
