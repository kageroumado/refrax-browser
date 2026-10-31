import Foundation
import Shields

/// A failure inside the Shields library (`Engines/Shared/shields`).
nonisolated enum ShieldsError: LocalizedError, Equatable {
    /// The library returned a status other than `SHIELDS_OK`.
    case status(Int32, operation: String)
    /// A DAT was corrupt or written by another library version.
    case unreadableEngine
    /// The library and Refrax disagree on the C interface.
    case abiMismatch(UInt32)

    var errorDescription: String? {
        switch self {
        case let .status(status, operation):
            "Shields \(operation) failed (status \(status))."
        case .unreadableEngine:
            "The content blocking engine file could not be read."
        case let .abiMismatch(version):
            "The Shields library speaks interface \(version); Refrax expects \(SHIELDS_ABI_VERSION)."
        }
    }
}

/// An immutable adblock-rust engine loaded from a DAT.
///
/// Queries are thread-safe: the Rust engine is `Send + Sync` (asserted in the crate), and
/// `use_resources`, its one mutation, runs in `init` before the handle escapes.
final nonisolated class ShieldsEngine: @unchecked Sendable {
    private let handle: OpaquePointer

    /// The DAT format this build of the library reads and writes; part of every cache key.
    static let format = String(cString: shields_engine_format())

    /// The version of the library's C interface.
    static var abiVersion: UInt32 {
        shields_abi_version()
    }

    /// The WebKit pass's version; part of every cache key.
    static var webKitPassVersion: UInt32 {
        shields_webkit_pass_version()
    }

    /// Loads an engine from a DAT and installs its redirect and scriptlet resources.
    init(dat: Data, resources: Data) throws(ShieldsError) {
        guard Self.abiVersion == UInt32(SHIELDS_ABI_VERSION) else {
            throw .abiMismatch(Self.abiVersion)
        }
        let engine = dat.withUnsafeBytes { bytes in
            shields_engine_deserialize(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
        }
        guard let engine else { throw .unreadableEngine }
        let status = resources.withUnsafeBytes { bytes in
            shields_engine_use_resources(engine, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
        }
        guard status == SHIELDS_OK else {
            shields_engine_free(engine)
            throw .status(status, operation: "use_resources")
        }
        self.handle = engine
    }

    /// Takes ownership of a freshly built engine.
    init(adopting handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        shields_engine_free(handle)
    }

    /// Runs `body` with the raw handle, for the compiler's passes.
    func withHandle<T>(_ body: (OpaquePointer) throws -> T) rethrows -> T {
        try body(handle)
    }

    /// Why a request is decided as it is, including an exception that matched without a block.
    /// `type` is a request type adblock-rust knows (`script`, `sub_frame`, …; see
    /// ``ShieldsRequestType``); unknown names count as `other`.
    func explain(
        url: String,
        source: String,
        type: String,
        method: String = "GET",
    ) -> ShieldsExplanation? {
        var buffer = ShieldsBuffer()
        let status = shields_engine_explain(handle, url, source, type, method, &buffer)
        defer { shields_buffer_free(&buffer) }
        guard status == SHIELDS_OK else { return nil }
        return try? JSONDecoder().decode(ShieldsExplanation.self, from: buffer.contents)
    }

    /// What to apply to a document at `url`: hide selectors, procedural filters, scriptlets.
    func cosmeticResources(for url: URL) -> ShieldsCosmeticResources? {
        var buffer = ShieldsBuffer()
        let status = shields_engine_url_cosmetic_resources(handle, url.absoluteString, &buffer)
        defer { shields_buffer_free(&buffer) }
        guard status == SHIELDS_OK else { return nil }
        return try? JSONDecoder().decode(ShieldsCosmeticResources.self, from: buffer.contents)
    }

    /// Serializes the engine's rules (a DAT); resources are not included.
    func serialized() throws(ShieldsError) -> Data {
        var buffer = ShieldsBuffer()
        let status = shields_engine_serialize(handle, &buffer)
        defer { shields_buffer_free(&buffer) }
        guard status == SHIELDS_OK else { throw .status(status, operation: "serialize") }
        return buffer.contents
    }
}

/// adblock-rust's request types (webRequest names).
nonisolated enum ShieldsRequestType: String, Codable, Sendable, CaseIterable {
    case document
    case subdocument
    case script
    case stylesheet
    case image
    case font
    case media
    case object
    case xmlhttprequest
    case websocket
    case ping
    case other

    /// A best guess from a URL's path extension, for loads WebKit reports without a type.
    init(guessingFrom url: URL) {
        switch url.pathExtension.lowercased() {
        case "js", "mjs": self = .script
        case "css": self = .stylesheet
        case "png", "jpg", "jpeg", "gif", "webp", "avif", "svg", "ico", "bmp": self = .image
        case "woff", "woff2", "ttf", "otf", "eot": self = .font
        case "mp4", "webm", "m3u8", "mp3", "m4a", "ogg", "mov": self = .media
        case "html", "htm": self = .subdocument
        default: self = .other
        }
    }
}

/// `shields_engine_explain`'s answer.
nonisolated struct ShieldsExplanation: Codable, Hashable, Sendable {
    nonisolated struct Rule: Codable, Hashable, Sendable {
        /// The filter as written; present for engines built from a debug set.
        var text: String?
        /// The list's position among the build's lists.
        var sourceIndex: Int?
        /// The filter's zero-based line in its list.
        var line: Int?
    }

    var shouldBlock: Bool
    var important: Bool
    var redirected: Bool
    var rewrittenUrl: String?
    var rule: Rule?
    var exception: Rule?
    var csp: String?
}

/// `shields_engine_url_cosmetic_resources`' answer.
nonisolated struct ShieldsCosmeticResources: Codable, Hashable, Sendable {
    var hideSelectors: [String]
    var proceduralActions: [String]
    var exceptions: [String]
    var injectedScript: String
    var generichide: Bool

    private enum CodingKeys: String, CodingKey {
        case hideSelectors = "hide_selectors"
        case proceduralActions = "procedural_actions"
        case exceptions
        case injectedScript = "injected_script"
        case generichide
    }
}

nonisolated extension ShieldsBuffer {
    /// A copy of the library-owned bytes; the buffer still needs `shields_buffer_free`.
    var contents: Data {
        guard let data, len > 0 else { return Data() }
        return Data(bytes: data, count: len)
    }
}
