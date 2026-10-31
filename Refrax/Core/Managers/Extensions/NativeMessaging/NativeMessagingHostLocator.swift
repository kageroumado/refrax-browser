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
    /// Chrome format: the `chrome-extension://<id>/` origins allowed to connect. In Refrax's
    /// own folder, `webkit-extension://<id>/` origins.
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
}

/// A host that may be started for one extension.
nonisolated struct ResolvedNativeMessagingHost: Equatable, Sendable {
    let name: String
    let manifestURL: URL
    let executableURL: URL
    let arguments: [String]
    /// The manifest allows the extension only by an identity the extension claims, so the
    /// user decides whether it may start the host.
    let requiresConsent: Bool
    /// The origin or add-on ID the manifest admitted the extension by.
    let matchedIdentity: String
}

/// Finds the native messaging host an extension names, in the directories where Chrome,
/// Chromium and Firefox look, and decides whether the extension may start it.
///
/// A host name selects `<name>.json` in each directory. In Refrax's own folder a manifest
/// allows an extension by the origin Refrax serves it from. In a browser's folder it allows
/// one by Chrome origin or Firefox add-on ID: a Chrome ID proven by the CRX signature starts
/// the host outright, while a Chrome ID or add-on ID the extension only states in its manifest
/// starts it with the user's consent. A proven match in any folder wins over a claimed one;
/// otherwise folders are searched in order, each browser's per-user folder before its
/// system-wide one.
nonisolated struct NativeMessagingHostLocator: Sendable {
    /// Refrax's own `NativeMessagingHosts` folder.
    let refraxDirectory: URL?
    /// Chrome's, Chromium's and Firefox's folders, in search order.
    let browserDirectories: [URL]

    /// The standard directories for a user whose home is `home`, with Refrax's own
    /// `NativeMessagingHosts` folder in `appStorage`.
    static func standard(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        appStorage: URL = Directories.appStorage,
    ) -> NativeMessagingHostLocator {
        let userSupport = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let systemSupport = URL(fileURLWithPath: "/Library/Application Support", isDirectory: true)
        let folder = "NativeMessagingHosts"
        return NativeMessagingHostLocator(
            refraxDirectory: appStorage.appendingPathComponent(folder, isDirectory: true),
            browserDirectories: [
                userSupport.appendingPathComponent("Google/Chrome/\(folder)", isDirectory: true),
                URL(fileURLWithPath: "/Library/Google/Chrome/\(folder)", isDirectory: true),
                userSupport.appendingPathComponent("Chromium/\(folder)", isDirectory: true),
                systemSupport.appendingPathComponent("Chromium/\(folder)", isDirectory: true),
                userSupport.appendingPathComponent("Mozilla/\(folder)", isDirectory: true),
                systemSupport.appendingPathComponent("Mozilla/\(folder)", isDirectory: true),
            ],
        )
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
        var claimedMatch: ResolvedNativeMessagingHost?
        let directories = (refraxDirectory.map { [($0, true)] } ?? []) + browserDirectories.map { ($0, false) }
        for (directory, isRefrax) in directories {
            let manifestURL = directory.appendingPathComponent("\(name).json")
            guard let manifest = try? loadManifest(at: manifestURL, name: name) else { continue }
            sawManifest = true
            guard let (arguments, requiresConsent) = Self.match(manifest, identity, manifestURL: manifestURL, isRefrax: isRefrax) else {
                continue
            }
            guard let executableURL = Self.executableURL(for: manifest.path) else {
                Logger.warning("Native messaging host '\(name)' names a missing or non-executable \(manifest.path)", category: Logger.extensions)
                continue
            }
            let host = ResolvedNativeMessagingHost(
                name: name,
                manifestURL: manifestURL,
                executableURL: executableURL,
                arguments: arguments,
                requiresConsent: requiresConsent,
                matchedIdentity: arguments.last ?? "",
            )
            if !requiresConsent {
                return host
            }
            claimedMatch = claimedMatch ?? host
        }
        if let claimedMatch {
            return claimedMatch
        }
        throw sawManifest ? NativeMessagingError.forbidden : NativeMessagingError.hostNotFound
    }

    /// Whether `manifest` lets `identity` connect, the arguments the host then starts with (the
    /// caller's origin for a Chrome-format host, the manifest's path and the add-on ID for a
    /// Firefox-format one), and whether the match rests on a claimed identity.
    private static func match(
        _ manifest: NativeMessagingHostManifest,
        _ identity: ExtensionIdentity,
        manifestURL: URL,
        isRefrax: Bool,
    ) -> (arguments: [String], requiresConsent: Bool)? {
        let origins = manifest.allowedOrigins ?? []
        if isRefrax {
            return origins.contains(identity.refraxOrigin) ? ([identity.refraxOrigin], false) : nil
        }
        if let id = identity.verifiedChromeID, origins.contains(ExtensionIdentity.chromeOrigin(id)) {
            return ([ExtensionIdentity.chromeOrigin(id)], false)
        }
        if let id = identity.claimedChromeID, origins.contains(ExtensionIdentity.chromeOrigin(id)) {
            return ([ExtensionIdentity.chromeOrigin(id)], true)
        }
        if let id = identity.claimedGeckoID, manifest.allowedExtensions?.contains(id) == true {
            return ([manifestURL.path, id], true)
        }
        return nil
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
