import Foundation

/// A native messaging host manifest as Chrome and Firefox define it: a JSON file named after
/// the host, in a browser's `NativeMessagingHosts` directory.
nonisolated struct NativeMessagingHostManifest: Decodable, Equatable, Sendable {
    let name: String
    let description: String?
    /// The host executable. Absolute on macOS.
    let path: String
    /// The transport; `stdio` is the only one either browser defines.
    let type: String
    /// Chrome format: the `chrome-extension://<id>/` origins allowed to connect.
    let allowedOrigins: [String]?
    /// Firefox format: the add-on IDs allowed to connect.
    let allowedExtensions: [String]?

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case path
        case type
        case allowedOrigins = "allowed_origins"
        case allowedExtensions = "allowed_extensions"
    }

    /// Whether the manifest lets `identity` connect, and the arguments the host then starts
    /// with: the caller's origin for a Chrome host, or the manifest's path and the add-on ID
    /// for a Firefox host.
    func launchArguments(for identity: ExtensionIdentity, manifestURL: URL) -> [String]? {
        if let origin = identity.chromeOrigin, allowedOrigins?.contains(origin) == true {
            return [origin]
        }
        if let geckoID = identity.geckoID, allowedExtensions?.contains(geckoID) == true {
            return [manifestURL.path, geckoID]
        }
        return nil
    }
}

/// A host that may be started for one extension.
nonisolated struct ResolvedNativeMessagingHost: Equatable, Sendable {
    let name: String
    let manifestURL: URL
    let executableURL: URL
    let arguments: [String]
}

/// Finds the native messaging host an extension names, in the directories where Chrome,
/// Chromium and Firefox look, and decides whether the extension may start it.
///
/// Refrax's own directory comes first, then each browser's per-user directory before its
/// system-wide one. A host name selects `<name>.json` in each directory; the first manifest
/// that allows the extension wins, so an app that registers itself for both Chrome and
/// Firefox serves the extension under whichever identity it carries.
nonisolated struct NativeMessagingHostLocator: Sendable {
    /// The directories searched, in order.
    let directories: [URL]

    /// The standard directories for a user whose home is `home`, after Refrax's own
    /// `NativeMessagingHosts` folder in `appStorage`.
    static func standard(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        appStorage: URL = Directories.appStorage,
    ) -> NativeMessagingHostLocator {
        let userSupport = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let systemSupport = URL(fileURLWithPath: "/Library/Application Support", isDirectory: true)
        let folder = "NativeMessagingHosts"
        return NativeMessagingHostLocator(directories: [
            appStorage.appendingPathComponent(folder, isDirectory: true),
            userSupport.appendingPathComponent("Google/Chrome/\(folder)", isDirectory: true),
            URL(fileURLWithPath: "/Library/Google/Chrome/\(folder)", isDirectory: true),
            userSupport.appendingPathComponent("Chromium/\(folder)", isDirectory: true),
            systemSupport.appendingPathComponent("Chromium/\(folder)", isDirectory: true),
            userSupport.appendingPathComponent("Mozilla/\(folder)", isDirectory: true),
            systemSupport.appendingPathComponent("Mozilla/\(folder)", isDirectory: true),
        ])
    }

    /// Whether `name` is a host name Chrome accepts: dot-separated components of lowercase
    /// ASCII letters, digits and underscores. The rule also keeps the name from leaving the
    /// manifest directory.
    static func isValidHostName(_ name: String) -> Bool {
        let components = name.split(separator: ".", omittingEmptySubsequences: false)
        return !name.isEmpty && components.allSatisfy { component in
            !component.isEmpty && component.allSatisfy { character in
                character.isASCII && (character.isLowercase || character.isNumber || character == "_")
            }
        }
    }

    /// The host `name` resolves to for `identity`.
    ///
    /// - Throws: ``NativeMessagingError/invalidHostName``; ``NativeMessagingError/hostNotFound``
    ///   when no directory has a usable manifest for `name`; ``NativeMessagingError/forbidden``
    ///   when manifests exist and none allows `identity`.
    func host(named name: String, for identity: ExtensionIdentity) throws -> ResolvedNativeMessagingHost {
        guard Self.isValidHostName(name) else { throw NativeMessagingError.invalidHostName }

        var sawManifest = false
        for directory in directories {
            let manifestURL = directory.appendingPathComponent("\(name).json")
            guard let manifest = try? loadManifest(at: manifestURL, name: name) else { continue }
            sawManifest = true
            guard let arguments = manifest.launchArguments(for: identity, manifestURL: manifestURL) else { continue }
            guard let executableURL = Self.executableURL(for: manifest.path) else {
                Logger.warning("Native messaging host '\(name)' names a missing or non-executable \(manifest.path)", category: Logger.extensions)
                continue
            }
            return ResolvedNativeMessagingHost(
                name: name,
                manifestURL: manifestURL,
                executableURL: executableURL,
                arguments: arguments,
            )
        }
        throw sawManifest ? NativeMessagingError.forbidden : NativeMessagingError.hostNotFound
    }

    /// The manifest at `url`, when it is a regular file describing the `stdio` host `name`.
    func loadManifest(at url: URL, name: String) throws -> NativeMessagingHostManifest {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw NativeMessagingError.hostNotFound }
        guard (values.fileSize ?? 0) <= Limits.manifestSize else {
            throw NativeMessagingError.invalidManifest("larger than \(Limits.manifestSize) bytes")
        }
        let manifest: NativeMessagingHostManifest
        do {
            manifest = try JSONDecoder().decode(NativeMessagingHostManifest.self, from: Data(contentsOf: url))
        } catch {
            throw NativeMessagingError.invalidManifest("unreadable JSON at \(url.path)")
        }
        guard manifest.name == name else { throw NativeMessagingError.invalidManifest("names \(manifest.name), expected \(name)") }
        guard manifest.type == "stdio" else { throw NativeMessagingError.invalidManifest("type \(manifest.type)") }
        return manifest
    }

    /// The executable a manifest's `path` names: absolute, after resolving symbolic links, a
    /// regular file the user may execute.
    static func executableURL(for path: String) -> URL? {
        guard path.hasPrefix("/") else { return nil }
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue,
              FileManager.default.isExecutableFile(atPath: url.path)
        else { return nil }
        return url
    }

    private enum Limits {
        static let manifestSize = 1_024 * 1_024
    }
}
