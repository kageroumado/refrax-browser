import Compression
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

    /// Unpacks `archiveURL` into `directory`, which must not exist yet, and applies the
    /// manifest fixups. Runs off the main actor.
    ///
    /// The central directory is checked first (``ZipInspection``), the entries are written by
    /// ``ZipExtractor``, which counts what it writes, and the written tree is checked on disk
    /// (``ExtractedTree``) before it takes `directory`'s place.
    ///
    /// - Returns: What the archive proved: a CRX's verified Chrome extension ID.
    /// - Throws: ``ExtensionError/invalidArchiveFormat`` for an unknown, malformed or unsafe
    ///   archive (see ``ZipInspection``), ``ExtensionError/invalidSignature`` for a CRX whose
    ///   signature fails.
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

        let entries = try ZipInspection.check(zip)
        // Written into a staging folder that becomes `directory` only once the tree checks out.
        let staging = directory.deletingLastPathComponent()
            .appendingPathComponent(".\(directory.lastPathComponent).unpacking-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try ZipExtractor.extract(zip, entries: entries, into: staging)
            try ExtractedTree.verify(staging)
            try FileManager.default.moveItem(at: staging, to: directory)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
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

/// Reads a ZIP archive's central directory: the entries Refrax will unpack, refused early when
/// the archive is past the limits or names anything but regular files and folders inside it.
///
/// The directory must be the plain, single one the end record describes: an archive with a
/// ZIP64 locator, or whose end record counts other entries than its directory holds, is
/// refused, so the entries checked here are the entries ``ZipExtractor`` writes.
nonisolated enum ZipInspection {
    static let maximumEntries = 50_000
    static let maximumUnpackedSize: UInt64 = 1 << 30

    /// One file or folder of the archive, as its central directory describes it.
    struct Entry {
        let name: String
        let method: UInt16
        let flags: UInt16
        let crc: UInt32
        let compressedSize: Int
        let size: Int
        let localHeaderOffset: Int

        var isFolder: Bool {
            name.hasSuffix("/")
        }
    }

    private enum Signature {
        static let endOfCentralDirectory: UInt32 = 0x0605_4B50
        static let zip64Locator: UInt32 = 0x0706_4B50
        static let centralDirectoryEntry: UInt32 = 0x0201_4B50
    }

    private enum Layout {
        static let endRecordLength = 22
        static let zip64LocatorLength = 20
        static let longestComment = 0xFFFF
        static let entryHeaderLength = 46
        static let fileTypeMask: UInt32 = 0o170000
        static let regularFile: UInt32 = 0o100000
        static let folder: UInt32 = 0o040000
    }

    /// The archive's entries.
    ///
    /// - Throws: ``ExtensionError/invalidArchiveFormat`` for a malformed or ZIP64 archive, one
    ///   past the limits, or one with an entry that is a symbolic link or any file type but a
    ///   regular file or folder, whatever system the archive says made it, or whose path is
    ///   absolute or has a `..` component.
    @discardableResult
    static func check(_ zip: Data) throws -> [Entry] {
        let bytes = [UInt8](zip)
        guard bytes.count >= Layout.endRecordLength else { throw ExtensionError.invalidArchiveFormat }
        let searchStart = max(0, bytes.count - Layout.endRecordLength - Layout.longestComment)
        guard let end = stride(from: bytes.count - Layout.endRecordLength, through: searchStart, by: -1)
            .first(where: { uint32(bytes, $0) == Signature.endOfCentralDirectory })
        else { throw ExtensionError.invalidArchiveFormat }
        if end >= Layout.zip64LocatorLength, uint32(bytes, end - Layout.zip64LocatorLength) == Signature.zip64Locator {
            throw ExtensionError.invalidArchiveFormat
        }

        let entryCount = Int(uint16(bytes, end + 10))
        let directorySize = Int(uint32(bytes, end + 12))
        let directoryOffset = Int(uint32(bytes, end + 16))
        guard entryCount <= maximumEntries, entryCount == Int(uint16(bytes, end + 8)),
              directoryOffset + directorySize <= end
        else { throw ExtensionError.invalidArchiveFormat }

        var entries: [Entry] = []
        var offset = directoryOffset
        var unpackedSize = 0
        for _ in 0 ..< entryCount {
            let entry = try entry(in: bytes, at: &offset)
            unpackedSize += entry.size
            guard UInt64(unpackedSize) <= maximumUnpackedSize else { throw ExtensionError.invalidArchiveFormat }
            entries.append(entry)
        }
        // The end record must count every entry the directory holds, and nothing else.
        guard offset == directoryOffset + directorySize else { throw ExtensionError.invalidArchiveFormat }
        return entries
    }

    private static func entry(in bytes: [UInt8], at offset: inout Int) throws -> Entry {
        guard offset + Layout.entryHeaderLength <= bytes.count,
              uint32(bytes, offset) == Signature.centralDirectoryEntry
        else { throw ExtensionError.invalidArchiveFormat }
        let flags = uint16(bytes, offset + 8)
        let method = uint16(bytes, offset + 10)
        let crc = uint32(bytes, offset + 16)
        let compressedSize = uint32(bytes, offset + 20)
        let size = uint32(bytes, offset + 24)
        let nameLength = Int(uint16(bytes, offset + 28))
        let extraLength = Int(uint16(bytes, offset + 30))
        let commentLength = Int(uint16(bytes, offset + 32))
        let attributes = uint32(bytes, offset + 38)
        let localHeaderOffset = uint32(bytes, offset + 42)
        let nameStart = offset + Layout.entryHeaderLength
        guard nameStart + nameLength <= bytes.count, size != UInt32.max, compressedSize != UInt32.max,
              localHeaderOffset != UInt32.max
        else { throw ExtensionError.invalidArchiveFormat }
        let name = String(decoding: bytes[nameStart ..< nameStart + nameLength], as: UTF8.self)

        // A file type in the high attribute bits counts whoever made the archive, as unzip
        // honors it.
        let fileType = (attributes >> 16) & Layout.fileTypeMask
        let components = name.split(separator: "/", omittingEmptySubsequences: false)
        guard fileType == 0 || fileType == Layout.regularFile || fileType == Layout.folder,
              !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"), !name.contains("\0"),
              !components.contains(".."), !components.contains(".")
        else { throw ExtensionError.invalidArchiveFormat }

        offset = nameStart + nameLength + extraLength + commentLength
        return Entry(
            name: name,
            method: method,
            flags: flags,
            crc: crc,
            compressedSize: Int(compressedSize),
            size: Int(size),
            localHeaderOffset: Int(localHeaderOffset),
        )
    }

    static func uint16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= bytes.count else { return 0 }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    static func uint32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= bytes.count else { return 0 }
        return (0 ..< 4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << (8 * $1) }
    }
}

