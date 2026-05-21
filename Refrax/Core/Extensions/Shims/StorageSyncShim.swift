import Foundation

/// Shim for `browser.storage.sync` API using iCloud Key-Value Store.
///
/// WebKit's `WKWebExtension` provides `storage.local` natively but not `storage.sync`.
/// This shim implements sync storage using `NSUbiquitousKeyValueStore` for iCloud
/// synchronization across devices.
///
/// ## Storage Format
///
/// Keys are prefixed with the extension identifier to prevent collisions:
/// ```
/// ext:{extensionID}:{key}
/// ```
///
/// ## Quotas
///
/// Per Chrome/Firefox specs, `storage.sync` has stricter limits than `storage.local`:
/// - `QUOTA_BYTES`: 102,400 bytes (100KB) total per extension
/// - `QUOTA_BYTES_PER_ITEM`: 8,192 bytes per item
/// - `MAX_ITEMS`: 512 items
/// - `MAX_WRITE_OPERATIONS_PER_HOUR`: 1,800
/// - `MAX_WRITE_OPERATIONS_PER_MINUTE`: 120
///
/// Note: `NSUbiquitousKeyValueStore` has its own limits (1MB total, 1024 keys),
/// which we stay well within by enforcing extension quotas.
///
/// ## Thread Safety
///
/// All operations are MainActor-isolated since `NSUbiquitousKeyValueStore` must
/// be accessed from the main thread.

final class StorageSyncShim: ExtensionShim {
    // MARK: - Constants

    /// Storage quota constants matching Chrome's storage.sync limits.
    enum Quota {
        /// Total bytes per extension (100KB).
        static let bytesTotal = 102_400

        /// Maximum bytes per item (8KB).
        static let bytesPerItem = 8_192

        /// Maximum number of items per extension.
        static let maxItems = 512
    }

    /// Prefix for all extension storage keys.
    private static let keyPrefix = "ext:"

    // MARK: - Properties

    /// The iCloud key-value store.
    private let store = NSUbiquitousKeyValueStore.default

    /// Tracks storage usage per extension for quota enforcement.
    private var usageCache: [String: Int] = [:]

    // MARK: - Initialization

