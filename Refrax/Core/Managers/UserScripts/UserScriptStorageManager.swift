import Foundation
import SwiftData

/// Manages persistent storage for GM_* API values.
///
/// Values are isolated by script namespace to prevent cross-script interference
/// while allowing scripts with the same namespace to share data.
///
/// ## Thread Safety
///
/// This manager is an actor, ensuring all storage operations are serialized.
/// Call from any thread; the actor will serialize access.
///
/// ## Usage
///
/// ```swift
/// let storage = UserScriptStorageManager(modelContext: context)
///
/// // Store a value
/// try await storage.setValue(key: "count", value: 42, namespace: "example.com")
///
/// // Retrieve a value
/// let count = try await storage.getValue(key: "count", namespace: "example.com", defaultValue: 0)
/// ```
@ModelActor
actor UserScriptStorageManager {
    // MARK: - Value Operations

    /// Gets a stored value as JSON data.
    ///
    /// - Parameters:
    ///   - key: Storage key name.
    ///   - namespace: Script namespace for isolation.
    /// - Returns: The stored value as JSON data, or nil if not found.
    func getValue(key: String, namespace: String) async throws -> Data? {
        let id = UserScriptStorage.makeID(namespace: namespace, key: key)

        let descriptor = FetchDescriptor<UserScriptStorage>(
            predicate: #Predicate { $0.id == id },
        )

        guard let entry = try modelContext.fetch(descriptor).first else {
            return nil
        }

        return entry.jsonData
    }

    /// Sets a stored value from JSON data.
    ///
    /// - Parameters:
    ///   - key: Storage key name.
    ///   - jsonData: Value as JSON data.
    ///   - namespace: Script namespace for isolation.
    func setValue(key: String, jsonData: Data, namespace: String) async throws {
        let id = UserScriptStorage.makeID(namespace: namespace, key: key)

        let descriptor = FetchDescriptor<UserScriptStorage>(
            predicate: #Predicate { $0.id == id },
        )

        if let existing = try modelContext.fetch(descriptor).first {
            existing.jsonData = jsonData
        } else {
            let entry = UserScriptStorage(namespace: namespace, key: key, jsonData: jsonData)
            modelContext.insert(entry)
        }

        try modelContext.save()
    }

    /// Deletes a stored value.
    ///
    /// - Parameters:
    ///   - key: Storage key name.
    ///   - namespace: Script namespace for isolation.
    func deleteValue(key: String, namespace: String) async throws {
        let id = UserScriptStorage.makeID(namespace: namespace, key: key)

        let descriptor = FetchDescriptor<UserScriptStorage>(
            predicate: #Predicate { $0.id == id },
        )

        if let entry = try modelContext.fetch(descriptor).first {
            modelContext.delete(entry)
            try modelContext.save()
        }
    }

    /// Lists all keys stored for a namespace.
    ///
    /// - Parameter namespace: Script namespace.
    /// - Returns: Array of key names.
    func listValues(namespace: String) async throws -> [String] {
        let descriptor = FetchDescriptor<UserScriptStorage>(
            predicate: #Predicate { $0.namespace == namespace },
        )

        let entries = try modelContext.fetch(descriptor)
        return entries.map(\.key)
    }

    /// Clears all storage for a namespace.
    ///
    /// Used when uninstalling a script.
    ///
    /// - Parameter namespace: Script namespace to clear.
    func clearNamespace(_ namespace: String) async throws {
        let descriptor = FetchDescriptor<UserScriptStorage>(
            predicate: #Predicate { $0.namespace == namespace },
        )

        let entries = try modelContext.fetch(descriptor)
        for entry in entries {
            modelContext.delete(entry)
        }

        try modelContext.save()
    }
}
