import CryptoKit
import Foundation
import Security
import Testing
@testable import Refrax

/// The native messaging wire format: a little-endian 32-bit length, then UTF-8 JSON.
@Suite("Native message framing")
struct NativeMessageFramingTests {
    @Test
    func `A framed message starts with its JSON length in little-endian order`() throws {
        let frame = try NativeMessageFraming.frame(["text": "hi"])
        let json = Data(#"{"text":"hi"}"#.utf8)
        #expect(frame.prefix(4) == Data([UInt8(json.count), 0, 0, 0]))
        #expect(frame.dropFirst(4) == json)
    }

    @Test
    func `Messages split across reads come out whole and in order`() throws {
        let stream = try NativeMessageFraming.frame(["n": 1]) + NativeMessageFraming.frame("two") + NativeMessageFraming.frame([3])
        var decoder = NativeMessageFraming.Decoder()
        var bodies: [Data] = []
        for byte in stream {
            bodies += try decoder.append(Data([byte]))
        }
        let values = try bodies.map(NativeMessageFraming.decode)
        #expect(values.count == 3)
        #expect((values[0] as? [String: Int]) == ["n": 1])
        #expect((values[1] as? String) == "two")
        #expect((values[2] as? [Int]) == [3])
    }

    @Test
    func `A header announcing more than a megabyte ends the stream`() {
        var decoder = NativeMessageFraming.Decoder()
        var length = UInt32(NativeMessageFraming.maximumIncomingLength + 1).littleEndian
        #expect(throws: NativeMessagingError.messageTooLarge) {
            _ = try decoder.append(Data(bytes: &length, count: 4))
        }
    }

    @Test
    func `A value JSON cannot hold is refused before it is sent`() {
        #expect(throws: NativeMessagingError.invalidMessage) {
            _ = try NativeMessageFraming.frame(Date())
        }
    }
}

/// Finding a host's manifest and deciding whether an extension may start it.
@Suite("Native messaging host lookup")
struct NativeMessagingHostLocatorTests {
    private static let chromeID = "abcdefghijklmnopabcdefghijklmnop"
    private static let geckoID = "{446900e4-71c2-419f-a6a7-df9c091e268b}"
    private static let refraxOrigin = "webkit-extension://6f9619ff-8b86-d011-b42d-00cf4fc964ff/"

    private func identity(verified: String? = nil, claimedChrome: String? = nil, claimedGecko: String? = nil) -> ExtensionIdentity {
        ExtensionIdentity(verifiedChromeID: verified, claimedChromeID: claimedChrome, claimedGeckoID: claimedGecko, refraxOrigin: Self.refraxOrigin)
    }

    @Test(arguments: ["com.8bit.bitwarden", "a", "a_b.c9", "org.example.host_1"])
    func `Chrome's host names are valid`(name: String) {
        #expect(NativeMessagingHostLocator.isValidHostName(name))
    }

    @Test(arguments: ["", "Com.Example", "a..b", ".a", "a.", "../evil", "a/b", "a-b", "a b", "é"])
    func `Other host names are invalid`(name: String) {
        #expect(!NativeMessagingHostLocator.isValidHostName(name))
    }

    @Test
    func `A verified Chrome ID starts a Chrome-format host with its origin, without asking`() throws {
        let fixture = try EchoHostFixture(allowedOrigins: [ExtensionIdentity.chromeOrigin(Self.chromeID)])
        let host = try fixture.locator.host(named: fixture.name, for: identity(verified: Self.chromeID))
        #expect(host.executableURL == fixture.executable.resolvingSymlinksInPath())
        #expect(host.arguments == [ExtensionIdentity.chromeOrigin(Self.chromeID)])
        #expect(!host.requiresConsent)
    }

    @Test
    func `A Chrome ID or add-on ID only claimed in the manifest needs the user's consent`() throws {
        let chrome = try EchoHostFixture(allowedOrigins: [ExtensionIdentity.chromeOrigin(Self.chromeID)])
        #expect(try chrome.locator.host(named: chrome.name, for: identity(claimedChrome: Self.chromeID)).requiresConsent)

        let firefox = try EchoHostFixture(allowedExtensions: [Self.geckoID])
        let host = try firefox.locator.host(named: firefox.name, for: identity(claimedGecko: Self.geckoID))
        #expect(host.requiresConsent)
        #expect(host.arguments == [firefox.directory.appendingPathComponent("\(firefox.name).json").path, Self.geckoID])
    }

