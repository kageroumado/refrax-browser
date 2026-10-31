import CryptoKit
import Foundation
import Security

/// Unpacks Chrome `.crx` and Firefox `.xpi` archives into folders `WKWebExtension` loads, and
/// patches their manifests for WebKit.
nonisolated enum ExtensionArchive {
    /// A CRX3 file whose developer signature checked out.
    struct CRXContents: Equatable {
        /// The ZIP archive after the CRX header.
        let zip: Data
        /// The Chrome extension ID of the developer key that signed the archive.
        let chromeID: String
    }

    /// What an extracted archive proved about its extension.
    struct Extracted {
        /// The signed Chrome extension ID of a CRX; `nil` for an XPI or a ZIP.
        let verifiedChromeID: String?
    }

    private enum CRX {
        static let magic = Data("Cr24".utf8)
        static let version: UInt32 = 3
        static let prefixLength = 12
        /// `CrxFileHeader.sha256_with_rsa`, an `AsymmetricKeyProof`.
        static let rsaProofField: UInt64 = 2
        /// `CrxFileHeader.sha256_with_ecdsa`, an `AsymmetricKeyProof`.
        static let ecdsaProofField: UInt64 = 3
        /// `AsymmetricKeyProof.public_key`, a DER SubjectPublicKeyInfo.
        static let publicKeyField: UInt64 = 1
        /// `AsymmetricKeyProof.signature`.
        static let signatureField: UInt64 = 2
        /// `CrxFileHeader.signed_header_data`, a serialized `SignedData`.
        static let signedHeaderDataField: UInt64 = 10_000
        /// `SignedData.crx_id`: the first 16 bytes of the SHA-256 of the extension's key.
        static let crxIDField: UInt64 = 1
        static let crxIDLength = 16
        /// What each signature covers before the signed header data's length.
        static let signaturePrefix = Data("CRX3 SignedData\u{0}".utf8)
    }

    private struct KeyProof {
        let publicKey: Data
        let signature: Data
        let isECDSA: Bool
    }

    // MARK: - CRX

    /// Splits a CRX3 file into its ZIP payload and its verified extension ID.
    ///
    /// The header is a `CrxFileHeader` protocol buffer: key proofs in fields 2 (RSA) and 3
    /// (ECDSA) and, in field 10000, the signed data holding the CRX ID. A Web Store CRX carries
    /// the developer's proof and the store's. As in Chrome, every proof's signature over the
    /// signed data and the ZIP must hold, one of them must be by the key whose hash is the CRX
    /// ID, and a field that appears twice counts by its last occurrence, as protocol buffers
    /// read singular fields.
    ///
    /// - Throws: ``ExtensionError/invalidArchiveFormat`` for anything but a CRX3 file,
    ///   ``ExtensionError/invalidSignature`` when no proof by the CRX ID's key verifies.
    static func contents(ofCRX data: Data) throws -> CRXContents {
        guard data.count > CRX.prefixLength,
              data.prefix(4) == CRX.magic,
              littleEndianUInt32(data, at: 4) == CRX.version
        else {
            throw ExtensionError.invalidArchiveFormat
        }
        let headerLength = Int(littleEndianUInt32(data, at: 8))
        let zipStart = CRX.prefixLength + headerLength
        guard zipStart < data.count else { throw ExtensionError.invalidArchiveFormat }

        let header = Data(data[CRX.prefixLength ..< zipStart])
        let zip = Data(data[zipStart...])
        guard let fields = try? ProtobufFields.parse(header),
              let signedHeaderData = fields.last(where: { $0.number == CRX.signedHeaderDataField })?.value,
              let crxID = (try? ProtobufFields.parse(signedHeaderData))?.last(where: { $0.number == CRX.crxIDField })?.value,
              crxID.count == CRX.crxIDLength
        else {
            throw ExtensionError.invalidSignature
        }

        var length = UInt32(signedHeaderData.count).littleEndian
        let signedMessage = CRX.signaturePrefix + Data(bytes: &length, count: 4) + signedHeaderData + zip
        let proofFields = fields.filter { $0.number == CRX.rsaProofField || $0.number == CRX.ecdsaProofField }
        let proofs = proofFields.compactMap(keyProof)
        guard proofs.count == proofFields.count,
              proofs.allSatisfy({ verify($0, of: signedMessage) }),
              let developerProof = proofs.first(where: { Data(SHA256.hash(data: $0.publicKey).prefix(CRX.crxIDLength)) == crxID })
        else {
            throw ExtensionError.invalidSignature
        }
        return CRXContents(zip: zip, chromeID: ExtensionIdentity.chromeID(forPublicKey: developerProof.publicKey))
    }

    private static func keyProof(_ field: ProtobufFields.Field) -> KeyProof? {
        guard field.number == CRX.rsaProofField || field.number == CRX.ecdsaProofField,
              let members = try? ProtobufFields.parse(field.value),
              let publicKey = members.last(where: { $0.number == CRX.publicKeyField })?.value,
              let signature = members.last(where: { $0.number == CRX.signatureField })?.value
        else { return nil }
        return KeyProof(publicKey: publicKey, signature: signature, isECDSA: field.number == CRX.ecdsaProofField)
    }

    /// Whether `proof`'s signature over `message` holds: RSASSA-PKCS1-v1_5 or ECDSA P-256,
    /// both over SHA-256.
    private static func verify(_ proof: KeyProof, of message: Data) -> Bool {
        guard let keyBits = subjectPublicKey(inSPKI: proof.publicKey) else { return false }
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: proof.isECDSA ? kSecAttrKeyTypeECSECPrimeRandom : kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
        ]
        guard let key = SecKeyCreateWithData(keyBits as CFData, attributes as CFDictionary, nil) else { return false }
        let algorithm: SecKeyAlgorithm = proof.isECDSA ? .ecdsaSignatureMessageX962SHA256 : .rsaSignatureMessagePKCS1v15SHA256
        return SecKeyVerifySignature(key, algorithm, message as CFData, proof.signature as CFData, nil)
    }

    /// The key inside a DER SubjectPublicKeyInfo: the bit string after the algorithm, which is
    /// a PKCS #1 key for RSA and an uncompressed point for ECDSA, the forms Security accepts.
    static func subjectPublicKey(inSPKI spki: Data) -> Data? {
        let bytes = [UInt8](spki)
        var index = 0
        guard let outer = DER.element(bytes, &index), outer.tag == DER.sequence else { return nil }
        var inner = outer.content.lowerBound
        guard let algorithm = DER.element(bytes, &inner), algorithm.tag == DER.sequence,
              let key = DER.element(bytes, &inner), key.tag == DER.bitString, !key.content.isEmpty,
              bytes[key.content.lowerBound] == 0
        else { return nil }
        return Data(bytes[(key.content.lowerBound + 1) ..< key.content.upperBound])
    }

    private enum DER {
        static let sequence: UInt8 = 0x30
        static let bitString: UInt8 = 0x03

        /// The element at `index`, which then points past it.
        static func element(_ bytes: [UInt8], _ index: inout Int) -> (tag: UInt8, content: Range<Int>)? {
            guard index + 2 <= bytes.count else { return nil }
            let tag = bytes[index]
            var length = Int(bytes[index + 1])
            index += 2
            if length & 0x80 != 0 {
                let count = length & 0x7F
                guard count > 0, count <= 4, index + count <= bytes.count else { return nil }
                length = bytes[index ..< index + count].reduce(0) { $0 << 8 | Int($1) }
                index += count
            }
            guard length <= bytes.count - index else { return nil }
            let content = index ..< index + length
            index += length
            return (tag, content)
        }
    }

    private static func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data.dropFirst(offset).prefix(4).reversed().reduce(0) { $0 << 8 | UInt32($1) }
    }

    // MARK: - Extraction

    /// Unzips `archiveURL` into `directory`, which must not exist yet, and applies the manifest
    /// fixups. Runs off the main actor.
    ///
    /// - Returns: What the archive proved: a CRX's verified Chrome extension ID.
    /// - Throws: ``ExtensionError/invalidArchiveFormat`` for an unknown, malformed or unsafe
    ///   archive (see ``ZipInspection``), ``ExtensionError/invalidSignature`` for a CRX whose
    ///   signature fails,
    ///   ``ExtensionError/extractionFailed`` when unzipping fails.
    @concurrent
    @discardableResult
    static func extract(_ archiveURL: URL, into directory: URL) async throws -> Extracted {
        let data = try Data(contentsOf: archiveURL)
        let zip: Data
        var chromeID: String?
        // By content: store downloads arrive without a telling file extension.
        if data.prefix(4) == CRX.magic {
            let contents = try contents(ofCRX: data)
            zip = contents.zip
            chromeID = contents.chromeID
        } else if data.prefix(2) == Data("PK".utf8) {
            zip = data
        } else {
            throw ExtensionError.invalidArchiveFormat
        }

        try ZipInspection.check(zip)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).zip")
        try zip.write(to: zipURL)
        defer { try? FileManager.default.removeItem(at: zipURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", "-o", zipURL.path, "-d", directory.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: directory)
            throw ExtensionError.extractionFailed
        }

        fixupManifest(at: directory)
        return Extracted(verifiedChromeID: chromeID)
    }

    // MARK: - Manifest

    /// Drops empty `commands` entries from the manifest in `directory`
    /// (`"_execute_browser_action": {}`), which WebKit rejects.
    static func fixupManifest(at directory: URL) {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let original = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            Logger.warning("Could not read manifest for fixup at: \(manifestURL.path)", category: Logger.extensions)
            return
        }

        let manifest = fixedManifest(original)
        guard !NSDictionary(dictionary: manifest).isEqual(to: original) else { return }
        do {
            let fixed = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            try fixed.write(to: manifestURL, options: .atomic)
        } catch {
            Logger.error("Failed to write fixed manifest: \(error)", category: Logger.extensions)
        }
    }

    /// `manifest` with the fixups ``fixupManifest(at:)`` describes.
    static func fixedManifest(_ manifest: [String: Any]) -> [String: Any] {
        var manifest = manifest
        if let commands = manifest["commands"] as? [String: Any] {
            manifest["commands"] = commands.filter { _, value in
                (value as? [String: Any]).map { !$0.isEmpty } ?? false
            }
        }
        return manifest
    }
}

