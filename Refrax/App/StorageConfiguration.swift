import Foundation
import SwiftData

/// Storage mode for the application's SwiftData container.
enum StorageMode: Sendable {
    /// Persistent disk storage in Application Support.
    case disk

    /// Ephemeral in-memory storage (data lost on quit).
    case memory
}

extension CommandLine {
    /// Parsed command-line arguments for Refrax.
    struct Arguments: Sendable {
        /// Forces in-memory storage regardless of other settings.
        let forceInMemory: Bool

        /// User requested help output.
        let showHelp: Bool

        init() {
            let args = Set(CommandLine.arguments.dropFirst())
            self.forceInMemory = args.contains("--in-memory")
            self.showHelp = args.contains("--help") || args.contains("-h")
        }
    }

    /// Prints usage information to stdout.
    static func printUsage() {
        let executableName = (arguments.first as NSString?)?.lastPathComponent ?? "Refrax"
        let bundleID = Bundle.main.bundleIdentifier ?? "website.refrax.browser"
        print("""
        Usage: \(executableName) [options]
        
        Options:
          --in-memory    Use ephemeral in-memory storage (data not persisted)
          --help, -h     Show this help message
        
        Storage Location:
          ~/Library/Application Support/\(bundleID)/
        """)
    }
}

/// Configuration for SwiftData model container creation.
enum StorageConfiguration {
    /// Determines the storage mode based on build configuration and CLI arguments.
    static func resolveMode(from arguments: CommandLine.Arguments) -> StorageMode {
        if arguments.forceInMemory {
            return .memory
        }
        return .disk
    }

    /// Creates a ModelConfiguration for the given schema and storage mode.
    static func createModelConfiguration(
        schema: Schema,
        mode: StorageMode,
    ) -> ModelConfiguration {
        switch mode {
        case .memory:
            return ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true,
                cloudKitDatabase: .none,
            )

        case .disk:
            let storeURL = defaultStoreURL()
            return ModelConfiguration(
                schema: schema,
                url: storeURL,
                allowsSave: true,
                cloudKitDatabase: .none,
            )
        }
    }

    /// Returns the default store URL following macOS conventions.
    ///
    /// SwiftData stores are placed in:
    /// `~/Library/Application Support/{bundleIdentifier}/default.store`
    ///
    /// Debug and release builds use different bundle identifiers for isolation.
    static func defaultStoreURL() -> URL {
        Directories.appStorage.appendingPathComponent("default.store")
    }
}