    @Test
    func `A verified match in a later folder wins over a claimed one in an earlier folder`() throws {
        let claimed = try EchoHostFixture(allowedExtensions: [Self.geckoID])
        let verified = try EchoHostFixture(allowedOrigins: [ExtensionIdentity.chromeOrigin(Self.chromeID)])
        let locator = NativeMessagingHostLocator(refraxDirectory: nil, browserDirectories: [claimed.directory, verified.directory])
        let host = try locator.host(named: verified.name, for: identity(verified: Self.chromeID, claimedGecko: Self.geckoID))
        #expect(!host.requiresConsent)
        #expect(host.executableURL == verified.executable.resolvingSymlinksInPath())
    }

    @Test
    func `Refrax's own folder admits an extension by the origin Refrax serves it from, and nothing else`() throws {
        let own = try EchoHostFixture(allowedOrigins: [Self.refraxOrigin], allowedExtensions: [Self.geckoID])
        let locator = NativeMessagingHostLocator(refraxDirectory: own.directory, browserDirectories: [])
        let host = try locator.host(named: own.name, for: identity())
        #expect(host.arguments == [Self.refraxOrigin])
        #expect(!host.requiresConsent)

        let stranger = ExtensionIdentity(
            verifiedChromeID: nil, claimedChromeID: nil, claimedGeckoID: Self.geckoID,
            refraxOrigin: "webkit-extension://00000000-0000-0000-0000-000000000000/",
        )
        #expect(throws: NativeMessagingError.forbidden) {
            try locator.host(named: own.name, for: stranger)
        }
    }

    @Test
    func `An extension the manifest does not list is forbidden`() throws {
        let fixture = try EchoHostFixture(allowedOrigins: ["chrome-extension://pppppppppppppppppppppppppppppppp/"])
        #expect(throws: NativeMessagingError.forbidden) {
            try fixture.locator.host(named: fixture.name, for: identity(verified: Self.chromeID, claimedGecko: Self.geckoID))
        }
    }

    @Test
    func `A name without a manifest is not found, and an invalid name is never looked up`() throws {
        let fixture = try EchoHostFixture(allowedOrigins: [])
        #expect(throws: NativeMessagingError.hostNotFound) {
            try fixture.locator.host(named: "refrax.test.missing", for: identity(verified: Self.chromeID))
        }
        #expect(throws: NativeMessagingError.invalidHostName) {
            try fixture.locator.host(named: "../\(fixture.name)", for: identity(verified: Self.chromeID))
        }
    }

    @Test
    func `A manifest naming another host, a relative path, or a file that cannot run is skipped`() throws {
        let origin = ExtensionIdentity.chromeOrigin(Self.chromeID)
        let fixture = try EchoHostFixture(allowedOrigins: [origin])
        let manifestURL = fixture.directory.appendingPathComponent("\(fixture.name).json")
        let variants: [[String: Any]] = [
            ["name": "refrax.test.other", "path": fixture.executable.path, "type": "stdio"],
            ["name": fixture.name, "path": "echo-host.pl", "type": "stdio"],
            ["name": fixture.name, "path": fixture.directory.path, "type": "stdio"],
            ["name": fixture.name, "path": fixture.executable.path, "type": "socket"],
        ]
        for variant in variants {
            var manifest = variant
            manifest["allowed_origins"] = [origin]
            try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
            #expect(throws: NativeMessagingError.self) {
                try fixture.locator.host(named: fixture.name, for: identity(verified: Self.chromeID))
            }
        }
    }

    @Test
    func `Refrax's folder is its own, and each browser's user folder comes before its system one`() {
        let home = URL(fileURLWithPath: "/Users/someone")
        let storage = URL(fileURLWithPath: "/Users/someone/Library/Application Support/website.refrax.browser")
        let locator = NativeMessagingHostLocator.standard(home: home, appStorage: storage)
        #expect(locator.refraxDirectory?.path == "/Users/someone/Library/Application Support/website.refrax.browser/NativeMessagingHosts")
        #expect(locator.browserDirectories.map(\.path) == [
            "/Users/someone/Library/Application Support/Google/Chrome/NativeMessagingHosts",
            "/Library/Google/Chrome/NativeMessagingHosts",
            "/Users/someone/Library/Application Support/Chromium/NativeMessagingHosts",
            "/Library/Application Support/Chromium/NativeMessagingHosts",
            "/Users/someone/Library/Application Support/Mozilla/NativeMessagingHosts",
            "/Library/Application Support/Mozilla/NativeMessagingHosts",
        ])
    }
}

