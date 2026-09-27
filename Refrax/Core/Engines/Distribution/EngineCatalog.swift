import CryptoKit
import Foundation

// MARK: - Release Version

/// An engine release's version, `<upstream version>-r<revision>` (`152.0.7977.82-r1`), ordered by
/// its numbers: the upstream version first, then Refrax's rebuild counter for it.
nonisolated struct EngineReleaseVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    let upstream: [Int]
    let revision: Int

    init?(_ string: String) {
        let parts = string.split(separator: "-r", omittingEmptySubsequences: false)
        guard parts.count == 2, let revision = Int(parts[1]), revision >= 0 else { return nil }
        let upstream = parts[0].split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !upstream.isEmpty, upstream.allSatisfy({ $0 != nil }) else { return nil }
        self.upstream = upstream.compactMap(\.self)
        self.revision = revision
    }

    var description: String {
        upstream.map(String.init).joined(separator: ".") + "-r\(revision)"
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.upstream != rhs.upstream {
            return lhs.upstream.lexicographicallyPrecedes(rhs.upstream)
        }
        return lhs.revision < rhs.revision
    }
}

// MARK: - Signature

/// The trust anchor for engine downloads: Refrax's Ed25519 release key (`RefraxEDPublicKey`, the
/// key app updates are checked with), whose private half signs every engine release and the
/// catalog. A signature is the raw 64-byte Ed25519 signature over a file's bytes, base64, in a
/// sibling file named `<file>.sig`. Nothing downloaded is trusted or opened before it verifies.
nonisolated enum EngineSignature {
    /// Engine downloads come only from this repository's releases, over HTTPS.
    static let allowedPathPrefix = "/kageroumado/refrax-engines/releases/download/"

    static func pinnedKey(bundle: Bundle = .main) throws -> Curve25519.Signing.PublicKey {
        guard let base64 = bundle.object(forInfoDictionaryKey: "RefraxEDPublicKey") as? String,
              let raw = Data(base64Encoded: base64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
        else {
            throw EngineDistributionError.keyMissing
        }
        return key
    }

    /// The signature file covering `url`.
    static func signatureURL(for url: URL) -> URL {
        URL(string: url.absoluteString + ".sig") ?? url.appendingPathExtension("sig")
    }

    static func isAllowedDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.host()?.lowercased() == "github.com",
              url.user == nil, url.password == nil
        else { return false }
        return url.path(percentEncoded: false).hasPrefix(allowedPathPrefix)
    }

    /// Decodes a `.sig` file: base64 (surrounding whitespace allowed) of exactly 64 bytes.
    static func signature(fromFile data: Data) throws -> Data {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let signature = Data(base64Encoded: text), signature.count == 64 else {
            throw EngineDistributionError.signatureMalformed
        }
        return signature
    }

    static func verify(
        _ message: some DataProtocol, signatureFile: Data, subject: String, key: Curve25519.Signing.PublicKey,
    ) throws {
        guard try key.isValidSignature(signature(fromFile: signatureFile), for: message) else {
            throw EngineDistributionError.signatureInvalid(subject)
        }
    }
}

// MARK: - Catalog

