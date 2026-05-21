import CommonCrypto
import Foundation
import Security

/// Decrypts passwords from Chromium-based browsers on macOS.
///
/// Chromium browsers (Chrome, Arc, Brave, Edge, Opera, Vivaldi) encrypt saved passwords
/// using AES-128-CBC. The encryption key is derived from a passphrase stored in the
/// macOS Keychain under "{Browser} Safe Storage".
///
/// ## Encryption Details
///
/// - **Algorithm**: AES-128-CBC
/// - **Key Derivation**: PBKDF2 with SHA1
/// - **Salt**: `"saltysalt"` (constant)
/// - **Iterations**: 1003
/// - **IV**: 16 space characters (0x20)
/// - **Prefix**: Encrypted values start with `"v10"` which must be stripped before decryption
///
/// ## Security Notes
///
/// Accessing the Safe Storage key requires user authentication via the Keychain.
/// The user will be prompted to allow access when the decryptor attempts to
/// retrieve the encryption passphrase.
///
/// - SeeAlso: [Chromium Password Encryption](https://source.chromium.org/chromium)
final class ChromiumPasswordDecryptor: Sendable {
    // MARK: - Constants

    private enum Constants {
        /// Salt used for PBKDF2 key derivation (constant across all Chromium browsers).
        static let salt = "saltysalt"

        /// Number of PBKDF2 iterations on macOS.
        static let iterations: UInt32 = 1_003

        /// AES key length in bytes (128-bit).
        static let keyLength = 16

        /// Initialization vector: 16 space characters.
        static let iv = Data(repeating: 0x20, count: 16)

        /// Prefix added to encrypted values by Chromium.
        static let encryptedPrefix = "v10"
    }

    // MARK: - Properties

    /// The browser to decrypt passwords for.
    let browser: ThirdPartyBrowser

    /// Cached derived encryption key.
    private var cachedKey: Data?

    // MARK: - Initialization

    /// Creates a decryptor for the specified Chromium browser.
    ///
    /// - Parameter browser: The browser whose passwords will be decrypted.
    init(browser: ThirdPartyBrowser) {
        self.browser = browser
    }

    // MARK: - Public Methods

    /// Retrieves the Safe Storage passphrase from the Keychain.
    ///
    /// This will prompt the user for Keychain access if the app hasn't been
    /// previously authorized.
    ///
    /// - Returns: The passphrase used for password encryption.
    /// - Throws: `DecryptionError` if the passphrase cannot be retrieved.
    func getSafeStoragePassword() throws -> String {
        guard let keychainServiceName = browser.safeStorageKeychainName else {
            throw DecryptionError.unsupportedBrowser
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw DecryptionError.keychainItemNotFound(keychainServiceName)
            } else if status == errSecAuthFailed || status == errSecUserCanceled {
                throw DecryptionError.keychainAccessDenied
            } else {
                throw DecryptionError.keychainError(status)
            }
        }

        guard let data = item as? Data,
              let password = String(data: data, encoding: .utf8)
        else {
            throw DecryptionError.invalidKeychainData
        }

        return password
    }

    /// Derives the AES encryption key from the Safe Storage passphrase.
    ///
    /// Uses PBKDF2 with SHA1 to derive a 128-bit key from the passphrase.
    ///
    /// - Parameter passphrase: The Safe Storage passphrase from Keychain.
    /// - Returns: The derived 128-bit AES key.
    /// - Throws: `DecryptionError` if key derivation fails.
    func deriveKey(from passphrase: String) throws -> Data {
        guard let passphraseData = passphrase.data(using: .utf8),
              let saltData = Constants.salt.data(using: .utf8)
        else {
            throw DecryptionError.invalidPassphrase
        }

        var derivedKey = Data(count: Constants.keyLength)
        let derivationStatus = derivedKey.withUnsafeMutableBytes { derivedKeyBytes in
            passphraseData.withUnsafeBytes { passphraseBytes in
                saltData.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passphraseBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        passphraseData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        saltData.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        Constants.iterations,
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        Constants.keyLength,
                    )
                }
            }
        }

        guard derivationStatus == kCCSuccess else {
            throw DecryptionError.keyDerivationFailed(Int(derivationStatus))
        }

        return derivedKey
    }

    /// Decrypts a Chromium-encrypted password.
    ///
    /// Handles the `v10` prefix and PKCS7 padding automatically.
    ///
    /// - Parameters:
    ///   - encryptedData: The encrypted password data from the SQLite database.
    ///   - key: The derived AES encryption key.
    /// - Returns: The decrypted password string.
    /// - Throws: `DecryptionError` if decryption fails.
    func decrypt(_ encryptedData: Data, with key: Data) throws -> String {
        // Check for v10 prefix and strip it
        var dataToDecrypt = encryptedData

        if let prefix = String(data: encryptedData.prefix(3), encoding: .utf8),
           prefix == Constants.encryptedPrefix {
            dataToDecrypt = encryptedData.dropFirst(3)
        }

        // Perform AES-128-CBC decryption
        let decryptedData = try aesDecrypt(dataToDecrypt, key: key, iv: Constants.iv)

        // Remove PKCS7 padding and convert to string
        let unpaddedData = try removePKCS7Padding(decryptedData)

        guard let password = String(data: unpaddedData, encoding: .utf8) else {
            throw DecryptionError.invalidDecryptedData
        }

        return password
    }

    /// Convenience method to decrypt a password using the browser's Safe Storage key.
    ///
    /// This method handles the full decryption pipeline:
    /// 1. Retrieves the Safe Storage passphrase from Keychain
    /// 2. Derives the AES key using PBKDF2
    /// 3. Decrypts the password data
    ///
    /// - Parameter encryptedData: The encrypted password data.
    /// - Returns: The decrypted password string.
    /// - Throws: `DecryptionError` if any step fails.
    func decryptPassword(_ encryptedData: Data) throws -> String {
        let passphrase = try getSafeStoragePassword()
        let key = try deriveKey(from: passphrase)
        return try decrypt(encryptedData, with: key)
    }
}

