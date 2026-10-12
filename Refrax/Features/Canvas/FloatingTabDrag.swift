import CoreTransferable
import Foundation
import UniformTypeIdentifiers

nonisolated struct FloatingTabDrag: Codable, Transferable {
    let id: UUID
    static let contentType = UTType(exportedAs: "website.refrax.floating-tab", conformingTo: .data)
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: contentType)
    }
}
