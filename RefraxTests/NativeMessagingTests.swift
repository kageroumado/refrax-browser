import CryptoKit
import Foundation
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
    private let chromeIdentity = ExtensionIdentity(chromeID: "abcdefghijklmnopabcdefghijklmnop", geckoID: nil)
    private let firefoxIdentity = ExtensionIdentity(chromeID: nil, geckoID: "{446900e4-71c2-419f-a6a7-df9c091e268b}")

    @Test(arguments: ["com.8bit.bitwarden", "a", "a_b.c9", "org.example.host_1"])
    func `Chrome's host names are valid`(name: String) {
        #expect(NativeMessagingHostLocator.isValidHostName(name))
    }

    @Test(arguments: ["", "Com.Example", "a..b", ".a", "a.", "../evil", "a/b", "a-b", "a b", "é"])
    func `Other host names are invalid`(name: String) {
        #expect(!NativeMessagingHostLocator.isValidHostName(name))
    }

    @Test
    func `A Chrome-format host starts with the caller's origin`() throws {
        let fixture = try EchoHostFixture(allowedOrigins: ["chrome-extension://abcdefghijklmnopabcdefghijklmnop/"])
        let host = try fixture.locator.host(named: fixture.name, for: chromeIdentity)
        #expect(host.executableURL == fixture.executable.resolvingSymlinksInPath())
        #expect(host.arguments == ["chrome-extension://abcdefghijklmnopabcdefghijklmnop/"])
    }

    @Test
    func `A Firefox-format host starts with its manifest path and the add-on ID`() throws {
        let fixture = try EchoHostFixture(allowedExtensions: ["{446900e4-71c2-419f-a6a7-df9c091e268b}"])
        let host = try fixture.locator.host(named: fixture.name, for: firefoxIdentity)
        #expect(host.arguments == [
            fixture.directory.appendingPathComponent("\(fixture.name).json").path,
            "{446900e4-71c2-419f-a6a7-df9c091e268b}",
        ])
    }

    @Test
    func `An extension the manifest does not list is forbidden`() throws {
        let fixture = try EchoHostFixture(allowedOrigins: ["chrome-extension://pppppppppppppppppppppppppppppppp/"])
        #expect(throws: NativeMessagingError.forbidden) {
            try fixture.locator.host(named: fixture.name, for: chromeIdentity)
        }
        #expect(throws: NativeMessagingError.forbidden) {
            try fixture.locator.host(named: fixture.name, for: firefoxIdentity)
        }
    }

    @Test
    func `A name without a manifest is not found, and an invalid name is never looked up`() throws {
        let fixture = try EchoHostFixture(allowedOrigins: [])
        #expect(throws: NativeMessagingError.hostNotFound) {
            try fixture.locator.host(named: "refrax.test.missing", for: chromeIdentity)
        }
        #expect(throws: NativeMessagingError.invalidHostName) {
            try fixture.locator.host(named: "../\(fixture.name)", for: chromeIdentity)
        }
    }

    @Test
    func `A manifest naming another host, a relative path, or a file that cannot run is skipped`() throws {
        let fixture = try EchoHostFixture(allowedOrigins: [#require(chromeIdentity.chromeOrigin)])
        let manifestURL = fixture.directory.appendingPathComponent("\(fixture.name).json")
        let variants: [[String: Any]] = [
            ["name": "refrax.test.other", "path": fixture.executable.path, "type": "stdio"],
            ["name": fixture.name, "path": "echo-host.pl", "type": "stdio"],
            ["name": fixture.name, "path": fixture.directory.path, "type": "stdio"],
            ["name": fixture.name, "path": fixture.executable.path, "type": "socket"],
        ]
        for variant in variants {
            var manifest = variant
            manifest["allowed_origins"] = try [#require(chromeIdentity.chromeOrigin)]
            try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
            #expect(throws: NativeMessagingError.self) {
                try fixture.locator.host(named: fixture.name, for: chromeIdentity)
            }
        }
    }

    @Test
    func `The first directory whose manifest allows the extension wins`() throws {
        let refusing = try EchoHostFixture(allowedOrigins: [])
        let allowing = try EchoHostFixture(allowedExtensions: [#require(firefoxIdentity.geckoID)])
        let locator = NativeMessagingHostLocator(directories: [refusing.directory, allowing.directory])
        let host = try locator.host(named: allowing.name, for: firefoxIdentity)
        #expect(host.executableURL == allowing.executable.resolvingSymlinksInPath())
    }

    @Test
    func `Refrax's folder comes before each browser's, and the user's before the system's`() {
        let home = URL(fileURLWithPath: "/Users/someone")
        let storage = URL(fileURLWithPath: "/Users/someone/Library/Application Support/website.refrax.browser")
        let paths = NativeMessagingHostLocator.standard(home: home, appStorage: storage).directories.map(\.path)
        #expect(paths == [
            "/Users/someone/Library/Application Support/website.refrax.browser/NativeMessagingHosts",
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
        let identity = ExtensionIdentity(manifest: ["key": "cmVmcmF4LXRlc3QtcHVibGljLWtleQ=="])
        #expect(identity.chromeID == "bhgcaanfkdmlhnjkbofcfcibigelhbee")
        #expect(identity.chromeOrigin == "chrome-extension://bhgcaanfkdmlhnjkbofcfcibigelhbee/")
    }

    @Test
    func `The Firefox ID comes from either settings key`() {
        let current = ExtensionIdentity(manifest: ["browser_specific_settings": ["gecko": ["id": "addon@darkreader.org"]]])
        let legacy = ExtensionIdentity(manifest: ["applications": ["gecko": ["id": "addon@darkreader.org"]]])
        #expect(current.geckoID == "addon@darkreader.org")
        #expect(legacy.geckoID == "addon@darkreader.org")
        #expect(current.chromeID == nil)
    }
}

/// CRX3 files: the ZIP after the header, and the developer key the header's CRX ID names.
@Suite("Extension archives")
struct ExtensionArchiveTests {
    private func lengthDelimited(_ field: UInt64, _ value: Data) -> Data {
        varint(field << 3 | 2) + varint(UInt64(value.count)) + value
    }

    private func varint(_ value: UInt64) -> Data {
        var value = value
        var bytes: [UInt8] = []
        repeat {
            let byte = UInt8(value & 0x7F)
            value >>= 7
            bytes.append(value == 0 ? byte : byte | 0x80)
        } while value != 0
        return Data(bytes)
    }

    private func crx(header: Data, zip: Data) -> Data {
        var version = UInt32(3).littleEndian
        var length = UInt32(header.count).littleEndian
        return Data("Cr24".utf8) + Data(bytes: &version, count: 4) + Data(bytes: &length, count: 4) + header + zip
    }

    @Test
    func `The key whose hash is the CRX ID is the developer's, whatever its position`() throws {
        let storeKey = Data("store-key".utf8)
        let developerKey = Data("developer-key".utf8)
        let crxID = Data(SHA256.hash(data: developerKey).prefix(16))
        let header = lengthDelimited(2, lengthDelimited(1, storeKey) + lengthDelimited(2, Data("sig".utf8)))
            + lengthDelimited(2, lengthDelimited(1, developerKey) + lengthDelimited(2, Data("sig".utf8)))
            + lengthDelimited(10_000, lengthDelimited(1, crxID))
        let zip = Data("PK\u{3}\u{4}payload".utf8)

        let contents = try ExtensionArchive.contents(ofCRX: crx(header: header, zip: zip))

        #expect(contents.zip == zip)
        #expect(contents.publicKey == developerKey)
    }

    @Test
    func `Anything but a CRX3 file is refused`() {
        #expect(throws: (any Error).self) {
            try ExtensionArchive.contents(ofCRX: Data("PK\u{3}\u{4}".utf8))
        }
    }

    @Test
    func `The manifest gains the CRX key, keeps its Firefox ID, and loses empty commands`() {
        let manifest: [String: Any] = [
            "commands": ["_execute_browser_action": [String: Any](), "toggle": ["description": "Toggle"]],
            "browser_specific_settings": ["gecko": ["id": "addon@example.org"]],
        ]
        let fixed = ExtensionArchive.fixedManifest(manifest, publicKey: Data("key".utf8))
        #expect((fixed["commands"] as? [String: Any])?.keys.sorted() == ["toggle"])
        #expect(fixed["key"] as? String == Data("key".utf8).base64EncodedString())
        #expect(ExtensionIdentity(manifest: fixed).geckoID == "addon@example.org")
    }
}
