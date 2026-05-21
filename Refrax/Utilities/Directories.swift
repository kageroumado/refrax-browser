import Foundation

/// Central directory access with fallbacks for sandboxed/constrained environments.
///
/// All properties are computed once at first access (static let) and cached for the app lifetime.
/// This avoids repeated FileManager lookups and ensures consistent paths throughout the session.
///
/// ## Fallback Strategy
///
/// Each directory falls back gracefully if the preferred location is unavailable:
/// - `applicationSupport` -> temporary directory
/// - `downloads` -> documents -> temporary directory
/// - `desktop` -> downloads fallback
/// - `caches` -> temporary directory
///
/// Fallbacks are logged as warnings so issues can be diagnosed without crashing.
enum Directories: @unchecked Sendable {
    /// Application Support directory for persistent data.
    /// Falls back to temporary directory if unavailable.
    nonisolated static let applicationSupport: URL = {
        if let url = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
        ).first {
            return url
        }
        Logger.warning("Application Support unavailable, using temp directory", category: Logger.storage)
        return FileManager.default.temporaryDirectory
    }()

    /// Downloads directory.
    /// Falls back to Documents, then temp directory.
    nonisolated static let downloads: URL = {
        if let url = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask,
        ).first {
            return url
        }
        if let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask,
        ).first {
            Logger.warning("Downloads unavailable, using Documents", category: Logger.storage)
            return docs
        }
        Logger.warning("Downloads unavailable, using temp directory", category: Logger.storage)
        return FileManager.default.temporaryDirectory
    }()

    /// Desktop directory.
    /// Falls back to Downloads, then temp directory.
    nonisolated static let desktop: URL = {
        if let url = FileManager.default.urls(
            for: .desktopDirectory,
            in: .userDomainMask,
        ).first {
            return url
        }
        Logger.warning("Desktop unavailable, using Downloads fallback", category: Logger.storage)
        return downloads
    }()

    /// Caches directory.
    /// Falls back to temp directory.
    nonisolated static let caches: URL = {
        if let url = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask,
        ).first {
            return url
        }
        Logger.warning("Caches unavailable, using temp directory", category: Logger.storage)
        return FileManager.default.temporaryDirectory
    }()

    /// App-specific storage directory (Application Support/bundleID).
    /// Creates the directory if it doesn't exist.
    nonisolated static let appStorage: URL = {
        let bundleID = Bundle.main.bundleIdentifier ?? "website.refrax.browser"
        let directory = applicationSupport.appendingPathComponent(bundleID, isDirectory: true)

        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true,
                )
            } catch {
                Logger.error("Failed to create app storage directory: \(error)", category: Logger.storage)
            }
        }
        return directory
    }()
}