    init() {
        // Synchronize with iCloud on init
        store.synchronize()

        // Listen for external changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(storeDidChange),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - ExtensionShim Protocol

    func handle(method: String, args: [String: Any], extensionID: String) async throws -> Any? {
        switch method {
        case "get":
            return try await get(keys: args["keys"], extensionID: extensionID)

        case "getBytesInUse":
            return try await getBytesInUse(keys: args["keys"], extensionID: extensionID)

        case "set":
            guard let items = args["items"] as? [String: Any] else {
                throw ShimError.invalidArguments("'items' must be an object")
            }
            try await set(items: items, extensionID: extensionID)
            return nil

        case "remove":
            guard let keys = args["keys"] else {
                throw ShimError.invalidArguments("'keys' is required")
            }
            try await remove(keys: keys, extensionID: extensionID)
            return nil

        case "clear":
            try await clear(extensionID: extensionID)
            return nil

        default:
            throw ShimError.unsupportedMethod(method)
        }
    }

    // MARK: - Storage Operations

    /// Gets items from sync storage.
    ///
    /// - Parameters:
    ///   - keys: The keys to retrieve (string, array, or object with defaults).
    ///   - extensionID: The calling extension's identifier.
    /// - Returns: An object containing the requested key-value pairs.
    private func get(keys: Any?, extensionID: String) async throws -> [String: Any] {
        var result: [String: Any] = [:]

        switch keys {
        case nil:
            // Get all items for extension
            let prefix = Self.keyPrefix + extensionID + ":"
            for key in store.dictionaryRepresentation.keys where key.hasPrefix(prefix) {
                let shortKey = String(key.dropFirst(prefix.count))
                if let value = store.object(forKey: key) {
                    result[shortKey] = decodeValue(value)
                }
            }

        case let key as String:
            // Single key
            if let value = getValue(key: key, extensionID: extensionID) {
                result[key] = value
            }

        case let keyArray as [String]:
            // Array of keys
            for key in keyArray {
                if let value = getValue(key: key, extensionID: extensionID) {
                    result[key] = value
                }
            }

        case let keyDefaults as [String: Any]:
            // Object with default values
            for (key, defaultValue) in keyDefaults {
                result[key] = getValue(key: key, extensionID: extensionID) ?? defaultValue
            }

        default:
            throw ShimError.invalidArguments("'keys' must be null, string, array, or object")
        }

        return result
    }

    /// Gets bytes in use for specified keys.
    ///
    /// - Parameters:
    ///   - keys: The keys to check (null for all).
    ///   - extensionID: The calling extension's identifier.
    /// - Returns: The number of bytes in use.
    private func getBytesInUse(keys: Any?, extensionID: String) async throws -> Int {
        var total = 0

        switch keys {
        case nil:
            // All storage for extension
            let prefix = Self.keyPrefix + extensionID + ":"
            for key in store.dictionaryRepresentation.keys where key.hasPrefix(prefix) {
                if let data = store.data(forKey: key) {
                    total += data.count
                } else if let value = store.object(forKey: key) {
                    total += estimateSize(value)
                }
            }

        case let key as String:
            total = getValueSize(key: key, extensionID: extensionID)

        case let keyArray as [String]:
            for key in keyArray {
                total += getValueSize(key: key, extensionID: extensionID)
            }

        default:
            throw ShimError.invalidArguments("'keys' must be null, string, or array")
        }

        return total
    }

    /// Sets items in sync storage.
    ///
    /// - Parameters:
    ///   - items: The key-value pairs to store.
    ///   - extensionID: The calling extension's identifier.
    private func set(items: [String: Any], extensionID: String) async throws {
        // Check item count quota
        let currentCount = countItems(extensionID: extensionID)
        let newKeys = items.keys.filter { getValue(key: $0, extensionID: extensionID) == nil }
        if currentCount + newKeys.count > Quota.maxItems {
            throw ShimError.quotaExceeded
        }

        // Encode and check per-item size quota
        for (key, value) in items {
            let encoded = try encodeValue(value)
            if encoded.count > Quota.bytesPerItem {
                throw ShimError.quotaExceeded
            }

            // Check total quota
            let currentTotal = try await getBytesInUse(keys: nil, extensionID: extensionID)
            let existingSize = getValueSize(key: key, extensionID: extensionID)
            if currentTotal - existingSize + encoded.count > Quota.bytesTotal {
                throw ShimError.quotaExceeded
            }

            // Store the value
            let fullKey = Self.keyPrefix + extensionID + ":" + key
            store.set(encoded, forKey: fullKey)
        }

        store.synchronize()
    }

    /// Removes items from sync storage.
    ///
    /// - Parameters:
    ///   - keys: The keys to remove (string or array).
    ///   - extensionID: The calling extension's identifier.
    private func remove(keys: Any, extensionID: String) async throws {
        let keysToRemove: [String]

        switch keys {
        case let key as String:
            keysToRemove = [key]

        case let keyArray as [String]:
            keysToRemove = keyArray

        default:
            throw ShimError.invalidArguments("'keys' must be string or array")
        }

        for key in keysToRemove {
            let fullKey = Self.keyPrefix + extensionID + ":" + key
            store.removeObject(forKey: fullKey)
        }

        store.synchronize()
    }

    /// Clears all storage for an extension.
    ///
    /// - Parameter extensionID: The extension to clear storage for.
    private func clear(extensionID: String) async throws {
        let prefix = Self.keyPrefix + extensionID + ":"

        for key in store.dictionaryRepresentation.keys where key.hasPrefix(prefix) {
            store.removeObject(forKey: key)
        }

        store.synchronize()
    }

    // MARK: - Private Helpers

    /// Gets a single value from storage.
    private func getValue(key: String, extensionID: String) -> Any? {
        let fullKey = Self.keyPrefix + extensionID + ":" + key
        guard let data = store.data(forKey: fullKey) else { return nil }
        return decodeValue(data)
    }

    /// Gets the byte size of a stored value.
    private func getValueSize(key: String, extensionID: String) -> Int {
        let fullKey = Self.keyPrefix + extensionID + ":" + key
        if let data = store.data(forKey: fullKey) {
            return data.count
        }
        return 0
    }

    /// Counts items stored for an extension.
    private func countItems(extensionID: String) -> Int {
        let prefix = Self.keyPrefix + extensionID + ":"
        return store.dictionaryRepresentation.keys.count(where: { $0.hasPrefix(prefix) })
    }

    /// Encodes a value for storage.
    private func encodeValue(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value)
    }

    /// Decodes a value from storage.
    private func decodeValue(_ data: Any) -> Any? {
        guard let data = data as? Data else { return data }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// Estimates the byte size of a value.
    private func estimateSize(_ value: Any) -> Int {
        if let data = try? JSONSerialization.data(withJSONObject: value) {
            return data.count
        }
        return 0
    }

    // MARK: - Notifications

    @objc
    private func storeDidChange(_: Notification) {
        // Could dispatch events to extensions here if needed
        Logger.debug(
            "iCloud storage changed externally",
            category: Logger.extensions,
        )
    }
}
