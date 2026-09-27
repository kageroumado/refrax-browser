import CryptoKit
import Foundation
@testable import Refrax
import Testing

@Suite("Engine distribution", .tags(.engines))
@MainActor
struct EngineDistributionTests {
    private let key = Curve25519.Signing.PrivateKey()
    private let engine = EngineID(rawValue: "website.refrax.engine.chromium")

    private func release(
        version: String = "152.0.7977.82-r1", url: String? = nil, bytes: Data = Data("engine".utf8),
        contract: String = "1.1", minimumSystemVersion: String = "26.0",
    ) -> EngineCatalog.Release {
        EngineCatalog.Release(
            version: version,
            url: URL(string: url ?? "https://github.com/kageroumado/refrax-engines/releases/download/chromium%2F\(version)/Refrax-Chromium-\(version).zip")!,
            sha256: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(),
            sizeBytes: Int64(bytes.count),
            contract: contract,
            minimumSystemVersion: minimumSystemVersion,
            notes: nil,
        )
    }

    private func signatureFile(for bytes: Data) throws -> Data {
        try Data(key.signature(for: bytes).base64EncodedString().utf8)
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "engine-distribution-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A bundle EngineBundle reads as an engine: Info.plist only, no code.
    private func makeEngineBundle(in directory: URL, id: String = "website.refrax.engine.chromium", build: String = "152.0.7977.82-r1", contract: String = "1.1") throws -> URL {
        let bundle = directory.appending(path: "Refrax Chromium.engine", directoryHint: .isDirectory)
        let contents = bundle.appending(path: "Contents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": id, "CFBundlePackageType": "BNDL", "NSPrincipalClass": "RFXChromiumEngine",
            "RFXEngineContractVersion": contract, "RFXEngineBuild": build, "RFXEngineDisplayName": "Chromium",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appending(path: "Info.plist"))
        return bundle
    }

    private func zip(_ bundle: URL, to archive: URL) throws {
        let ditto = Process()
        ditto.executableURL = URL(filePath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", "--keepParent", bundle.path(percentEncoded: false), archive.path(percentEncoded: false)]
        try ditto.run()
        ditto.waitUntilExit()
        #expect(ditto.terminationStatus == 0)
    }

    @Test("Release versions order by upstream version, then revision, never lexically")
    func versions() throws {
        let r1 = try #require(EngineReleaseVersion("152.0.7977.82-r1"))
        #expect(r1.description == "152.0.7977.82-r1")
        #expect(try #require(EngineReleaseVersion("152.0.7977.82-r2")) > r1)
        #expect(try #require(EngineReleaseVersion("152.0.7977.100-r1")) > r1)
        #expect(try #require(EngineReleaseVersion("153.0.1.0-r1")) > #require(EngineReleaseVersion("152.9.9999.99-r9")))
        #expect(try #require(EngineReleaseVersion("152.0.7977.82-r10")) > #require(EngineReleaseVersion("152.0.7977.82-r9")))
        for local in ["dev-28", "release-4", "152.0.7977.82", "152.0.x.82-r1", "152.0.7977.82-rX", ""] {
            #expect(EngineReleaseVersion(local) == nil, "\(local)")
        }
    }

    @Test("The catalog validates what Refrax would refuse to install")
    func catalogProblems() {
        let good = EngineCatalog(schema: 1, engines: [engine.rawValue: .init(displayName: "Chromium", channels: ["stable": release()])])
        #expect(good.problems().isEmpty)
        #expect(good.release(for: engine)?.version == "152.0.7977.82-r1")

        let foreign = release(url: "https://example.com/Refrax-Chromium-152.0.7977.82-r1.zip")
        let wrongName = release(url: "https://github.com/kageroumado/refrax-engines/releases/download/x/Refrax-Chromium.zip")
        let noStable = EngineCatalog(schema: 1, engines: [engine.rawValue: .init(displayName: "Chromium", channels: ["beta": foreign])])
        let problems = noStable.problems()
        #expect(problems.contains { $0.contains("no stable channel") })
        #expect(problems.contains { $0.contains("not a refrax-engines release asset") })
        #expect(EngineCatalog(schema: 1, engines: [engine.rawValue: .init(displayName: "C", channels: ["stable": wrongName])])
            .problems().contains { $0.contains("does not carry the version") })
        #expect(throws: EngineDistributionError.self) { try EngineCatalog.decode(Data(#"{"schema":2,"engines":{}}"#.utf8)) }
    }

    @Test("Downloads are accepted only from refrax-engines releases over HTTPS")
    func downloadURLs() throws {
        let allowed = "https://github.com/kageroumado/refrax-engines/releases/download/catalog/engines.json"
        #expect(EngineSignature.isAllowedDownloadURL(try #require(URL(string: allowed))))
        for url in [
            "http://github.com/kageroumado/refrax-engines/releases/download/catalog/engines.json",
            "https://github.com/kageroumado/refrax-browser/releases/download/v1/Refrax.dmg",
            "https://github.com.evil.test/kageroumado/refrax-engines/releases/download/x/y.zip",
            "https://user@github.com/kageroumado/refrax-engines/releases/download/x/y.zip",
        ] {
            #expect(!EngineSignature.isAllowedDownloadURL(try #require(URL(string: url))), "\(url)")
        }
        #expect(EngineSignature.signatureURL(for: EngineCatalog.url).absoluteString == allowed + ".sig")
    }

    @Test("An archive must match the catalog's size, hash and signature")
    func verifyArchive() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data("the engine".utf8)
        let archive = directory.appending(path: "Refrax-Chromium-152.0.7977.82-r1.zip")
        try bytes.write(to: archive)
        let release = release(bytes: bytes)
        let signature = try signatureFile(for: bytes)

        try EngineInstaller.verify(archive, against: release, signatureFile: signature, key: key.publicKey)

        let otherKey = Curve25519.Signing.PrivateKey().publicKey
        #expect(throws: EngineDistributionError.signatureInvalid(archive.lastPathComponent)) {
            try EngineInstaller.verify(archive, against: release, signatureFile: signature, key: otherKey)
        }
        #expect(throws: EngineDistributionError.signatureMalformed) {
            try EngineInstaller.verify(archive, against: release, signatureFile: Data("not base64".utf8), key: key.publicKey)
        }
        try Data("the engine!".utf8).write(to: archive)
        #expect(throws: EngineDistributionError.sizeMismatch(expected: Int64(bytes.count), actual: Int64(bytes.count + 1))) {
            try EngineInstaller.verify(archive, against: release, signatureFile: signature, key: key.publicKey)
        }
        try Data("THE engine".utf8).write(to: archive)
        #expect(throws: EngineDistributionError.hashMismatch) {
            try EngineInstaller.verify(archive, against: release, signatureFile: signature, key: key.publicKey)
        }
    }

    @Test("Unpacking yields the catalog's engine and release, or refuses")
    func unpack() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "source", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let archive = directory.appending(path: "engine.zip")
        try zip(makeEngineBundle(in: source), to: archive)

        func unpack(_ release: EngineCatalog.Release, as id: EngineID? = nil) throws -> EngineBundle {
            let staging = directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            return try EngineInstaller.unpack(archive, in: staging, expecting: release, engine: id ?? engine)
        }
        let bundle = try unpack(release())
        #expect(bundle.descriptor.id == engine)
        #expect(bundle.descriptor.version == "152.0.7977.82-r1")
        #expect(throws: EngineDistributionError.self) { try unpack(release(version: "152.0.7977.82-r2")) }
        #expect(throws: EngineDistributionError.self) { try unpack(release(), as: EngineID(rawValue: "other.engine")) }
    }

    @Test("A newer contract than Refrax speaks is refused at unpack")
    func unpackRefusesNewerContract() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let archive = directory.appending(path: "engine.zip")
        let current = EngineContractVersion.current
        try zip(makeEngineBundle(in: directory, contract: "\(current.major).\(current.minor + 1)"), to: archive)
        let staging = directory.appending(path: "staging", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        #expect(throws: EngineError.self) {
            try EngineInstaller.unpack(archive, in: staging, expecting: release(), engine: engine)
        }
    }

    @Test("A running engine's update waits in .pending; the registry installs it and ignores the folder")
    func pendingInstall() throws {
        let support = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: support) }
        let engines = support.appending(path: "Engines", directoryHint: .isDirectory)
        let downloads = support.appending(path: "downloads", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)

        let outcome = try EngineInstaller.place(
            makeEngineBundle(in: downloads), engine: engine, in: engines, replacingRunningEngine: true,
        )
        #expect(outcome == .pendingRelaunch)
        #expect(!FileManager.default.fileExists(atPath: engines.appending(path: engine.rawValue).path(percentEncoded: false)))

        let registry = EngineRegistry(applicationSupport: support)
        #expect(registry.descriptor(for: engine)?.version == "152.0.7977.82-r1")
        #expect(!FileManager.default.fileExists(atPath: engines.appending(path: ".pending/\(engine.rawValue)").path(percentEncoded: false)))
        #expect(registry.descriptors.count == 2, "the .pending folder is never scanned as an engine")
    }

    @Test("Offers new engines and newer releases, never a local build or one Refrax can't run")
    func offers() {
        let catalog = EngineCatalog(schema: 1, engines: [
            engine.rawValue: .init(displayName: "Chromium", channels: ["stable": release(version: "152.0.7977.82-r2")]),
            "future.engine": .init(displayName: "Future", channels: ["stable": release(version: "1.0-r1", contract: "9.0")]),
            "later.os": .init(displayName: "Later", channels: ["stable": release(version: "1.0-r1", minimumSystemVersion: "99.0")]),
        ])
        func offers(installed: String?) -> [EngineDistribution.Offer] {
            EngineDistribution.offers(in: catalog) { $0 == engine ? installed : nil }
        }
        #expect(offers(installed: nil).map(\.id) == [engine])
        #expect(offers(installed: nil).first?.isUpdate == false)
        #expect(offers(installed: "152.0.7977.82-r1").first?.isUpdate == true)
        #expect(offers(installed: "152.0.7977.82-r2").isEmpty)
        #expect(offers(installed: "152.0.7977.82-r3").isEmpty)
        #expect(offers(installed: "dev-28").isEmpty)
    }
}
