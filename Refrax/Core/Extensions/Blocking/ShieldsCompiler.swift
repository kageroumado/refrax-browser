import CryptoKit
import Foundation
import Shields

/// One filter list's text, as the compiler reads it.
nonisolated struct ShieldsList: Sendable, Hashable {
    nonisolated enum Format: UInt32, Codable, Sendable {
        /// Adblock Plus / uBlock Origin syntax.
        case standard = 0
        /// Hosts-file syntax.
        case hosts = 1
    }

    let id: String
    let text: Data
    var format = Format.standard
    /// Lists Refrax trusts (uBlock Origin's own) may use scriptlets uBO marks `requiresTrust`.
    var isTrusted = false
    /// Whether the list's scriptlet injections (`##+js(…)`) apply. The library drops them
    /// otherwise, with adblock-rust's own line splitting and parser
    /// (`SHIELDS_LIST_NO_SCRIPTLETS`).
    var allowsScriptlets = true

    /// adblock-rust's permission mask for the list: bit 0 is uBO's trusted scriptlets.
    var permissions: UInt8 {
        isTrusted ? 1 : 0
    }

    /// `shields_filter_set_add_list_with_options` options for the list.
    var options: ShieldsListOptions {
        allowsScriptlets ? 0 : ShieldsListOptions(SHIELDS_LIST_NO_SCRIPTLETS)
    }
}

/// Identifies one build: every input that changes what the compiler writes.
///
/// `sha256(engine format ‖ ABI version ‖ WebKit pass version ‖ for each list in order: id ‖
/// sha256(filters) ‖ format ‖ permissions ‖ options ‖ sha256(resources))`. A crate bump
/// changes the engine format, so every cached DAT is rebuilt, which adblock-rust requires.
/// `filters` is the text with comment lines (`!`) emptied, so a list whose header alone changed
/// (`! Version`, `! Last modified`, hourly on uBO's quick fixes) keeps its key; the line count,
/// which the logger's line numbers depend on, still counts.
nonisolated struct ShieldsKey: Hashable, Sendable, CustomStringConvertible {
    let hex: String

    init(hex: String) {
        self.hex = hex
    }

    /// Whether `name` has a key's form: 64 lowercase hex digits, as build directories are named.
    static func isHex(_ name: String) -> Bool {
        name.utf8.count == 64 && name.utf8.allSatisfy { (48 ... 57).contains($0) || (97 ... 102).contains($0) }
    }

    init(lists: [ShieldsList], resources: Data, format: String = ShieldsEngine.format, passVersion: UInt32 = ShieldsEngine.webKitPassVersion) {
        var hasher = SHA256()
        func feed(_ string: String) {
            hasher.update(data: Data(string.utf8))
            hasher.update(data: Data([0]))
        }
        feed(format)
        feed("\(SHIELDS_ABI_VERSION)")
        feed("\(passVersion)")
        for list in lists {
            feed(list.id)
            feed(SHA256.hash(data: Self.filterContent(of: list.text)).hexString)
            feed("\(list.format.rawValue)")
            feed("\(list.permissions)")
            feed("\(list.options)")
        }
        feed(SHA256.hash(data: resources).hexString)
        self.hex = hasher.finalize().hexString
    }

    /// `text` with every comment line emptied.
    static func filterContent(of text: Data) -> Data {
        var content = Data(capacity: text.count)
        for line in text.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false) {
            if line.first != UInt8(ascii: "!") {
                content.append(contentsOf: line)
            }
            content.append(UInt8(ascii: "\n"))
        }
        return content
    }

    /// A short form for logs.
    var shortForm: String {
        String(hex.prefix(12))
    }

    var description: String {
        hex
    }
}

/// What one build wrote, read back from `manifest.json`.
nonisolated struct ShieldsManifest: Codable, Hashable, Sendable {
    nonisolated struct List: Codable, Hashable, Sendable {
        let id: String
        let sourceIndex: Int
        let sha256: String
        let stats: ShieldsListStats
    }

    nonisolated struct WebKit: Codable, Hashable, Sendable {
        let passVersion: Int
        let networkLists: Int
        let cosmeticLists: Int
        let scripts: Int
        let counts: ShieldsWebKitCounts
    }

    /// A file of the build, checked before use.
    nonisolated struct File: Codable, Hashable, Sendable {
        let size: Int
        let sha256: String
    }

    let key: String
    let format: String
    let lists: [List]
    /// The non-debug DAT the Chromium engine loads.
    let engineSHA256: String
    let resourcesSHA256: String
    let webKit: WebKit
    /// Every file of the build by its path in the build directory.
    let files: [String: File]
    let builtAt: Date
    /// Wall time of the build, for the Filters settings and measurements.
    let buildSeconds: Double
}