/// The engines Refrax can download: `engines.json` on the `catalog` release of
/// `kageroumado/refrax-engines`, signed as a whole (`engines.json.sig`). Written by
/// `Scripts/forge/publish-engine.sh`; a release reaches users when the catalog names it.
nonisolated struct EngineCatalog: Codable, Hashable, Sendable {
    /// One downloadable engine release: a zip of the signed, notarized `.engine`.
    struct Release: Codable, Hashable, Sendable {
        /// `<upstream version>-r<revision>`, the `RFXEngineBuild` of the bundle inside.
        let version: String
        let url: URL
        let sha256: String
        let sizeBytes: Int64
        /// The engine contract the bundle implements, `major.minor`.
        let contract: String
        let minimumSystemVersion: String
        let notes: String?
    }

    struct Engine: Codable, Hashable, Sendable {
        let displayName: String
        /// Release per channel; `stable` is what Refrax installs.
        let channels: [String: Release]
    }

    static let schemaVersion = 1
    static let url = URL(string: "https://github.com/kageroumado/refrax-engines/releases/download/catalog/engines.json")!

    let schema: Int
    /// Keyed by engine ID.
    let engines: [String: Engine]

    /// Downloads the catalog and verifies it against the pinned key before decoding it.
    static func fetch(session: URLSession = .shared, key: Curve25519.Signing.PublicKey? = nil) async throws -> EngineCatalog {
        let key = try key ?? EngineSignature.pinnedKey()
        let data = try await download(url, session: session, limit: 1 << 20)
        let signature = try await download(EngineSignature.signatureURL(for: url), session: session, limit: 1024)
        try EngineSignature.verify(data, signatureFile: signature, subject: url.lastPathComponent, key: key)
        return try decode(data)
    }

    static func decode(_ data: Data) throws -> EngineCatalog {
        let catalog: EngineCatalog
        do {
            catalog = try JSONDecoder().decode(EngineCatalog.self, from: data)
        } catch {
            throw EngineDistributionError.catalogMalformed(String(describing: error))
        }
        guard catalog.schema == schemaVersion else {
            throw EngineDistributionError.catalogMalformed("schema \(catalog.schema) is not \(schemaVersion)")
        }
        return catalog
    }

    /// The stable release of `id`.
    func release(for id: EngineID) -> Release? {
        engines[id.rawValue]?.channels["stable"]
    }

    /// Everything that would stop Refrax installing from this catalog; empty means publishable.
    /// The publish script runs it before uploading.
    func problems() -> [String] {
        var problems: [String] = []
        if schema != Self.schemaVersion {
            problems.append("schema \(schema) is not \(Self.schemaVersion)")
        }
        for (id, engine) in engines.sorted(by: { $0.key < $1.key }) {
            if engine.channels["stable"] == nil {
                problems.append("\(id): no stable channel")
            }
            for (channel, release) in engine.channels.sorted(by: { $0.key < $1.key }) {
                let label = "\(id).channels.\(channel)"
                if EngineReleaseVersion(release.version) == nil {
                    problems.append("\(label).version \(release.version) is not <version>-r<revision>")
                }
                if !EngineSignature.isAllowedDownloadURL(release.url) {
                    problems.append("\(label).url is not a refrax-engines release asset: \(release.url.absoluteString)")
                }
                if !release.url.lastPathComponent.contains(release.version) {
                    problems.append("\(label).url does not carry the version \(release.version)")
                }
                if !(release.sha256.count == 64 && release.sha256.allSatisfy(\.isHexDigit)) {
                    problems.append("\(label).sha256 is not 64 hex digits")
                }
                if release.sizeBytes <= 0 {
                    problems.append("\(label).sizeBytes must be positive")
                }
                if EngineContractVersion(string: release.contract) == nil {
                    problems.append("\(label).contract \(release.contract) is not major.minor")
                }
            }
        }
        return problems
    }

    private static func download(_ url: URL, session: URLSession, limit: Int) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw EngineDistributionError.http(url, http.statusCode)
        }
        guard data.count <= limit else {
            throw EngineDistributionError.catalogMalformed("\(url.lastPathComponent) is \(data.count) bytes")
        }
        return data
    }
}

nonisolated extension EngineContractVersion {
    /// Parses `major.minor`.
    init?(string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 2, let major = parts[0], let minor = parts[1] else { return nil }
        self.init(major: major, minor: minor)
    }
}

// MARK: - Errors

nonisolated enum EngineDistributionError: LocalizedError, Equatable {
    case keyMissing
    case signatureMalformed
    case signatureInvalid(String)
    case urlNotAllowed(URL)
    case http(URL, Int)
    case catalogMalformed(String)
    case sizeMismatch(expected: Int64, actual: Int64)
    case hashMismatch
    case archiveInvalid(String)
    case bundleMismatch(String)

    var errorDescription: String? {
        switch self {
        case .keyMissing:
            "This copy of Refrax has no engine signing key."
        case .signatureMalformed:
            "The engine's signature file is malformed."
        case let .signatureInvalid(subject):
            "\(subject) isn't signed by Refrax's release key."
        case let .urlNotAllowed(url):
            "\(url.absoluteString) isn't a Refrax engine download."
        case let .http(url, status):
            "\(url.lastPathComponent) answered HTTP \(status)."
        case let .catalogMalformed(detail):
            "The engine catalog is malformed: \(detail)"
        case let .sizeMismatch(expected, actual):
            "The download is \(actual) bytes; the catalog says \(expected)."
        case .hashMismatch:
            "The download doesn't match the catalog's checksum."
        case let .archiveInvalid(detail):
            "The engine archive is invalid: \(detail)"
        case let .bundleMismatch(detail):
            "The downloaded engine isn't the one the catalog describes: \(detail)"
        }
    }
}
