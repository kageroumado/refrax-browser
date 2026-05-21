@preconcurrency import AppKit
import Foundation
import UniformTypeIdentifiers

/// Provides file promises for .webloc files during drag operations.
///
/// When a user drags a tab to Finder, this class generates the .webloc file
/// on demand. The file is created lazily when Finder requests it, avoiding
/// unnecessary disk I/O if the drop is cancelled.
///
/// ## .webloc Format
///
/// A .webloc file is a property list with a single "URL" key:
/// ```xml
/// <?xml version="1.0" encoding="UTF-8"?>
/// <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN">
/// <plist version="1.0">
/// <dict>
///     <key>URL</key>
///     <string>https://example.com</string>
/// </dict>
/// </plist>
/// ```
///
/// ## Usage
///
/// ```swift
/// let provider = WeblocFilePromiseProvider(url: tab.activePage.url, title: tab.displayTitle)
/// let draggingItem = NSDraggingItem(pasteboardWriter: provider)
/// ```
///
/// ## Thread Safety
///
/// File writing happens on a background operation queue to avoid blocking
/// the UI thread during drag operations.
final class WeblocFilePromiseProvider: NSFilePromiseProvider {
    /// URL to embed in the .webloc file.
    let url: URL

    /// Title used for the filename (sanitized for filesystem).
    let title: String

    /// Background queue for file operations.
    private lazy var fileOperationQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.refrax.webloc-writer"
        queue.qualityOfService = .userInitiated
        return queue
    }()

    /// Creates a file promise provider for a .webloc file.
    ///
    /// - Parameters:
    ///   - url: The URL to embed in the .webloc file
    ///   - title: Display title for the filename (will be sanitized)
    init(url: URL, title: String) {
        self.url = url
        self.title = title

        super.init()
        // UTI for web internet location files (.webloc)
        self.fileType = "com.apple.web-internet-location"
        // Set self as delegate to receive file promise callbacks
        self.delegate = self
    }

    /// Required override to match nonisolated superclass initializer.
    override nonisolated init() {
        self.url = .blank
        self.title = ""
        super.init()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - NSFilePromiseProviderDelegate

extension WeblocFilePromiseProvider: NSFilePromiseProviderDelegate {
    func filePromiseProvider(
        _: NSFilePromiseProvider,
        fileNameForType _: String,
    ) -> String {
        sanitizedFilename() + ".webloc"
    }

    func filePromiseProvider(
        _: NSFilePromiseProvider,
        writePromiseTo destinationURL: URL,
        completionHandler: @escaping ((any Error)?) -> Void,
    ) {
        // Create plist dictionary with URL
        let plist: [String: Any] = ["URL": url.absoluteString]

        do {
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: .xml,
                options: 0,
            )
            try data.write(to: destinationURL)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    func operationQueue(for _: NSFilePromiseProvider) -> OperationQueue {
        // Use background queue to avoid blocking UI
        fileOperationQueue
    }

    // MARK: - Filename Sanitization

    /// Sanitize title for use as a filename.
    ///
    /// Removes or replaces characters that are invalid in filesystem paths:
    /// - `/` and `:` are replaced with `-`
    /// - Control characters are removed
    /// - Leading/trailing whitespace is trimmed
    /// - Maximum length is 255 characters (filesystem limit)
    ///
    /// Falls back to hostname if title produces an empty or all-period name.
    private func sanitizedFilename() -> String {
        // Replace filesystem-invalid characters
        var sanitized = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "<", with: "")
            .replacingOccurrences(of: ">", with: "")
            .replacingOccurrences(of: "|", with: "-")

        // Remove control characters
        sanitized = sanitized.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
            .map { Character($0) }
            .reduce(into: "") { $0.append($1) }

        // Trim whitespace
        sanitized = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)

        // Enforce max length (leave room for .webloc extension)
        if sanitized.count > 250 {
            sanitized = String(sanitized.prefix(250))
        }

        // Filenames cannot be empty or all periods
        if sanitized.isEmpty || sanitized.allSatisfy({ $0 == "." }) {
            // Fall back to hostname
            if let host = url.host {
                sanitized = host
            } else {
                sanitized = "Untitled"
            }
        }

        return sanitized
    }
}

// MARK: - Factory Method

extension WeblocFilePromiseProvider {
    /// Create file promise providers for multiple dragged items.
    ///
    /// - Parameter items: Dragged items to create promises for
    /// - Returns: Array of file promise providers (one per item with a URL)
    static func providers(
        for items: [Sidebar.DragCoordinator.DraggedItem],
    ) -> [WeblocFilePromiseProvider] {
        items.compactMap { item -> WeblocFilePromiseProvider? in
            switch item {
            case let .tab(tab):
                let url = tab.activePage.url
                guard url != .blank else { return nil }
                return WeblocFilePromiseProvider(url: url, title: tab.displayTitle)

            case let .favorite(favorite):
                guard let url = favorite.url else { return nil }
                return WeblocFilePromiseProvider(url: url, title: favorite.displayName)

            case .group:
                return nil
            }
        }
    }
}
