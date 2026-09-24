import AppKit

// MARK: - Contract Version

/// The version of the engine contract (`Engines/CONTRACT.md`).
///
/// A major bump changes the meaning of an existing message; a minor bump only
/// adds messages or optional fields. Refrax loads an engine when the majors
/// match and the engine's minor is not newer than Refrax's.
nonisolated struct EngineContractVersion: Codable, Hashable, Sendable, Comparable, CustomStringConvertible {
    static let current = EngineContractVersion(major: 1, minor: 0)

    let major: Int
    let minor: Int

    var description: String {
        "\(major).\(minor)"
    }

    /// Whether Refrax, speaking `self`, can drive an engine built against `engine`.
    func accepts(_ engine: EngineContractVersion) -> Bool {
        engine.major == major && engine.minor <= minor
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
    }
}

// MARK: - Identity

/// A reverse-DNS engine identifier, e.g. `system.webkit` or `website.refrax.engine.chromium`.
nonisolated struct EngineID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    /// The operating system's WebKit, hosted in Refrax's process.
    static let systemWebKit = EngineID(rawValue: "system.webkit")

    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var description: String {
        rawValue
    }
}

/// Identifies one page (browsing context) within an engine.
nonisolated struct EnginePageID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    init() {
        rawValue = UUID()
    }

    init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UUID.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Descriptor & Capabilities

/// Browser features whose availability depends on the engine hosting the page.
///
/// The chrome gates UI on these instead of checking which engine is active.
nonisolated struct EngineCapabilities: OptionSet, Codable, Hashable, Sendable {
    let rawValue: Int

    static let javaScriptEvaluation = EngineCapabilities(rawValue: 1 << 0)
    static let findInPage = EngineCapabilities(rawValue: 1 << 1)
    static let zoom = EngineCapabilities(rawValue: 1 << 2)
    static let snapshots = EngineCapabilities(rawValue: 1 << 3)
    static let devTools = EngineCapabilities(rawValue: 1 << 4)
    static let downloads = EngineCapabilities(rawValue: 1 << 5)
    static let contentBlocking = EngineCapabilities(rawValue: 1 << 6)
    static let userScripts = EngineCapabilities(rawValue: 1 << 7)
    static let webExtensions = EngineCapabilities(rawValue: 1 << 8)
    static let pictureInPicture = EngineCapabilities(rawValue: 1 << 9)
    static let mediaCapture = EngineCapabilities(rawValue: 1 << 10)
    static let readerMode = EngineCapabilities(rawValue: 1 << 11)
    static let agentPerception = EngineCapabilities(rawValue: 1 << 12)
    static let autoFill = EngineCapabilities(rawValue: 1 << 13)
    static let processInfo = EngineCapabilities(rawValue: 1 << 14)
    static let rendererControl = EngineCapabilities(rawValue: 1 << 15)

    /// Names used in an engine bundle's `RFXEngineCapabilities` Info.plist array.
    static let namesByCapability: [(String, EngineCapabilities)] = [
        ("javaScriptEvaluation", .javaScriptEvaluation), ("findInPage", .findInPage), ("zoom", .zoom),
        ("snapshots", .snapshots), ("devTools", .devTools), ("downloads", .downloads),
        ("contentBlocking", .contentBlocking), ("userScripts", .userScripts), ("webExtensions", .webExtensions),
        ("pictureInPicture", .pictureInPicture), ("mediaCapture", .mediaCapture), ("readerMode", .readerMode),
        ("agentPerception", .agentPerception), ("autoFill", .autoFill), ("processInfo", .processInfo),
        ("rendererControl", .rendererControl),
    ]
}

nonisolated extension EngineCapabilities {
    /// Parses capability names, ignoring ones this version of Refrax doesn't know.
    init(names: [String]) {
        let known = Dictionary(uniqueKeysWithValues: Self.namesByCapability)
        self = names.reduce(into: []) { result, name in
            if let capability = known[name] { result.insert(capability) }
        }
    }
}

/// What an engine is and what it can do. Engines publish one at startup.
nonisolated struct EngineDescriptor: Codable, Hashable, Sendable {
    let id: EngineID
    /// Name shown in the Engines pane, e.g. "Chromium".
    let displayName: String
    /// Version of the engine bundle, e.g. "155.0.8059.12-1".
    let version: String
    /// Version of the rendering engine itself, e.g. "Chromium 155.0.8059.12".
    let engineVersion: String
    let vendor: String
    let contractVersion: EngineContractVersion
    let capabilities: EngineCapabilities
    /// Whether the engine renders in a process separate from Refrax.
    let isOutOfProcess: Bool
}

// MARK: - Profiles

/// The storage partition a page runs in: one per space.
nonisolated enum EngineProfileSpec: Codable, Hashable, Sendable {
    /// Shared persistent storage (spaces in `.global` data store mode).
    case shared
    /// Persistent storage isolated under an identifier (a space's UUID).
    case isolated(id: UUID)
    /// In-memory storage discarded when the profile closes (private spaces).
    case ephemeral(id: UUID)
}

/// What a new page starts with.
nonisolated struct EnginePageSpec: Codable, Hashable, Sendable {
    let id: EnginePageID
    let profile: EngineProfileSpec
    let initialURL: URL?
    /// The page that opened this one with `window.open`, when the engine supports opener links.
    let opener: EnginePageID?
}

/// What Refrax hands an engine when starting it.
nonisolated struct EngineConfiguration: Codable, Hashable, Sendable {
    /// Directory the engine owns for all persistent state (profiles, caches). Created by Refrax.
    let storageDirectory: URL
    /// Where the engine may write its log, if it keeps one.
    let logFile: URL?
    /// Preferred languages, most preferred first (BCP 47).
    let languages: [String]
}

// MARK: - Errors

nonisolated enum EngineError: LocalizedError, Equatable {
    case notInstalled(EngineID)
    case incompatibleContract(EngineID, engine: EngineContractVersion)
    case failedToLoad(EngineID, reason: String)
    case failedToStart(EngineID, reason: String)
    case pageClosed
    case inUse(EngineID)
    case unsupported(EngineCapabilities)
    case scriptFailed(String)
    case malformedMessage(String)

    var errorDescription: String? {
        switch self {
        case let .notInstalled(id):
            "The engine \(id) is not installed."
        case let .incompatibleContract(id, engine):
            "The engine \(id) was built for engine contract \(engine), which this version of Refrax (\(EngineContractVersion.current)) cannot use."
        case let .failedToLoad(id, reason):
            "The engine \(id) could not be loaded: \(reason)"
        case let .failedToStart(id, reason):
            "The engine \(id) could not start: \(reason)"
        case .pageClosed:
            "The page was closed."
        case .inUse:
            "The engine is rendering open pages. Quit Refrax, then remove it."
        case .unsupported:
            "The engine does not support this feature."
        case let .scriptFailed(message):
            message
        case let .malformedMessage(detail):
            "The engine sent a malformed message: \(detail)"
        }
    }
}
