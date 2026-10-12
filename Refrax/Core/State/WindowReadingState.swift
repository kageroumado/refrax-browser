import Foundation

/// Restores the selected pages of a window after the tab models have loaded.
nonisolated struct WindowReadingState: Codable, Equatable {
    let tabIDsBySpace: [UUID: UUID]
    let mainTabID: UUID?
}