// MARK: - Private Helpers

private extension ChromiumPasswordDecryptor {
    /// Performs AES-128-CBC decryption.
    func aesDecrypt(_ data: Data, key: Data, iv: Data) throws -> Data {
        let bufferSize = data.count + kCCBlockSizeAES128
        var decryptedData = Data(count: bufferSize)
        var decryptedLength = 0

        let status = decryptedData.withUnsafeMutableBytes { decryptedBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress,
                            data.count,
                            decryptedBytes.baseAddress,
                            bufferSize,
                            &decryptedLength,
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw DecryptionError.decryptionFailed(Int(status))
        }

        return decryptedData.prefix(decryptedLength)
    }

    /// Removes PKCS7 padding from decrypted data.
    func removePKCS7Padding(_ data: Data) throws -> Data {
        guard let lastByte = data.last else {
            throw DecryptionError.invalidPadding
        }

        let paddingLength = Int(lastByte)

        guard paddingLength > 0, paddingLength <= 16, data.count >= paddingLength else {
            // No padding or invalid padding - return as-is
            return data
        }

        // Verify all padding bytes are correct
        let paddingBytes = data.suffix(paddingLength)
        guard paddingBytes.allSatisfy({ $0 == lastByte }) else {
            // Invalid padding - return as-is
            return data
        }

        return data.dropLast(paddingLength)
    }
}

// MARK: - Decryption Error

extension ChromiumPasswordDecryptor {
    /// Errors that can occur during password decryption.
    enum DecryptionError: Error, LocalizedError, Sendable {
        /// The browser does not support direct password import.
        case unsupportedBrowser

        /// The Safe Storage item was not found in the Keychain.
        case keychainItemNotFound(String)

        /// The user denied Keychain access.
        case keychainAccessDenied

        /// A Keychain operation failed with the given status.
        case keychainError(OSStatus)

        /// The Keychain data was not in the expected format.
        case invalidKeychainData

        /// The passphrase could not be encoded.
        case invalidPassphrase

        /// PBKDF2 key derivation failed.
        case keyDerivationFailed(Int)

        /// AES decryption failed.
        case decryptionFailed(Int)

        /// The decrypted data could not be converted to a string.
        case invalidDecryptedData

        /// The padding was invalid.
        case invalidPadding

        var errorDescription: String? {
            switch self {
            case .unsupportedBrowser:
                "This browser does not support direct password import"
            case let .keychainItemNotFound(service):
                "Could not find '\(service)' in Keychain. Is the browser installed?"
            case .keychainAccessDenied:
                "Keychain access was denied. Please allow access when prompted."
            case let .keychainError(status):
                "Keychain error (status: \(status))"
            case .invalidKeychainData:
                "The Keychain data was corrupted or in an unexpected format"
            case .invalidPassphrase:
                "Failed to process the encryption passphrase"
            case let .keyDerivationFailed(status):
                "Failed to derive encryption key (status: \(status))"
            case let .decryptionFailed(status):
                "Failed to decrypt password (status: \(status))"
            case .invalidDecryptedData:
                "The decrypted data could not be read as text"
            case .invalidPadding:
                "Invalid encryption padding"
            }
        }
    }
}
