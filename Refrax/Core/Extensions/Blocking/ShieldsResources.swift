import CryptoKit
import Foundation
import Shields

/// Shields' redirect resources and scriptlets (`shields-resources.json`, built from uBlock
/// Origin by `Scripts/shields-resources.mjs`).
///
/// The app ships a copy. A newer copy is fetched alongside the filter lists and used only when
/// it carries a valid signature from a release key Refrax pins (``ReleaseKeys``): scriptlets
/// run as page JavaScript in every frame, so an unsigned download never replaces the bundled
/// code. A copy that fails the library's check (``check(_:)``) is ignored the same way, and so
/// is one fetched before the app last updated, whose bundled copy may be newer.
nonisolated enum ShieldsResources {
    private enum Constants {
        static let fileName = "shields-resources.json"
        /// The SHA-256 of the bundled copy a download superseded.
        static let baseFileName = "shields-resources.base"
        /// The signed copy published with each Shields resources release.
        static let refreshURL = URL.staticRequired(
            "https://github.com/kageroumado/refrax-browser/releases/download/shields-resources/shields-resources.json",
        )
        /// Fewer scriptlets than this means a truncated or wrong file.
        static let minimumScriptlets = 50
    }

    /// What `shields_resources_check` counted.
    nonisolated struct Summary: Codable, Hashable, Sendable {
        let resources: Int
        let redirects: Int
        let scriptlets: Int
    }

    /// The copy the app bundle ships.
    static func bundled(in bundle: Bundle = .main) -> Data? {
        let name = (Constants.fileName as NSString).deletingPathExtension
        guard let url = bundle.url(forResource: name, withExtension: "json") else { return nil }
        return try? Data(contentsOf: url)
    }

    /// The downloaded copy when it is still valid, else the bundled one.
    static func current(in directory: URL, bundle: Bundle = .main) -> Data {
        let bundled = bundled(in: bundle) ?? Data("[]".utf8)
        let base = try? String(contentsOf: directory.appending(path: Constants.baseFileName), encoding: .utf8)
        if base == SHA256.hash(data: bundled).hexString,
           let downloaded = try? Data(contentsOf: directory.appending(path: Constants.fileName)),
           check(downloaded) != nil {
            return downloaded
        }
        return bundled
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

    /// Fetches the published copy and keeps it in `directory` when it is signed, valid and
    /// different from the current one.
    ///
    /// - Returns: Whether the current resources changed.
    @concurrent
    static func refresh(
        into directory: URL,
        session: URLSession = .shared,
        keys: ReleaseKeys? = ReleaseKeys.pinned(),
    ) async throws -> Bool {
        guard let keys else { return false }
        let (json, response) = try await session.data(from: Constants.refreshURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
        let (signature, signatureResponse) = try await session.data(from: EngineSignature.signatureURL(for: Constants.refreshURL))
        guard (signatureResponse as? HTTPURLResponse)?.statusCode == 200 else { return false }
        try EngineSignature.verify(json, signatureFile: signature, subject: Constants.fileName, keys: keys)
        guard check(json) != nil else { return false }

        guard json != current(in: directory) else { return false }
        let bundled = bundled() ?? Data("[]".utf8)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try json.write(to: directory.appending(path: Constants.fileName), options: .atomic)
        try SHA256.hash(data: bundled).hexString.write(
            to: directory.appending(path: Constants.baseFileName),
            atomically: true,
            encoding: .utf8,
        )
        return true
    }
}