/// `shields_filter_set_stats` per list.
nonisolated struct ShieldsListStats: Codable, Hashable, Sendable {
    let sourceIndex: Int
    let network: Int
    let cosmetic: Int
    let scriptlets: Int
    let procedural: Int
    let invalid: Int
    let invalidExamples: [String]
}

/// The WebKit pass's rule and filter counts.
nonisolated struct ShieldsWebKitCounts: Codable, Hashable, Sendable {
    let networkRules: Int
    let exceptionRules: Int
    let importantRules: Int
    let redirectRules: Int
    let removeparamRules: Int
    let genericHideRules: Int
    let specificHideRules: Int
    let bundleHosts: Int
    let entities: Int
    /// Filters only the Chromium engine applies, by reason.
    let unsupported: [String: Int]

    var totalRules: Int {
        networkRules + exceptionRules + importantRules + redirectRules + removeparamRules
            + genericHideRules + specificHideRules
    }
}

/// A build on disk: `Filters/shields/<key>/`.
nonisolated struct ShieldsArtifacts: Sendable, Hashable {
    static let manifestName = "manifest.json"
    static let engineName = "engine.dat"
    static let debugEngineName = "engine-debug.dat"
    static let webKitDirectoryName = "webkit"
    static let resourcesName = "resources.json"

    let key: ShieldsKey
    let directory: URL
    let manifest: ShieldsManifest

    var engineURL: URL {
        directory.appending(path: Self.engineName)
    }

    var debugEngineURL: URL {
        directory.appending(path: Self.debugEngineName)
    }

    /// The resources the build used, for engines that load the DAT.
    var resourcesURL: URL {
        directory.appending(path: Self.resourcesName)
    }

    var webKitDirectory: URL {
        directory.appending(path: Self.webKitDirectoryName, directoryHint: .isDirectory)
    }

    func networkRulesURL(_ index: Int) -> URL {
        directory.appending(path: Self.networkRulesPath(index))
    }

    func cosmeticRulesURL(_ index: Int) -> URL {
        directory.appending(path: Self.cosmeticRulesPath(index))
    }

    static func networkRulesPath(_ index: Int) -> String {
        "\(webKitDirectoryName)/network-\(index).json"
    }

    static func cosmeticRulesPath(_ index: Int) -> String {
        "\(webKitDirectoryName)/cosmetic-\(index).json"
    }

    /// The WebKit rule list identifier for a rules file: its kind and a hash of its JSON, so a
    /// list whose rules did not change between builds is found in WebKit's store.
    func ruleListIdentifier(forPath path: String) -> String? {
        guard let file = manifest.files[path] else { return nil }
        let kind = path.contains("cosmetic") ? "cosmetic" : "network"
        return "\(ShieldsWebKit.identifierPrefix)\(kind).\(file.sha256.prefix(24))"
    }

    var scriptsURL: URL {
        directory.appending(path: Self.scriptsPath)
    }

    static let scriptsPath = "\(webKitDirectoryName)/scripts.json"

    /// Reads a finished build, or nil when `directory` holds none for `key` or one of its files
    /// is missing or has another size than the manifest records. Contents are hashed where they
    /// are read (``verifiedContents(ofPath:)``).
    init?(key: ShieldsKey, directory: URL) {
        let manifestURL = directory.appending(path: Self.manifestName)
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? ShieldsCompiler.decoder.decode(ShieldsManifest.self, from: data),
              manifest.key == key.hex, !manifest.files.isEmpty
        else { return nil }
        for (path, file) in manifest.files {
            let size = (try? FileManager.default.attributesOfItem(atPath: directory.appending(path: path).path)[.size]) as? Int
            guard size == file.size else { return nil }
        }
        self.key = key
        self.directory = directory
        self.manifest = manifest
    }

    /// The build in `directory` named by its manifest, when it is whole.
    init?(directory: URL) {
        let name = directory.lastPathComponent
        guard ShieldsKey.isHex(name) else { return nil }
        self.init(key: ShieldsKey(hex: name), directory: directory)
    }

    /// A file's bytes, when they hash to what the manifest records.
    func verifiedContents(ofPath path: String) throws -> Data {
        let data = try Data(contentsOf: directory.appending(path: path))
        guard let file = manifest.files[path], SHA256.hash(data: data).hexString == file.sha256 else {
            throw ShieldsError.status(SHIELDS_INVALID_DATA, operation: "verify \(path)")
        }
        return data
    }
}