/// The top-level fields of a protocol buffer message, enough to walk a CRX header.
nonisolated enum ProtobufFields {
    struct Field {
        let number: UInt64
        /// The bytes of a length-delimited field; empty for every other wire type.
        let value: Data
    }

    private enum WireType: UInt64 {
        case varint = 0
        case fixed64 = 1
        case lengthDelimited = 2
        case fixed32 = 5
    }

    struct MalformedMessage: Error {}

    static func parse(_ data: Data) throws -> [Field] {
        let bytes = [UInt8](data)
        var index = 0
        var fields: [Field] = []
        while index < bytes.count {
            let key = try varint(bytes, &index)
            guard let wireType = WireType(rawValue: key & 0x7) else { throw MalformedMessage() }
            let number = key >> 3
            switch wireType {
            case .varint:
                _ = try varint(bytes, &index)
                fields.append(Field(number: number, value: Data()))
            case .fixed64, .fixed32:
                index += wireType == .fixed64 ? 8 : 4
                guard index <= bytes.count else { throw MalformedMessage() }
                fields.append(Field(number: number, value: Data()))
            case .lengthDelimited:
                let length = try varint(bytes, &index)
                guard length <= UInt64(bytes.count - index) else { throw MalformedMessage() }
                let end = index + Int(length)
                fields.append(Field(number: number, value: Data(bytes[index ..< end])))
                index = end
            }
        }
        return fields
    }

    private static func varint(_ bytes: [UInt8], _ index: inout Int) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count, shift < 64 {
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 {
                return result
            }
            shift += 7
        }
        throw MalformedMessage()
    }
}

