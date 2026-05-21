import Foundation
import OSLog
import SwiftData

/// Consolidates debounced SwiftData save logic used across multiple managers.
///
/// Multiple managers (BookmarksManager, HistoryManager, BrowserState, SiteSettingsManager,
/// DownloadManager) use identical debounced save patterns. This class extracts that
/// common logic to reduce duplication and ensure consistent save behavior.
///
/// ## Usage
///
/// ```swift
/// @Observable
/// final class MyManager {
///     private let saver: DebouncedModelContextSaver
///
///     init(modelContext: ModelContext) {
///         self.saver = DebouncedModelContextSaver(
///             modelContext: modelContext,
///             debounceDelay: 0.5,
///             logCategory: Logger.data
///         )
///     }
///
///     func modifyData() {
///         // ... modify model objects ...
///         saver.scheduleSave()
///     }
/// }
/// ```
///
/// ## Thread Safety
///
/// This class is `@MainActor` isolated to match the managers that use it.
/// All SwiftData ModelContext access must occur on the main actor.
final class DebouncedModelContextSaver {
    // MARK: - Properties

    private let modelContext: ModelContext
    private let debounceDelay: TimeInterval
    private let logCategory: OSLog

    /// The pending save task, if any.
    private var saveTask: Task<Void, any Error>?

    // MARK: - Initialization

    /// Creates a debounced saver for the given context.
    ///
    /// - Parameters:
    ///   - modelContext: The SwiftData context to save.
    ///   - debounceDelay: Delay in seconds before saving (default 0.5).
    ///   - logCategory: Logger category for error messages (e.g., `Logger.data`).
    init(
        modelContext: ModelContext,
        debounceDelay: TimeInterval = 0.5,
        logCategory: OSLog,
    ) {
        self.modelContext = modelContext
        self.debounceDelay = debounceDelay
        self.logCategory = logCategory
    }

    // MARK: - Public API

    /// Schedules a debounced save operation.
    ///
    /// Cancels any pending save and schedules a new one after the debounce delay.
    /// Multiple rapid calls will only result in a single save after the delay.
    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task(priority: .utility) { @MainActor [weak self] in
            guard let self else { return }
            try await Task.sleep(for: .seconds(debounceDelay))

            if modelContext.hasChanges {
                do {
                    try modelContext.save()
                } catch {
                    Logger.error("Failed to save: \(error)", category: logCategory)
                }
            }
        }
    }

    /// Saves immediately without debouncing (async version).
    ///
    /// Use sparingly—prefer `scheduleSave()` for most operations.
    /// Cancels any pending debounced save and saves immediately.
    func saveImmediately() async {
        cancelPendingSave()
        performSave()
    }

    /// Saves immediately without debouncing (synchronous version).
    ///
    /// Use for synchronous contexts where async/await isn't available.
    /// Cancels any pending debounced save and saves immediately.
    func saveImmediatelySync() {
        cancelPendingSave()
        performSave()
    }

    /// Cancels any pending save without saving.
    ///
    /// Use when the manager is being deinitialized or the save is no longer needed.
    func cancelPendingSave() {
        saveTask?.cancel()
        saveTask = nil
    }

    // MARK: - Private

    private func performSave() {
        guard modelContext.hasChanges else { return }
        do {
            try modelContext.save()
        } catch {
            Logger.error("Save failed: \(error)", category: logCategory)
        }
    }
}