/// Unpacks the entries ``ZipInspection`` read, writing only regular files and folders and
/// counting the bytes it writes: an entry that inflates past its declared size, fails its
/// checksum, or would take the archive past ``ZipInspection/maximumUnpackedSize`` stops the
/// extraction. Stored and deflated entries are supported, as browsers' extension archives use.
nonisolated enum ZipExtractor {
    private enum Layout {
        static let localSignature: UInt32 = 0x0403_4B50
        static let localHeaderLength = 30
        static let encryptedFlag: UInt16 = 1
        static let stored: UInt16 = 0
        static let deflated: UInt16 = 8
        static let bufferSize = 64 * 1_024
    }

    /// Writes `entries` of `zip` into `directory`, which must exist and be empty.
    ///
    /// - Throws: ``ExtensionError/invalidArchiveFormat`` for anything that is not exactly what
    ///   the entries declare.
    static func extract(_ zip: Data, entries: [ZipInspection.Entry], into directory: URL) throws {
        let bytes = [UInt8](zip)
        var written = 0
        for entry in entries {
            let destination = directory.appendingPathComponent(entry.name)
            if entry.isFolder {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                continue
            }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try compressedData(of: entry, in: bytes)
            let descriptor = open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644)
            guard descriptor >= 0 else { throw ExtensionError.invalidArchiveFormat }
            let file = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            var checksum = CRC32()
            var entryBytes = 0
            try inflate(data, method: entry.method) { chunk in
                entryBytes += chunk.count
                written += chunk.count
                guard entryBytes <= entry.size, UInt64(written) <= ZipInspection.maximumUnpackedSize else {
                    throw ExtensionError.invalidArchiveFormat
                }
                checksum.update(chunk)
                try file.write(contentsOf: chunk)
            }
            guard entryBytes == entry.size, checksum.value == entry.crc else { throw ExtensionError.invalidArchiveFormat }
        }
    }

    private static func compressedData(of entry: ZipInspection.Entry, in bytes: [UInt8]) throws -> ArraySlice<UInt8> {
        let header = entry.localHeaderOffset
        guard entry.flags & Layout.encryptedFlag == 0,
              ZipInspection.uint32(bytes, header) == Layout.localSignature
        else { throw ExtensionError.invalidArchiveFormat }
        let nameLength = Int(ZipInspection.uint16(bytes, header + 26))
        let extraLength = Int(ZipInspection.uint16(bytes, header + 28))
        let start = header + Layout.localHeaderLength + nameLength + extraLength
        guard start + entry.compressedSize <= bytes.count else { throw ExtensionError.invalidArchiveFormat }
        return bytes[start ..< start + entry.compressedSize]
    }

    /// Feeds `data`'s uncompressed bytes to `output` in chunks.
    private static func inflate(_ data: ArraySlice<UInt8>, method: UInt16, output: (Data) throws -> Void) throws {
        switch method {
        case Layout.stored:
            try output(Data(data))
        case Layout.deflated:
            try data.withUnsafeBufferPointer { source in
                let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
                defer { stream.deallocate() }
                guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
                    throw ExtensionError.invalidArchiveFormat
                }
                defer { compression_stream_destroy(stream) }
                let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Layout.bufferSize)
                defer { buffer.deallocate() }
                stream.pointee.src_ptr = source.baseAddress ?? UnsafePointer(buffer)
                stream.pointee.src_size = source.count
                while true {
                    stream.pointee.dst_ptr = buffer
                    stream.pointee.dst_size = Layout.bufferSize
                    let status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                    let produced = Layout.bufferSize - stream.pointee.dst_size
                    if produced > 0 {
                        try output(Data(bytes: buffer, count: produced))
                    }
                    switch status {
                    case COMPRESSION_STATUS_OK: continue
                    case COMPRESSION_STATUS_END: return
                    default: throw ExtensionError.invalidArchiveFormat
                    }
                }
            }
        default:
            throw ExtensionError.invalidArchiveFormat
        }
    }

    /// The CRC-32 ZIP archives use.
    private struct CRC32 {
        private static let table: [UInt32] = (0 ..< 256).map { index in
            (0 ..< 8).reduce(UInt32(index)) { value, _ in value & 1 == 1 ? 0xEDB8_8320 ^ (value >> 1) : value >> 1 }
        }

        private var state: UInt32 = 0xFFFF_FFFF

        var value: UInt32 {
            state ^ 0xFFFF_FFFF
        }

        mutating func update(_ data: Data) {
            var state = state
            for byte in data {
                state = Self.table[Int((state ^ UInt32(byte)) & 0xFF)] ^ (state >> 8)
            }
            self.state = state
        }
    }
}

