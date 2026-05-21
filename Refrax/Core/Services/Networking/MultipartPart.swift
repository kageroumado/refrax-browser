import Foundation

/// A single part in a multipart/form-data request body.
nonisolated struct MultipartPart: Sendable {
    let name: String
    let filename: String?
    let contentType: String
    let data: Data
}