/// Reads a ZIP archive's central directory to decide whether it is safe to unpack: within
/// size and entry limits, with every entry a regular file or folder inside the archive.
nonisolated enum ZipInspection {
    static let maximumEntries = 50_000
    static let maximumUnpackedSize: UInt64 = 1 << 30

    private enum Signature {
        static let endOfCentralDirectory: UInt32 = 0x0605_4B50
        static let centralDirectoryEntry: UInt32 = 0x0201_4B50
    }

    private enum Layout {
        static let endRecordLength = 22
        static let longestComment = 0xFFFF
        static let entryHeaderLength = 46
        /// "Version made by" names the system in its high byte; 3 is Unix, whose external
        /// attributes carry a file mode in their high 16 bits.
        static let unixHost: UInt8 = 3
        static let fileTypeMask: UInt32 = 0o170000
        static let symbolicLink: UInt32 = 0o120000
    }

    /// - Throws: ``ExtensionError/invalidArchiveFormat`` for a malformed archive, one past the
    ///   limits, or one with a symbolic link, an absolute path or a `..` component.
    static func check(_ zip: Data) throws {
        let bytes = [UInt8](zip)
        guard bytes.count >= Layout.endRecordLength else { throw ExtensionError.invalidArchiveFormat }
        let searchStart = max(0, bytes.count - Layout.endRecordLength - Layout.longestComment)
        guard let end = stride(from: bytes.count - Layout.endRecordLength, through: searchStart, by: -1)
            .first(where: { uint32(bytes, $0) == Signature.endOfCentralDirectory })
        else { throw ExtensionError.invalidArchiveFormat }

        let entryCount = Int(uint16(bytes, end + 10))
        let directoryOffset = Int(uint32(bytes, end + 16))
        guard entryCount <= maximumEntries, directoryOffset < bytes.count else { throw ExtensionError.invalidArchiveFormat }

        var offset = directoryOffset
        var unpackedSize: UInt64 = 0
        for _ in 0 ..< entryCount {
            guard offset + Layout.entryHeaderLength <= bytes.count,
                  uint32(bytes, offset) == Signature.centralDirectoryEntry
            else { throw ExtensionError.invalidArchiveFormat }
            let madeBy = bytes[offset + 5]
            let size = uint32(bytes, offset + 24)
            let nameLength = Int(uint16(bytes, offset + 28))
            let extraLength = Int(uint16(bytes, offset + 30))
            let commentLength = Int(uint16(bytes, offset + 32))
            let attributes = uint32(bytes, offset + 38)
            let nameStart = offset + Layout.entryHeaderLength
            guard nameStart + nameLength <= bytes.count, size != UInt32.max else { throw ExtensionError.invalidArchiveFormat }
            let name = String(decoding: bytes[nameStart ..< nameStart + nameLength], as: UTF8.self)

            unpackedSize += UInt64(size)
            let components = name.split(separator: "/", omittingEmptySubsequences: false)
            let isSymbolicLink = madeBy == Layout.unixHost && (attributes >> 16) & Layout.fileTypeMask == Layout.symbolicLink
            guard unpackedSize <= maximumUnpackedSize, !name.hasPrefix("/"), !name.contains("\\"),
                  !components.contains(".."), !isSymbolicLink
            else { throw ExtensionError.invalidArchiveFormat }
            offset = nameStart + nameLength + extraLength + commentLength
        }
    }

    private static func uint16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        guard offset + 2 <= bytes.count else { return 0 }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func uint32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset + 4 <= bytes.count else { return 0 }
        return (0 ..< 4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << (8 * $1) }
    }
}