/// Checks an unpacked extension folder as it is on disk: only regular files with a single
/// link and folders, nothing that resolves outside it, and no more than
/// ``ZipInspection/maximumUnpackedSize`` in all.
nonisolated enum ExtractedTree {
    /// - Throws: ``ExtensionError/invalidArchiveFormat`` when the folder holds anything else.
    static func verify(_ directory: URL) throws {
        let root = directory.resolvingSymlinksInPath().standardizedFileURL.path
        guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else {
            throw ExtensionError.invalidArchiveFormat
        }
        var total: UInt64 = 0
        for case let relativePath as String in enumerator {
            let path = directory.appendingPathComponent(relativePath).path
            var info = stat()
            guard lstat(path, &info) == 0 else { throw ExtensionError.invalidArchiveFormat }
            switch info.st_mode & S_IFMT {
            case S_IFDIR:
                break
            case S_IFREG:
                guard info.st_nlink == 1 else { throw ExtensionError.invalidArchiveFormat }
                total += UInt64(info.st_size)
            default:
                throw ExtensionError.invalidArchiveFormat
            }
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
            guard resolved == root || resolved.hasPrefix(root + "/"), total <= ZipInspection.maximumUnpackedSize else {
                throw ExtensionError.invalidArchiveFormat
            }
        }
    }
}
