@preconcurrency import Foundation
import os

/// A file presenter that tracks a download file through moves, renames, and deletions.
///
/// Unlike a simple file watcher, `DownloadFilePresenter` uses `NSFileCoordinator` to:
/// - Receive notifications when the file is moved by the user (e.g., in Finder)
/// - Coordinate writes to prevent data corruption during concurrent access
/// - Track the file across renames while maintaining access
///
/// ## Thread Safety
///
/// All presenter callbacks execute on `presenterQueue`. State updates are published
/// to the main actor via async dispatch.
///
/// ## Usage
///
/// ```swift
/// let presenter = try DownloadFilePresenter(url: downloadURL)
///
/// presenter.onMoved = { newURL in
///     print("File moved to: \(newURL)")
/// }
///
/// presenter.onDeleted = {
///     print("File was deleted")
/// }
/// ```
final class DownloadFilePresenter: NSObject, Sendable {
    // MARK: - Types

    /// Events that can occur to the presented file.
    enum FileEvent: Sendable {
        case moved(to: URL)
        case deleted
        case changed
    }

    // MARK: - Properties

    /// Current URL of the presented file.
    ///
    /// This may change if the file is moved or renamed.
    private let _url: OSAllocatedUnfairLock<URL?>

    /// The dedicated queue for file presenter operations.
    ///
    /// Apple recommends against using the main queue to avoid deadlocks.
    private let presenterQueue: OperationQueue

    /// Callback invoked when file events occur.
    ///
    /// Called on `presenterQueue`, dispatch to main if needed.
    private let eventHandler: @Sendable (FileEvent) -> Void

    /// Whether the presenter is currently registered with NSFileCoordinator.
    private let _isRegistered: OSAllocatedUnfairLock<Bool>

    // MARK: - NSFilePresenter

    nonisolated var presentedItemURL: URL? {
        _url.withLock { $0 }
    }

    nonisolated var presentedItemOperationQueue: OperationQueue {
        presenterQueue
    }

    // MARK: - Initialization

    /// Creates a file presenter for the given URL.
    ///
    /// - Parameters:
    ///   - url: The file URL to present. Must be a file URL.
    ///   - eventHandler: Callback for file events. Called on a background queue.
    /// - Throws: If the URL is not a file URL.
    init(url: URL, eventHandler: @escaping @Sendable (FileEvent) -> Void) throws {
        guard url.isFileURL else {
            throw CocoaError(.fileReadInvalidFileName)
        }

        self._url = OSAllocatedUnfairLock(initialState: url)
        self._isRegistered = OSAllocatedUnfairLock(initialState: false)
        self.eventHandler = eventHandler

        // Create dedicated queue for presenter operations
        let queue = OperationQueue()
        queue.name = "com.refrax.download-file-presenter"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        self.presenterQueue = queue

        super.init()

        // Register with file coordination system
        NSFileCoordinator.addFilePresenter(self)
        _isRegistered.withLock { $0 = true }
    }

    deinit {
        // Must unregister before deallocation - NSFileCoordinator retains presenters
        if _isRegistered.withLock({ $0 }) {
            NSFileCoordinator.removeFilePresenter(self)
        }
    }

    // MARK: - Public Methods

    /// Unregisters the file presenter.
    ///
    /// Call this when you no longer need to track the file. After calling,
    /// no further events will be received.
    ///
    /// This method is `nonisolated` to allow calling from `deinit`.
    nonisolated func unregister() {
        _isRegistered.withLock { registered in
            guard registered else { return }
            NSFileCoordinator.removeFilePresenter(self)
            registered = false
        }
    }

    /// Performs a coordinated write operation on the file.
    ///
    /// Use this for all write operations to ensure proper coordination with
    /// other processes that may be accessing the file.
    ///
    /// - Parameters:
    ///   - options: Write coordination options.
    ///   - block: The write operation to perform. Receives the actual URL to use.
    /// - Throws: Coordination errors or errors from the block.
    func coordinateWrite(
        options: NSFileCoordinator.WritingOptions = [],
        block: (URL) throws -> Void,
    ) throws {
        guard let url = presentedItemURL else {
            throw CocoaError(.fileNoSuchFile)
        }

        var coordinationError: NSError?
        var blockError: (any Error)?

        let coordinator = NSFileCoordinator(filePresenter: self)
        coordinator.coordinate(writingItemAt: url, options: options, error: &coordinationError) { actualURL in
            do {
                try block(actualURL)
            } catch {
                blockError = error
            }
        }

        if let error = coordinationError {
            throw error
        }
        if let error = blockError {
            throw error
        }
    }

