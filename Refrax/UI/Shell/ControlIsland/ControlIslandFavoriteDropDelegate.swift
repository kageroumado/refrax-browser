import SwiftUI

/// Tracks insertion feedback while AppKit manages the drag image and cancellation.
struct ControlIslandFavoriteDropDelegate: DropDelegate {
    let isActive: Bool
    let onUpdate: (CGPoint) -> Void
    let onExit: () -> Void
    let onDrop: (CGPoint) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        isActive && info.hasItemsConforming(to: [ControlIslandFavoriteDrag.contentType])
    }

    func dropEntered(info: DropInfo) {
        onUpdate(info.location)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard validateDrop(info: info) else { return DropProposal(operation: .cancel) }
        onUpdate(info.location)
        return DropProposal(operation: .move)
    }

    func dropExited(info _: DropInfo) {
        onExit()
    }

    func performDrop(info: DropInfo) -> Bool {
        validateDrop(info: info) && onDrop(info.location)
    }
}