/// Builds Shields engines and WebKit artifacts off the main actor, one build at a time.
///
/// Each build parses the union of the enabled lists once per filter set: a debug set (rule
/// text and locations, for the app's logger and the WebKit pass) and a plain set, whose DAT
/// goes to the Chromium engine. The debug DAT measured 71% larger and its engine 60% more
/// resident than the plain one, past the design's 40% budget, so the host gets the plain DAT
/// and Refrax attributes its log entries.
actor ShieldsCompiler {
    private enum Constants {
        /// Builds kept on disk besides the protected ones (the new, installed and published
        /// builds): the newest other one.
        static let keptBuilds = 1
        static let buildingPrefix = ".building-"
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }()

    /// The build for `lists` and `resources` under `root`, from disk when one exists.
    ///
    /// - Parameters:
    ///   - reusingCache: False rebuilds even when a build for the same key is on disk, and
    ///     replaces it: the caller found one of its files bad.
    ///   - protecting: Build keys pruning keeps (the installed and published ones).
    /// - Returns: The artifacts and, for a fresh build, the engine it built (resources
    ///   installed), so the caller can keep it without reading the DAT back.
    func build(
        lists: [ShieldsList],
        resources: Data,
        into root: URL,
        reusingCache: Bool = true,
        protecting: Set<String> = [],
    ) throws -> (artifacts: ShieldsArtifacts, engine: ShieldsEngine?) {
        let key = ShieldsKey(lists: lists, resources: resources)
        let directory = root.appending(path: key.hex, directoryHint: .isDirectory)
        if reusingCache, let cached = ShieldsArtifacts(key: key, directory: directory) {
            return (cached, nil)
        }

        let start = ContinuousClock.now
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appending(path: Constants.buildingPrefix + UUID().uuidString, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }

        let debugSet = try FilterSet(debug: true, lists: lists)
        let stats = try debugSet.stats()
        try Task.checkCancellation()

        let engine = try debugSet.buildEngine(resources: resources)
        try engine.serialized().write(to: staging.appending(path: ShieldsArtifacts.debugEngineName))
        try Task.checkCancellation()

        let webKitDirectory = staging.appending(path: ShieldsArtifacts.webKitDirectoryName, directoryHint: .isDirectory)
        let webKit = try debugSet.compileWebKit(engine: engine, into: webKitDirectory)
        try Task.checkCancellation()

        let hostDAT = try FilterSet(debug: false, lists: lists).buildEngine(resources: nil).serialized()
        try hostDAT.write(to: staging.appending(path: ShieldsArtifacts.engineName))
        try resources.write(to: staging.appending(path: ShieldsArtifacts.resourcesName))

        let elapsed = ContinuousClock.now - start
        let manifest = try ShieldsManifest(
            key: key.hex,
            format: ShieldsEngine.format,
            lists: zip(lists, stats).map { list, stats in
                ShieldsManifest.List(
                    id: list.id,
                    sourceIndex: stats.sourceIndex,
                    sha256: SHA256.hash(data: list.text).hexString,
                    stats: stats,
                )
            },
            engineSHA256: SHA256.hash(data: hostDAT).hexString,
            resourcesSHA256: SHA256.hash(data: resources).hexString,
            webKit: webKit,
            files: Self.fileRecords(in: staging),
            builtAt: .now,
            buildSeconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18,
        )
        try Self.encoder.encode(manifest).write(to: staging.appending(path: ShieldsArtifacts.manifestName))

        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.moveItem(at: staging, to: directory)
        pruneBuilds(in: root, keeping: protecting.union([key.hex]))

        guard let artifacts = ShieldsArtifacts(key: key, directory: directory) else {
            throw ShieldsError.status(SHIELDS_INVALID_DATA, operation: "manifest")
        }
        return (artifacts, engine)
    }

    /// Sizes and hashes of every file under `directory`, by relative path.
    private static func fileRecords(in directory: URL) throws -> [String: ShieldsManifest.File] {
        var records: [String: ShieldsManifest.File] = [:]
        let names = [ShieldsArtifacts.engineName, ShieldsArtifacts.debugEngineName, ShieldsArtifacts.resourcesName]
        let webKitNames = try FileManager.default.contentsOfDirectory(
            atPath: directory.appending(path: ShieldsArtifacts.webKitDirectoryName).path,
        ).map { "\(ShieldsArtifacts.webKitDirectoryName)/\($0)" }
        for path in names + webKitNames {
            let data = try Data(contentsOf: directory.appending(path: path), options: .mappedIfSafe)
            records[path] = ShieldsManifest.File(size: data.count, sha256: SHA256.hash(data: data).hexString)
        }
        return records
    }

    /// Removes all but the protected builds and the newest other one (and abandoned staging
    /// directories).
    private func pruneBuilds(in root: URL, keeping protected: Set<String>) {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
        ) else { return }
        let builds = entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { lhs, rhs in
                let left = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
        var kept = 0
        for build in builds {
            let name = build.lastPathComponent
            let isStaging = name.hasPrefix(Constants.buildingPrefix)
            guard isStaging || ShieldsKey.isHex(name), !protected.contains(name) else {
                continue
            }
            if !isStaging, kept < Constants.keptBuilds {
                kept += 1
                continue
            }
            try? fileManager.removeItem(at: build)
        }
    }
}