    /// Performs a coordinated read operation on the file.
    ///
    /// - Parameters:
    ///   - options: Read coordination options.
    ///   - block: The read operation to perform. Receives the actual URL to use.
    /// - Returns: The result of the block.
    /// - Throws: Coordination errors or errors from the block.
    func coordinateRead<T>(
        options: NSFileCoordinator.ReadingOptions = [],
        block: (URL) throws -> T,
    ) throws -> T {
        guard let url = presentedItemURL else {
            throw CocoaError(.fileNoSuchFile)
        }

        var coordinationError: NSError?
        var result: Result<T, any Error>?

        let coordinator = NSFileCoordinator(filePresenter: self)
        coordinator.coordinate(readingItemAt: url, options: options, error: &coordinationError) { actualURL in
            do {
                result = try .success(block(actualURL))
            } catch {
                result = .failure(error)
            }
        }

        if let error = coordinationError {
            throw error
        }

        switch result {
        case let .success(value):
            return value
        case let .failure(error):
            throw error
        case .none:
            throw CocoaError(.fileReadUnknown)
        }
    }

    /// Performs a coordinated move operation.
    ///
    /// - Parameters:
    ///   - destination: The destination URL.
    ///   - block: The move operation. Receives source and destination URLs.
    /// - Throws: Coordination errors or errors from the block.
    func coordinateMove(
        to destination: URL,
        block: (URL, URL) throws -> Void,
    ) throws {
        guard let sourceURL = presentedItemURL else {
            throw CocoaError(.fileNoSuchFile)
        }

        var coordinationError: NSError?
        var blockError: (any Error)?

        let coordinator = NSFileCoordinator(filePresenter: self)
        coordinator.coordinate(
            writingItemAt: sourceURL,
            options: .forMoving,
            writingItemAt: destination,
            options: .forReplacing,
            error: &coordinationError,
        ) { actualSource, actualDestination in
            do {
                try block(actualSource, actualDestination)
                // Update tracked URL and notify coordinator INSIDE the block
                // This ensures proper ordering with other coordinators
                _url.withLock { $0 = actualDestination }
                coordinator.item(at: actualSource, didMoveTo: actualDestination)
            } catch {
                blockError = error
            }
        }

        if let error = coordinationError {
            throw error
        }
        if let error = blockError {
            throw error
        }
    }

    // MARK: - NSFilePresenter Protocol

    nonisolated func presentedItemDidMove(to newURL: URL) {
        _url.withLock { $0 = newURL }
        eventHandler(.moved(to: newURL))
    }

    nonisolated func presentedItemDidChange() {
        eventHandler(.changed)
    }

    nonisolated func accommodatePresentedItemDeletion(completionHandler: @escaping ((any Error)?) -> Void) {
        // Clean up our state
        _url.withLock { $0 = nil }
        eventHandler(.deleted)

        // Must always call completion handler
        completionHandler(nil)
    }

    nonisolated func relinquishPresentedItem(
        toReader reader: @Sendable @escaping ((@Sendable () -> Void)?) -> Void,
    ) {
        // Allow readers immediate access
        reader(nil)
    }

    nonisolated func relinquishPresentedItem(
        toWriter writer: @Sendable @escaping ((@Sendable () -> Void)?) -> Void,
    ) {
        // Allow writers immediate access
        writer(nil)
    }
}

// MARK: - NSFilePresenter Conformance

nonisolated extension DownloadFilePresenter: NSFilePresenter {}

// MARK: - Convenience Extensions

extension DownloadFilePresenter {
    /// The current URL, or nil if the file was deleted.
    var url: URL? {
        presentedItemURL
    }

    /// Whether the file still exists at the tracked location.
    var fileExists: Bool {
        guard let url = presentedItemURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
}
