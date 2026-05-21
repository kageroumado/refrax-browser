import Foundation
import SwiftData

/// Persistent storage entry for GM_* API values.
///
/// User scripts use GM_getValue/GM_setValue for persistent storage.
/// Values are stored per-namespace to isolate scripts from each other
/// while allowing scripts in the same namespace to share data.
///
/// ## Storage Format
///
/// Values are JSON-encoded to preserve type information across languages.
/// Supported types: string, number, boolean, null, arrays, objects.
///
/// ## Usage
///
/// ```swift
/// // Storage entries are managed by UserScriptStorageManager
/// let entry = UserScriptStorage(namespace: "example.com", key: "config")
/// entry.setValue(["theme": "dark", "fontSize": 14])
/// ```
@Model
final class UserScriptStorage {
    /// Compound key for uniqueness: "{namespace}:{key}"
    @Attribute(.unique)
    var id: String

    /// Script namespace this storage belongs to.
    var namespace: String

    /// Storage key name.
    var key: String

    /// JSON-encoded value.
    var jsonData: Data

    /// When this entry was last modified.
    var modifiedAt: Date

    // MARK: - Initialization

    /// Creates a new storage entry with JSON data.
    ///
    /// - Parameters:
    ///   - namespace: Script namespace for isolation.
    ///   - key: Storage key name.
    ///   - jsonData: Value as JSON-encoded data.
    init(namespace: String, key: String, jsonData: Data) {
        self.id = "\(namespace):\(key)"
        self.namespace = namespace
        self.key = key
        self.jsonData = jsonData
        self.modifiedAt = Date()
    }

    // MARK: - Key Generation

    /// Creates a compound ID from namespace and key.
    static func makeID(namespace: String, key: String) -> String {
        "\(namespace):\(key)"
    }
}