/// The identifiers native messaging hosts know an extension by.
@Suite("Extension identity")
struct ExtensionIdentityTests {
    @Test
    func `The Chrome ID is the key's SHA-256 written in the letters a to p`() {
        #expect(ExtensionIdentity.chromeID(forPublicKey: Data("refrax-test-public-key".utf8)) == "bhgcaanfkdmlhnjkbofcfcibigelhbee")
    }

    @Test
    func `What the manifest states is claimed, never verified`() {
        let manifest: [String: Any] = [
            "key": "cmVmcmF4LXRlc3QtcHVibGljLWtleQ==",
            "browser_specific_settings": ["gecko": ["id": "addon@darkreader.org"]],
        ]
        let identity = ExtensionIdentity(manifest: manifest, verifiedChromeID: nil, refraxOrigin: "webkit-extension://a/")
        #expect(identity.claimedChromeID == "bhgcaanfkdmlhnjkbofcfcibigelhbee")
        #expect(identity.claimedGeckoID == "addon@darkreader.org")
        #expect(identity.verifiedChromeID == nil)
        let legacy = ExtensionIdentity(manifest: ["applications": ["gecko": ["id": "x@y"]]], verifiedChromeID: nil, refraxOrigin: "")
        #expect(legacy.claimedGeckoID == "x@y")
    }
}

/// CRX3 files: the ZIP after the header, and the extension ID the developer's signature proves.
@Suite("Extension archives")
struct ExtensionArchiveTests {
    private let zip = Data("PK\u{3}\u{4}payload".utf8)

    @Test
    func `A CRX signed by the key its ID names yields that ID, whatever else signed it`() throws {
        let store = try TestArchives.rsaSigner()
        let developer = try TestArchives.rsaSigner()
        let file = try TestArchives.crx(zip: zip, developer: developer, signers: [store, developer])

        let contents = try ExtensionArchive.contents(ofCRX: file)

        #expect(contents.zip == zip)
        #expect(contents.chromeID == ExtensionIdentity.chromeID(forPublicKey: developer.spki))
    }

    @Test
    func `An ECDSA proof verifies too`() throws {
        let developer = try TestArchives.ecdsaSigner()
        let file = try TestArchives.crx(zip: zip, developer: developer, signers: [developer])
        #expect(try ExtensionArchive.contents(ofCRX: file).chromeID == ExtensionIdentity.chromeID(forPublicKey: developer.spki))
    }

    @Test
    func `A CRX whose payload changed after signing, or that the named key never signed, is refused`() throws {
        let developer = try TestArchives.rsaSigner()
        let other = try TestArchives.rsaSigner()
        var tampered = try TestArchives.crx(zip: zip, developer: developer, signers: [developer])
        tampered[tampered.count - 1] ^= 0xFF
        #expect(throws: ExtensionError.invalidSignature) {
            try ExtensionArchive.contents(ofCRX: tampered)
        }

