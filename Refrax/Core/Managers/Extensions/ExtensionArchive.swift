import CryptoKit
import Foundation

/// Unpacks Chrome `.crx` and Firefox `.xpi` archives into folders `WKWebExtension` loads, and
/// patches their manifests for WebKit.
nonisolated enum ExtensionArchive {
    /// A CRX3 file split into its ZIP payload and the public key that identifies the extension.
    struct CRXContents: Equatable {
        /// The ZIP archive after the CRX header.
        let zip: Data
        /// The DER public key whose SHA-256 is the header's CRX ID: the key Chrome derives the
        /// extension ID from. `nil` when the header names no matching key.
        let publicKey: Data?
    }

    private enum CRX {
        static let magic = Data("Cr24".utf8)
        static let version: UInt32 = 3
        static let prefixLength = 12
        /// `CrxFileHeader.sha256_with_rsa` and `.sha256_with_ecdsa`, each an `AsymmetricKeyProof`.
        static let keyProofFields: Set<UInt64> = [2, 3]
        /// `AsymmetricKeyProof.public_key`.
        static let publicKeyField: UInt64 = 1
        /// `CrxFileHeader.signed_header_data`, a serialized `SignedData`.
        static let signedHeaderDataField: UInt64 = 10_000
        /// `SignedData.crx_id`: the first 16 bytes of the SHA-256 of the extension's key.
        static let crxIDField: UInt64 = 1
        static let crxIDLength = 16
    }

    // MARK: - CRX

    /// Splits a CRX3 file into its ZIP payload and its extension key.
    ///
    /// The header is a `CrxFileHeader` protocol buffer: key proofs in fields 2 and 3 and, in
    /// field 10000, the signed data holding the CRX ID. A Web Store CRX carries two proofs, the
    /// developer's and the store's; the developer's is the one whose hash is the CRX ID.
    ///
    /// - Throws: ``ExtensionError/invalidArchiveFormat`` for anything but a CRX3 file.
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
        return CRXContents(zip: Data(data[zipStart...]), publicKey: developerKey(inHeader: header))
    }

    private static func developerKey(inHeader header: Data) -> Data? {
        guard let fields = try? ProtobufFields.parse(header) else { return nil }
        let keys = fields
            .filter { CRX.keyProofFields.contains($0.number) }
            .compactMap { proof in
                (try? ProtobufFields.parse(proof.value))?.first { $0.number == CRX.publicKeyField }?.value
            }
        let crxID = fields.first { $0.number == CRX.signedHeaderDataField }
            .flatMap { try? ProtobufFields.parse($0.value) }?
            .first { $0.number == CRX.crxIDField }?.value
        guard let crxID, crxID.count == CRX.crxIDLength else { return keys.first }
        return keys.first { Data(SHA256.hash(data: $0).prefix(CRX.crxIDLength)) == crxID }
    }

    private static func littleEndianUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data.dropFirst(offset).prefix(4).reversed().reduce(0) { $0 << 8 | UInt32($1) }
    }

    // MARK: - Extraction

    /// Unzips `archiveURL` into `directory`, which must not exist yet, and applies the manifest
    /// fixups. Runs off the main actor.
    ///
    /// - Throws: ``ExtensionError/invalidArchiveFormat`` for an unknown or malformed archive,
    ///   ``ExtensionError/extractionFailed`` when unzipping fails.
    @concurrent
    static func extract(_ archiveURL: URL, into directory: URL) async throws {
        let data = try Data(contentsOf: archiveURL)
        let zip: Data
        var publicKey: Data?
        switch archiveURL.pathExtension.lowercased() {
        case "crx":
            let contents = try contents(ofCRX: data)
            zip = contents.zip
            publicKey = contents.publicKey
        case "xpi", "zip":
            zip = data
        default:
            throw ExtensionError.invalidArchiveFormat
        }

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

        fixupManifest(at: directory, publicKey: publicKey)
    }

    // MARK: - Manifest

    /// Patches the manifest in `directory` for WebKit and for Refrax's extension identity:
    ///
    /// - Drops empty `commands` entries (`"_execute_browser_action": {}`), which WebKit rejects.
    /// - Records a CRX's `publicKey` as the manifest's `key`, as Chrome does for an unpacked
    ///   extension, so the Chrome extension ID that native messaging hosts allow stays known.
    static func fixupManifest(at directory: URL, publicKey: Data?) {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let original = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            Logger.warning("Could not read manifest for fixup at: \(manifestURL.path)", category: Logger.extensions)
            return
        }

        let manifest = fixedManifest(original, publicKey: publicKey)
        guard !NSDictionary(dictionary: manifest).isEqual(to: original) else { return }
        do {
            let fixed = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            try fixed.write(to: manifestURL, options: .atomic)
        } catch {
            Logger.error("Failed to write fixed manifest: \(error)", category: Logger.extensions)
        }
    }

    /// `manifest` with the fixups ``fixupManifest(at:publicKey:)`` describes.
    static func fixedManifest(_ manifest: [String: Any], publicKey: Data?) -> [String: Any] {
        var manifest = manifest
        if let commands = manifest["commands"] as? [String: Any] {
            manifest["commands"] = commands.filter { _, value in
                (value as? [String: Any]).map { !$0.isEmpty } ?? false
            }
        }
        if manifest["key"] == nil, let publicKey {
            manifest["key"] = publicKey.base64EncodedString()
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
