import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// A live favorite identity scoped to native dragging inside the control rail.
nonisolated struct ControlIslandFavoriteDrag: Codable, Transferable {
    let id: UUID

    static let contentType = UTType(exportedAs: "website.refrax.control-island-favorite", conformingTo: .data)

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: contentType)
    }
}
