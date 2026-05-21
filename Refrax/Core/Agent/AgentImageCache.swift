import AppKit
import Foundation

/// Actor for lazy-loading and caching agent chat images.
///
/// Images from chat history arrive as base64 strings. This cache decodes them
/// on-demand when cells become visible, preventing memory spikes when loading
/// history with many images.
///
/// ## Usage
///
/// ```swift
/// let image = await AgentImageCache.shared.image(for: attachment)
/// ```
actor AgentImageCache {
    /// Shared cache instance.
    static let shared = AgentImageCache()

    /// Cached decoded images by attachment ID.
    private var cache: [UUID: NSImage] = [:]

    /// In-progress decoding tasks to avoid duplicate work.
    private var pendingTasks: [UUID: Task<NSImage?, Never>] = [:]

    // MARK: - Public API

    /// Returns the decoded image for an attachment, loading lazily if needed.
    ///
    /// - Parameter attachment: The image attachment to load.
    /// - Returns: The decoded NSImage, or nil if decoding failed.
    func image(for attachment: AgentMessage.ImageAttachment) async -> NSImage? {
        let id = attachment.id

        // Check cache first
        if let cached = cache[id] {
            return cached
        }

        // If already loading, wait for that task
        if let pending = pendingTasks[id] {
            return await pending.value
        }

        // Start new decoding task
        let task = Task<NSImage?, Never> { [attachment] in
            await decodeImage(attachment)
        }
        pendingTasks[id] = task

        let result = await task.value

        // Clean up and cache
        pendingTasks[id] = nil
        if let image = result {
            cache[id] = image
        }

        return result
    }

    /// Checks if an image is already cached (no loading required).
    func isCached(_ attachmentId: UUID) -> Bool {
        cache[attachmentId] != nil
    }

    /// Clears the cache to free memory.
    func clearCache() {
        cache.removeAll()
    }

    /// Removes a specific image from cache.
    func evict(_ attachmentId: UUID) {
        cache[attachmentId] = nil
    }

    // MARK: - Private

    private func decodeImage(_ attachment: AgentMessage.ImageAttachment) async -> NSImage? {
        // If already loaded, use the data directly
        if let data = attachment.data {
            return NSImage(data: data)
        }

        // Decode base64 off the cooperative pool to avoid blocking
        guard let base64 = attachment.base64String else {
            return nil
        }

        return await Task.detached(priority: .userInitiated) {
            guard let data = Data(base64Encoded: base64),
                  let image = NSImage(data: data) else {
                return nil
            }
            return image
        }.value
    }
}
