import Foundation
import SwiftData

// MARK: - Persistence Helpers

extension BookmarksManager {
    /// Schedule a debounced save operation.
    ///
    /// Cancels any pending save and schedules a new one after the debounce delay.
    func scheduleSave() {
        _saver.scheduleSave()
    }

    /// Immediately save changes without debouncing.
    func saveImmediately() async {
        await _saver.saveImmediately()
    }
}
