import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A favorite's identity for native dragging inside the control rail and the favorites drawer.
nonisolated struct ControlIslandFavoriteDrag: Codable, Transferable {
    let id: UUID

    static let contentType = UTType(exportedAs: "website.refrax.control-island-favorite", conformingTo: .data)

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: contentType)
    }
}
