import CryptoKit
import Foundation
import Shields

/// Shields' redirect resources and scriptlets (`shields-resources.json`, built from uBlock
/// Origin by `Scripts/shields-resources.mjs`).
///
/// The app ships a copy and its version (`shields-resources.version`). A newer copy is fetched
/// alongside the filter lists as a release: a JSON object naming its purpose
/// (`"domain": "refrax-shields-resources"`), its version and the resources, signed as a whole by
/// a release key Refrax pins (``ReleaseKeys``). Scriptlets run as page JavaScript in every
/// frame, so a release is used only while its signature verifies, which is checked again each
/// time it is read from disk, and only when its version is above both the bundled copy's and
/// the release already kept: an old signed release cannot be replayed, and an app update with
/// newer bundled resources outranks an older download. A file signed for another purpose
/// lacks the domain and is refused.
nonisolated enum ShieldsResources {
    private enum Constants {
        static let fileName = "shields-resources.json"
        static let versionFileName = "shields-resources"
        static let versionExtension = "version"
        /// The downloaded release, kept with its signature (`.sig`).
        static let releaseFileName = "shields-resources.release.json"
        static let domain = "refrax-shields-resources"
        /// Larger downloads are not a resources release; the bundled copy is about 400 KB.
        static let maximumBytes = 8 * 1_024 * 1_024
        static let maximumSignatureBytes = 1_024
        /// Fewer scriptlets than this means a truncated or wrong file.
        static let minimumScriptlets = 50
    }

    /// Where each resources release is published, signed (`.sig`).
    static let releaseURL = URL.staticRequired(
        "https://github.com/kageroumado/refrax-browser/releases/download/shields-resources/shields-resources.release.json",
    )

    /// What `shields_resources_check` counted.
    nonisolated struct Summary: Codable, Hashable, Sendable {
        let resources: Int
        let redirects: Int
        let scriptlets: Int
    }

    /// A verified release.
    nonisolated struct Release: Hashable, Sendable {
        let version: Int
        /// The resources array, as `shields_engine_use_resources` reads it.
        let resources: Data
    }

    nonisolated enum ReleaseError: LocalizedError, Equatable {
        case tooLarge
        case malformed

        var errorDescription: String? {
            switch self {
            case .tooLarge: "The Shields resources release is too large."
            case .malformed: "The Shields resources release is not one Refrax can use."
            }
        }
    }

    /// The copy the app bundle ships.
    static func bundled(in bundle: Bundle = .main) -> Data? {
        let name = (Constants.fileName as NSString).deletingPathExtension
        guard let url = bundle.url(forResource: name, withExtension: "json") else { return nil }
        return try? Data(contentsOf: url)
    }

    /// The version of the bundled copy; 0 when the bundle names none.
    static func bundledVersion(in bundle: Bundle = .main) -> Int {
        guard let url = bundle.url(forResource: Constants.versionFileName, withExtension: Constants.versionExtension),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return 0 }
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    /// The downloaded release when it verifies now and is newer than the bundled copy, else
    /// the bundled copy.
    static func current(in directory: URL, bundle: Bundle = .main, keys: ReleaseKeys? = ReleaseKeys.pinned()) -> Data {
        let bundled = bundled(in: bundle) ?? Data("[]".utf8)
        guard let keys, let release = try? keptRelease(in: directory, keys: keys),
              release.version > bundledVersion(in: bundle)
        else { return bundled }
        return release.resources
    }

    /// The release kept in `directory`, verified against `keys`.
    static func keptRelease(in directory: URL, keys: ReleaseKeys) throws -> Release {
        let url = directory.appending(path: Constants.releaseFileName)
        let envelope = try Data(contentsOf: url)
        let signature = try Data(contentsOf: EngineSignature.signatureURL(for: url))
        return try open(envelope, signatureFile: signature, keys: keys)
    }

    /// Verifies a release's signature, then reads it.
    static func open(_ envelope: Data, signatureFile: Data, keys: ReleaseKeys) throws -> Release {
        guard envelope.count <= Constants.maximumBytes else { throw ReleaseError.tooLarge }
        try EngineSignature.verify(envelope, signatureFile: signatureFile, subject: Constants.releaseFileName, keys: keys)
        guard let object = try? JSONSerialization.jsonObject(with: envelope) as? [String: Any],
              object["domain"] as? String == Constants.domain,
              let version = object["version"] as? Int, version > 0,
              let resources = object["resources"] as? [Any],
              let data = try? JSONSerialization.data(withJSONObject: resources, options: [.sortedKeys]),
              check(data) != nil
        else { throw ReleaseError.malformed }
        return Release(version: version, resources: data)
    }

    /// Counts what `json` holds, or nil when the library rejects it or it holds too few
    /// scriptlets to be a real resources file.
    static func check(_ json: Data) -> Summary? {
        var buffer = ShieldsBuffer()
        let status = json.withUnsafeBytes { bytes in
            shields_resources_check(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, &buffer)
        }
        defer { shields_buffer_free(&buffer) }
        guard status == SHIELDS_OK,
              let summary = try? JSONDecoder().decode(Summary.self, from: buffer.contents),
              summary.scriptlets >= Constants.minimumScriptlets
        else { return nil }
        return summary
    }

    /// Fetches the published release and keeps it in `directory` when it verifies and is newer
    /// than the bundled copy and the release already kept.
    ///
    /// - Returns: Whether the current resources changed.
    @concurrent
    static func refresh(
        into directory: URL,
        session: URLSession = .shared,
        keys: ReleaseKeys? = ReleaseKeys.pinned(),
        bundle: Bundle = .main,
        from url: URL = releaseURL,
    ) async throws -> Bool {
        guard let keys else { return false }
        let envelope = try await download(url, session: session, limit: Constants.maximumBytes)
        let signatureURL = EngineSignature.signatureURL(for: url)
        let signature = try await download(signatureURL, session: session, limit: Constants.maximumSignatureBytes)
        let release = try open(envelope, signatureFile: signature, keys: keys)
        let floor = max(bundledVersion(in: bundle), (try? keptRelease(in: directory, keys: keys))?.version ?? 0)
        guard release.version > floor else { return false }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let kept = directory.appending(path: Constants.releaseFileName)
        try signature.write(to: EngineSignature.signatureURL(for: kept), options: .atomic)
        try envelope.write(to: kept, options: .atomic)
        return true
    }

    /// `url`'s body, refused past `limit` bytes; the download stops there.
    private static func download(_ url: URL, session: URLSession, limit: Int) async throws -> Data {
        let (bytes, response) = try await session.bytes(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        if response.expectedContentLength > limit {
            throw ReleaseError.tooLarge
        }
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count > limit {
                throw ReleaseError.tooLarge
            }
        }
        return data
    }
}