// MARK: - Filter Sets

/// An adblock-rust filter set; owns its handle.
private final nonisolated class FilterSet {
    let handle: OpaquePointer

    init(debug: Bool, lists: [ShieldsList]) throws(ShieldsError) {
        guard let handle = shields_filter_set_new(debug) else {
            throw .status(SHIELDS_PANIC, operation: "filter_set_new")
        }
        self.handle = handle
        for list in lists {
            let status = list.text.withUnsafeBytes { bytes in
                shields_filter_set_add_list_with_options(
                    handle,
                    bytes.bindMemory(to: UInt8.self).baseAddress,
                    bytes.count,
                    list.format.rawValue,
                    list.permissions,
                    list.options,
                    nil,
                )
            }
            guard status == SHIELDS_OK else { throw .status(status, operation: "add_list \(list.id)") }
        }
    }

    deinit {
        shields_filter_set_free(handle)
    }

    func stats() throws(ShieldsError) -> [ShieldsListStats] {
        var buffer = ShieldsBuffer()
        let status = shields_filter_set_stats(handle, &buffer)
        defer { shields_buffer_free(&buffer) }
        guard status == SHIELDS_OK else { throw .status(status, operation: "stats") }
        do {
            return try JSONDecoder().decode([ShieldsListStats].self, from: buffer.contents)
        } catch {
            throw .status(SHIELDS_INVALID_DATA, operation: "stats")
        }
    }

    /// A new engine; `resources` installed when given (a DAT never carries them).
    func buildEngine(resources: Data?) throws(ShieldsError) -> ShieldsEngine {
        guard let engine = shields_engine_build(handle) else {
            throw .status(SHIELDS_PANIC, operation: "engine_build")
        }
        guard let resources else { return ShieldsEngine(adopting: engine) }
        let status = resources.withUnsafeBytes { bytes in
            shields_engine_use_resources(engine, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
        }
        guard status == SHIELDS_OK else {
            shields_engine_free(engine)
            throw .status(status, operation: "use_resources")
        }
        return ShieldsEngine(adopting: engine)
    }

    func compileWebKit(engine: ShieldsEngine, into directory: URL) throws(ShieldsError) -> ShieldsManifest.WebKit {
        var buffer = ShieldsBuffer()
        let status = engine.withHandle { engineHandle in
            shields_webkit_compile(handle, engineHandle, nil, 0, directory.path, &buffer)
        }
        defer { shields_buffer_free(&buffer) }
        guard status == SHIELDS_OK else { throw .status(status, operation: "webkit_compile") }
        do {
            return try JSONDecoder().decode(ShieldsManifest.WebKit.self, from: buffer.contents)
        } catch {
            throw .status(SHIELDS_INVALID_DATA, operation: "webkit_compile summary")
        }
    }
}
