import Foundation

/// Detects installed browsers and their user profiles on the system.
///
/// `BrowserDetector` scans the file system to find which browsers are installed
/// and discovers their available user profiles. This information is used to
/// present import options to the user.
///
/// ## Usage
///
/// ```swift
/// let browsers = BrowserDetector.detectInstalledBrowsers()
///
/// for browser in browsers {
///     let profiles = BrowserDetector.detectProfiles(for: browser)
///     print("\(browser.displayName): \(profiles.count) profiles")
/// }
/// ```
///
/// ## Profile Detection
///
/// Different browsers store profiles differently:
///
/// - **Chromium**: Named directories (`Default`, `Profile 1`, etc.) with `Preferences` JSON
/// - **Firefox**: Hash-prefixed directories (`abc123.default`) with `places.sqlite`
/// - **Safari**: Single profile in `~/Library/Safari`
/// - **Arc**: Single profile with `StorableSidebar.json`
enum BrowserDetector {
    /// Scans the system for installed browsers.
    ///
    /// - Returns: List of browsers that have their application bundle present on the system.
    static func detectInstalledBrowsers() -> [ThirdPartyBrowser] {
        ThirdPartyBrowser.allCases.filter { $0.isInstalled && $0 != .htmlFile }
    }

    /// Detects available user profiles for a specific browser.
    ///
    /// - Parameter browser: The browser to scan for profiles.
    /// - Returns: Array of detected profiles, or empty array if none found.
    static func detectProfiles(for browser: ThirdPartyBrowser) -> [BrowserProfile] {
        guard let dataDir = browser.dataDirectoryURL else {
            return []
        }

        if browser.isChromiumBased {
            return detectChromiumProfiles(in: dataDir, browser: browser)
        } else if browser.isFirefoxBased {
            return detectFirefoxProfiles(in: dataDir, browser: browser)
        } else if browser == .safari {
            return detectSafariProfile(in: dataDir)
        } else if browser == .arc {
            return detectArcProfile(in: dataDir, browser: browser)
        }

        return []
    }
}

// MARK: - Profile Detection by Browser Type

extension BrowserDetector {
    /// Detects Chromium-based browser profiles by scanning for profile directories.
    ///
    /// Chromium browsers store each profile in a separate directory containing
    /// a `Bookmarks` JSON file and a `Preferences` JSON file with the profile name.
    private static func detectChromiumProfiles(
        in directory: URL,
        browser: ThirdPartyBrowser,
    ) -> [BrowserProfile] {
        var profiles: [BrowserProfile] = []
        let fileManager = FileManager.default

        let defaultProfile = detectDefaultChromiumProfile(in: directory, browser: browser)
        if let defaultProfile {
            profiles.append(defaultProfile)
        }

        let numberedProfiles = detectNumberedChromiumProfiles(
            in: directory,
            browser: browser,
            fileManager: fileManager,
        )
        profiles.append(contentsOf: numberedProfiles)

        // Electron-based Chromium apps (e.g. Helium) store data directly in the
        // root data directory without a Default/ subdirectory.
        if profiles.isEmpty {
            let rootBookmarks = directory.appendingPathComponent("Bookmarks")
            let rootHistory = directory.appendingPathComponent("History")
            if fileManager.fileExists(atPath: rootBookmarks.path)
                || fileManager.fileExists(atPath: rootHistory.path)
            {
                profiles.append(
                    BrowserProfile(
                        id: "default",
                        name: "Default",
                        path: directory,
                        browser: browser,
                    )
                )
            }
        }

        return profiles
    }

    private static func detectDefaultChromiumProfile(
        in directory: URL,
        browser: ThirdPartyBrowser,
    ) -> BrowserProfile? {
        let defaultPath = directory.appendingPathComponent("Default")
        let bookmarksFile = defaultPath.appendingPathComponent("Bookmarks")

        guard FileManager.default.fileExists(atPath: bookmarksFile.path) else {
            return nil
        }

        return BrowserProfile(
            id: "Default",
            name: "Default",
            path: defaultPath,
            browser: browser,
        )
    }

    private static func detectNumberedChromiumProfiles(
        in directory: URL,
        browser: ThirdPartyBrowser,
        fileManager: FileManager,
    ) -> [BrowserProfile] {
        guard
            let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
            )
        else {
            return []
        }

