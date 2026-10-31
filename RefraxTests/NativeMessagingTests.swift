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

    private func derLength(_ count: Int) -> Data {
        count < 0x80 ? Data([UInt8(count)]) : Data([0x82, UInt8(count >> 8), UInt8(count & 0xFF)])
    }

    /// A new RSA key pair and its public key as a DER SubjectPublicKeyInfo.
    private func rsaKey() throws -> (privateKey: SecKey, spki: Data) {
        let attributes: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2_048]
        let privateKey = try #require(SecKeyCreateRandomKey(attributes as CFDictionary, nil))
        let publicKey = try #require(SecKeyCopyPublicKey(privateKey))
        let pkcs1 = try #require(SecKeyCopyExternalRepresentation(publicKey, nil) as Data?)
        let algorithm = Data([0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00])
        let bitString = Data([0x03]) + derLength(pkcs1.count + 1) + Data([0x00]) + pkcs1
        let body = algorithm + bitString
        return (privateKey, Data([0x30]) + derLength(body.count) + body)
    }

    private func sign(_ message: Data, with key: SecKey) throws -> Data {
        try #require(SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, nil) as Data?)
    }

    /// A CRX3 file whose header names `crxKey`'s ID and carries proofs by `signers`.
    private func crx(zip: Data, crxKey: Data, signers: [(spki: Data, key: SecKey)]) throws -> Data {
        let signedHeaderData = lengthDelimited(1, Data(SHA256.hash(data: crxKey).prefix(16)))
        var signedLength = UInt32(signedHeaderData.count).littleEndian
        let message = Data("CRX3 SignedData\u{0}".utf8) + Data(bytes: &signedLength, count: 4) + signedHeaderData + zip
        var header = Data()
        for signer in signers {
            header += try lengthDelimited(2, lengthDelimited(1, signer.spki) + lengthDelimited(2, sign(message, with: signer.key)))
        }
        header += lengthDelimited(10_000, signedHeaderData)
        var version = UInt32(3).littleEndian
        var length = UInt32(header.count).littleEndian
        return Data("Cr24".utf8) + Data(bytes: &version, count: 4) + Data(bytes: &length, count: 4) + header + zip
    }

    @Test
    func `A CRX signed by the key its ID names yields that ID, whatever else signed it`() throws {
        let store = try rsaKey()
        let developer = try rsaKey()
        let zip = Data("PK\u{3}\u{4}payload".utf8)
        let file = try crx(zip: zip, crxKey: developer.spki, signers: [(store.spki, store.privateKey), (developer.spki, developer.privateKey)])

        let contents = try ExtensionArchive.contents(ofCRX: file)

        #expect(contents.zip == zip)
        #expect(contents.chromeID == ExtensionIdentity.chromeID(forPublicKey: developer.spki))
    }

    @Test
    func `A CRX whose payload changed after signing, or that the named key never signed, is refused`() throws {
        let developer = try rsaKey()
        let other = try rsaKey()
        var tampered = try crx(zip: Data("PK\u{3}\u{4}payload".utf8), crxKey: developer.spki, signers: [(developer.spki, developer.privateKey)])
        tampered[tampered.count - 1] ^= 0xFF
        #expect(throws: ExtensionError.self) {
            try ExtensionArchive.contents(ofCRX: tampered)
        }

        let unsigned = try crx(zip: Data("PK\u{3}\u{4}payload".utf8), crxKey: developer.spki, signers: [(other.spki, other.privateKey)])
        #expect(throws: ExtensionError.self) {
            try ExtensionArchive.contents(ofCRX: unsigned)
        }
    }

    @Test
    func `Anything but a CRX3 file is refused`() {
        #expect(throws: (any Error).self) {
            try ExtensionArchive.contents(ofCRX: Data("PK\u{3}\u{4}".utf8))
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