        let unsigned = try TestArchives.crx(zip: zip, developer: developer, signers: [other])
        #expect(throws: ExtensionError.invalidSignature) {
            try ExtensionArchive.contents(ofCRX: unsigned)
        }
    }

    @Test
    func `Every proof must verify, not only the developer's`() throws {
        let developer = try TestArchives.rsaSigner()
        let store = try TestArchives.rsaSigner()
        let signed = TestArchives.signedHeaderData(for: developer.spki)
        let message = TestArchives.signedMessage(signedHeaderData: signed, zip: zip)
        let header = try TestArchives.proof(by: developer, signature: developer.sign(message))
            + TestArchives.proof(by: store, signature: Data(repeating: 1, count: 256))
            + TestArchives.lengthDelimited(10_000, signed)
        #expect(throws: ExtensionError.invalidSignature) {
            try ExtensionArchive.contents(ofCRX: TestArchives.crx(header: header, zip: zip))
        }
    }

    @Test
    func `A field that appears twice counts by its last occurrence`() throws {
        let developer = try TestArchives.rsaSigner()
        let decoy = try TestArchives.rsaSigner()
        let signed = TestArchives.signedHeaderData(for: developer.spki)
        let message = TestArchives.signedMessage(signedHeaderData: signed, zip: zip)
        let header = try TestArchives.proof(by: developer, signature: developer.sign(message))
            + TestArchives.lengthDelimited(10_000, TestArchives.signedHeaderData(for: decoy.spki))
            + TestArchives.lengthDelimited(10_000, signed)
        #expect(try ExtensionArchive.contents(ofCRX: TestArchives.crx(header: header, zip: zip)).chromeID
            == ExtensionIdentity.chromeID(forPublicKey: developer.spki))

        // The last header data names the decoy, which signed nothing.
        let swapped = try TestArchives.proof(by: developer, signature: developer.sign(message))
            + TestArchives.lengthDelimited(10_000, signed)
            + TestArchives.lengthDelimited(10_000, TestArchives.signedHeaderData(for: decoy.spki))
        #expect(throws: ExtensionError.invalidSignature) {
            try ExtensionArchive.contents(ofCRX: TestArchives.crx(header: swapped, zip: zip))
        }
    }

    @Test
    func `A header longer than the file, or anything but a CRX3 file, is refused`() {
        var file = TestArchives.crx(header: Data(count: 8), zip: zip)
        file.replaceSubrange(8 ..< 12, with: [0xFF, 0xFF, 0xFF, 0x7F])
        #expect(throws: ExtensionError.invalidArchiveFormat) {
            try ExtensionArchive.contents(ofCRX: file)
        }
        #expect(throws: ExtensionError.invalidArchiveFormat) {
            try ExtensionArchive.contents(ofCRX: Data("PK\u{3}\u{4}".utf8))
        }
    }

    @Test
    func `An archive with a path out of it, an absolute path, or a symbolic link is refused`() throws {
        let file: UInt32 = 0o100644
        let link: UInt32 = 0o120777
        try ZipInspection.check(TestArchives.centralDirectory([("manifest.json", file, 10), ("js/a.js", file, 10)]))
        let unsafe: [[(name: String, mode: UInt32, size: UInt32)]] = [
            [("../outside.js", file, 10)],
            [("js/../../outside.js", file, 10)],
            [("/etc/hosts", file, 10)],
            [("link", link, 10)],
        ]
        for entries in unsafe {
            #expect(throws: ExtensionError.invalidArchiveFormat) {
                try ZipInspection.check(TestArchives.centralDirectory(entries))
            }
        }
    }

    @Test
    func `A symbolic link counts whatever system the archive says made it`() {
        let msDOS = 0x0014
        #expect(throws: ExtensionError.invalidArchiveFormat) {
            try ZipInspection.check(TestArchives.centralDirectory([("link", 0o120777, 10)], madeBy: msDOS))
        }
        #expect(throws: ExtensionError.invalidArchiveFormat) {
            try ZipInspection.check(TestArchives.centralDirectory([("fifo", 0o010644, 0)], madeBy: msDOS))
        }
    }

    @Test
    func `A ZIP64 archive, or one whose end record miscounts its directory, is refused`() {
        let file: UInt32 = 0o100644
        let entries: [(name: String, mode: UInt32, size: UInt32)] = [("a.js", file, 1), ("b.js", file, 1)]
        #expect(throws: ExtensionError.invalidArchiveFormat) {
            try ZipInspection.check(TestArchives.centralDirectory(entries, zip64Locator: true))
        }
        #expect(throws: ExtensionError.invalidArchiveFormat) {
            try ZipInspection.check(TestArchives.centralDirectory(entries, declaredCount: 1))
        }
    }

    @Test
    func `An entry that inflates past its declared size stops the extraction and leaves nothing`() async throws {
        let folder = try ExtensionFixture(files: [
            "manifest.json": #"{"manifest_version": 3, "name": "Big", "version": "1.0"}"#,
            "big.bin": String(repeating: "0", count: 200_000),
        ]).write()
        var zip = try TestArchives.zip(folder)
        // Declare 100 bytes for big.bin in the central directory, which the pre-check sums.
        let name = Data("big.bin".utf8)
        let signature = Data([0x50, 0x4B, 0x01, 0x02])
        var search = zip.startIndex
        var patched = false
        while let range = zip.range(of: signature, in: search ..< zip.endIndex) {
            let nameLength = Int(zip[range.lowerBound + 28]) | Int(zip[range.lowerBound + 29]) << 8
            let nameStart = range.lowerBound + 46
            if zip[nameStart ..< nameStart + nameLength] == name {
                zip.replaceSubrange(range.lowerBound + 24 ..< range.lowerBound + 28, with: [100, 0, 0, 0])
                patched = true
            }
            search = range.upperBound
        }
        #expect(patched)
        try ZipInspection.check(zip)

        let archive = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).xpi")
        try zip.write(to: archive)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        await #expect(throws: ExtensionError.invalidArchiveFormat) {
            try await ExtensionArchive.extract(archive, into: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test(.timeLimit(.minutes(1)))
    func `A deflated entry whose stream breaks off is refused, never inflated forever`() async throws {
        let folder = try ExtensionFixture(files: [
            "manifest.json": #"{"manifest_version": 3, "name": "Cut", "version": "1.0"}"#,
            "cut.js": (0 ..< 20_000).map { "var v\($0) = \($0 * 7_919 % 104_729);" }.joined(separator: "\n"),
        ]).write()
        var zip = try TestArchives.zip(folder)
        // Blank the second half of cut.js's compressed bytes, behind its local header.
        let name = Data("cut.js".utf8)
        let signature = Data([0x50, 0x4B, 0x03, 0x04])
        var search = zip.startIndex
        var cut = false
        while let range = zip.range(of: signature, in: search ..< zip.endIndex) {
            let start = range.lowerBound
            let compressedSize = Int(zip[start + 18]) | Int(zip[start + 19]) << 8 | Int(zip[start + 20]) << 16 | Int(zip[start + 21]) << 24
            let nameLength = Int(zip[start + 26]) | Int(zip[start + 27]) << 8
            let extraLength = Int(zip[start + 28]) | Int(zip[start + 29]) << 8
            if zip[start + 30 ..< start + 30 + nameLength] == name, compressedSize > 2 {
                let body = start + 30 + nameLength + extraLength
                zip.replaceSubrange(body + compressedSize / 2 ..< body + compressedSize, with: Data(count: compressedSize - compressedSize / 2))
                cut = true
            }
            search = range.upperBound
        }
        #expect(cut)

        let archive = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).xpi")
        try zip.write(to: archive)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        await #expect(throws: (any Error).self) {
            try await ExtensionArchive.extract(archive, into: destination)
        }
        #expect(!FileManager.default.fileExists(atPath: destination.path))
    }

    @Test
    func `An honest archive unpacks, and an unpacked tree with a link in it is refused`() async throws {
        let folder = try ExtensionFixture(files: [
            "manifest.json": #"{"manifest_version": 3, "name": "Small", "version": "1.0"}"#,
            "js/a.js": "console.log(1);",
        ]).write()
        let archive = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).xpi")
        try TestArchives.zip(folder).write(to: archive)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try await ExtensionArchive.extract(archive, into: destination)
        #expect(try String(contentsOf: destination.appendingPathComponent("js/a.js"), encoding: .utf8) == "console.log(1);")
        try ExtractedTree.verify(destination)

        try FileManager.default.createSymbolicLink(atPath: destination.appendingPathComponent("js/link").path, withDestinationPath: "/etc")
        #expect(throws: ExtensionError.invalidArchiveFormat) {
            try ExtractedTree.verify(destination)
        }
    }

    @Test
    func `An archive that unpacks past the size limit is refused`() {
        let file: UInt32 = 0o100644
        #expect(throws: ExtensionError.invalidArchiveFormat) {
            try ZipInspection.check(TestArchives.centralDirectory([("a", file, 0xF000_0000), ("b", file, 0xF000_0000)]))
        }
    }

    @Test
    func `The manifest loses empty commands and keeps the rest`() {
        let manifest: [String: Any] = [
            "commands": ["_execute_browser_action": [String: Any](), "toggle": ["description": "Toggle"]],
            "browser_specific_settings": ["gecko": ["id": "addon@example.org"]],
        ]
        let fixed = ExtensionArchive.fixedManifest(manifest)
        #expect((fixed["commands"] as? [String: Any])?.keys.sorted() == ["toggle"])
        #expect(fixed["browser_specific_settings"] != nil)
        #expect(fixed["key"] == nil)
    }
}