        return contents.compactMap { itemURL -> BrowserProfile? in
            guard itemURL.lastPathComponent.hasPrefix("Profile ") else {
                return nil
            }

            let profileName = extractChromiumProfileName(from: itemURL)
            let bookmarksFile = itemURL.appendingPathComponent("Bookmarks")

            guard fileManager.fileExists(atPath: bookmarksFile.path) else {
                return nil
            }

            return BrowserProfile(
                id: itemURL.lastPathComponent,
                name: profileName ?? itemURL.lastPathComponent,
                path: itemURL,
                browser: browser,
            )
        }
    }

    private static func extractChromiumProfileName(from profileURL: URL) -> String? {
        let prefsFile = profileURL.appendingPathComponent("Preferences")

        guard
            let prefsData = try? Data(contentsOf: prefsFile),
            let prefs = try? JSONSerialization.jsonObject(with: prefsData) as? [String: Any],
            let profile = prefs["profile"] as? [String: Any],
            let name = profile["name"] as? String
        else {
            return nil
        }

        return name
    }

    /// Detects Firefox profiles by scanning the Profiles directory.
    ///
    /// Firefox stores profiles in directories with a random prefix followed by
    /// the profile name (e.g., `abc123.default-release`). Each profile contains
    /// a `places.sqlite` database with bookmarks.
    private static func detectFirefoxProfiles(
        in directory: URL,
        browser: ThirdPartyBrowser,
    ) -> [BrowserProfile] {
        let fileManager = FileManager.default

        guard
            let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
            )
        else {
            return []
        }

        return contents.compactMap { itemURL -> BrowserProfile? in
            let placesDB = itemURL.appendingPathComponent("places.sqlite")

            guard fileManager.fileExists(atPath: placesDB.path) else {
                return nil
            }

            let dirName = itemURL.lastPathComponent
            let profileName = extractFirefoxProfileName(from: dirName)

            return BrowserProfile(
                id: dirName,
                name: profileName,
                path: itemURL,
                browser: browser,
            )
        }
    }

    private static func extractFirefoxProfileName(from directoryName: String) -> String {
        let components = directoryName.components(separatedBy: ".")
        guard components.count > 1 else {
            return directoryName
        }
        return components.dropFirst().joined(separator: ".")
    }

    /// Detects the Safari profile.
    ///
    /// Safari has a single profile per user stored in `~/Library/Safari`.
    private static func detectSafariProfile(in directory: URL) -> [BrowserProfile] {
        let bookmarksPlist = directory.appendingPathComponent("Bookmarks.plist")

        guard FileManager.default.fileExists(atPath: bookmarksPlist.path) else {
            return []
        }

        return [
            BrowserProfile(
                id: "default",
                name: "Default",
                path: directory,
                browser: .safari,
            ),
        ]
    }

    /// Detects the Arc browser profile.
    ///
    /// Arc stores sidebar data (including pinned tabs/bookmarks) in `StorableSidebar.json`.
    /// The data directory points to `Arc/User Data` but the sidebar file lives in the
    /// parent `Arc/` directory, so we check both locations. Arc also has a standard
    /// Chromium `Default/Bookmarks` inside `User Data/`.
    private static func detectArcProfile(
        in directory: URL,
        browser: ThirdPartyBrowser,
    ) -> [BrowserProfile] {
        let sidebarFile = directory.appendingPathComponent("StorableSidebar.json")
        let parentSidebarFile = directory.deletingLastPathComponent().appendingPathComponent("StorableSidebar.json")

        let sidebarExists = FileManager.default.fileExists(atPath: sidebarFile.path)
            || FileManager.default.fileExists(atPath: parentSidebarFile.path)

        // Also check for standard Chromium Default profile
        let defaultBookmarks = directory.appendingPathComponent("Default/Bookmarks")
        let hasDefaultProfile = FileManager.default.fileExists(atPath: defaultBookmarks.path)

        guard sidebarExists || hasDefaultProfile else {
            return []
        }

        // Use the Default profile path if it exists (has Chromium bookmarks/history),
        // otherwise use the data directory itself
        let profilePath = hasDefaultProfile
            ? directory.appendingPathComponent("Default")
            : directory

        return [
            BrowserProfile(
                id: "default",
                name: "Default",
                path: profilePath,
                browser: browser,
            ),
        ]
    }
}
